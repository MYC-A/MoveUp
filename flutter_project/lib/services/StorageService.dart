import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/RunningRoute.dart';
import '../models/RoutePoint.dart';

class StorageService {
  static const String _tableName = 'routes';
  static const int _databaseVersion = 2;
  static Database? _database;

  // Получение размера базы данных
  Future<int> getDatabaseSize() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');
    final file = File(path);

    if (await file.exists()) {
      return file.lengthSync();
    } else {
      debugPrint('Файл базы данных не найден: $path');
      return 0;
    }
  }

  // Форматирование размера базы данных
  String formatSize(int sizeInBytes) {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes байт';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} КБ';
    } else {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
    }
  }

  // Создание резервной копии базы данных.
  // Вызывается явно (например, перед рискованной операцией), а не на каждую
  // запись, иначе копирование файла тормозит частые сохранения.
  Future<void> backupDatabase() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');
    final backupPath = join(dbPath.path, 'running_routes_backup.db');
    try {
      if (await File(path).exists()) {
        await File(path).copy(backupPath);
        debugPrint('Создана резервная копия базы данных: $backupPath');
      } else {
        debugPrint(
            'Файл базы данных не найден для резервного копирования: $path');
      }
    } catch (e) {
      debugPrint('Ошибка при создании резервной копии: $e');
    }
  }

  // Получение экземпляра базы данных
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  // Инициализация базы данных
  Future<Database> _initDatabase() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');

    try {
      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      // Проверка существования таблицы
      final tableExists = (Sqflite.firstIntValue(
                await db.rawQuery(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$_tableName'"),
              ) ??
              0) >
          0;
      if (!tableExists) {
        await _onCreate(db, _databaseVersion);
      } else {
        await _ensureRouteMetadataColumns(db);
      }

      return db;
    } catch (e) {
      debugPrint('Ошибка инициализации базы данных: $e');
      rethrow;
    }
  }

  // Создание таблицы
  Future<void> _onCreate(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $_tableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          points TEXT,
          distance REAL,
          date TEXT,
          duration INTEGER,
          description TEXT,
          photos TEXT,
          is_downloaded INTEGER DEFAULT 0,
          source_post_id TEXT
        )
      ''');
    } catch (e) {
      debugPrint('Ошибка при создании таблицы: $e');
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureRouteMetadataColumns(db);
    }
  }

  Future<void> _ensureRouteMetadataColumns(Database db) async {
    final tableExists = (Sqflite.firstIntValue(
              await db.rawQuery(
                  "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$_tableName'"),
            ) ??
            0) >
        0;
    if (!tableExists) {
      await _onCreate(db, _databaseVersion);
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info($_tableName)');
    final columnNames = columns
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();

    if (!columnNames.contains('is_downloaded')) {
      await db.execute(
        'ALTER TABLE $_tableName ADD COLUMN is_downloaded INTEGER DEFAULT 0',
      );
    }

    if (!columnNames.contains('source_post_id')) {
      await db
          .execute('ALTER TABLE $_tableName ADD COLUMN source_post_id TEXT');
    }

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_routes_source_post_id '
      'ON $_tableName(source_post_id)',
    );
  }

  // Сохранение маршрута. Возвращает id вставленной записи (для последующего
  // открытия/редактирования маршрута, например добавления фото).
  Future<int> saveRoute(RunningRoute route) async {
    final db = await database;
    try {
      final pointsJson =
          jsonEncode(route.points.map((point) => point.toJson()).toList());
      final photosJson = jsonEncode(route.photos);

      int insertedId = 0;
      await db.transaction((txn) async {
        insertedId = await txn.insert(
          _tableName,
          {
            'name': route.name,
            'points': pointsJson,
            'distance': route.distance,
            'date': route.date.toIso8601String(),
            'duration': route.duration.inSeconds,
            'description': route.description,
            'photos': photosJson,
            'is_downloaded': route.is_downloaded,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      debugPrint('Маршрут сохранён: ${route.name}');
      return insertedId;
    } catch (e) {
      debugPrint('Ошибка сохранения маршрута: $e');
      rethrow;
    }
  }

  // Скачивание маршрута
  Future<void> downloadRoute(RunningRoute route) async {
    final db = await database;
    try {
      final pointsJson =
          jsonEncode(route.points.map((point) => point.toJson()).toList());
      final photosJson = jsonEncode(route.photos);
      final sourcePostId = route.id.trim().isEmpty ? null : route.id.trim();

      await db.transaction((txn) async {
        await txn.insert(
          _tableName,
          {
            'name': route.name,
            'points': pointsJson,
            'distance': route.distance,
            'date': route.date.toIso8601String(),
            'duration': route.duration.inSeconds,
            'description': route.description,
            'photos': photosJson,
            'is_downloaded': 1,
            'source_post_id': sourcePostId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      debugPrint('Маршрут скачан: ${route.name}');
    } catch (e) {
      debugPrint('Ошибка скачивания маршрута: $e');
      rethrow;
    }
  }

  // Загрузка маршрутов (новые сверху). Лимит ограничивает память на больших БД.
  Future<List<RunningRoute>> loadRoutes({int limit = 500}) async {
    final db = await database;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        orderBy: 'date DESC',
        limit: limit,
      );

      return List.generate(maps.length, (i) {
        final pointsJson = maps[i]['points'] as String?;
        List<RoutePoint> points = [];
        if (pointsJson != null && pointsJson.isNotEmpty) {
          try {
            points = (jsonDecode(pointsJson) as List)
                .map((point) => RoutePoint.fromJson(point))
                .toList();
          } catch (e) {
            debugPrint(
                'Ошибка десериализации точек для маршрута ${maps[i]['name']}: $e');
          }
        }

        final photosJson = maps[i]['photos'] as String?;
        List<String> photos = [];
        if (photosJson != null && photosJson.isNotEmpty) {
          try {
            photos = (jsonDecode(photosJson) as List)
                .map((item) => item.toString())
                .toList();
          } catch (e) {
            debugPrint(
                'Ошибка десериализации фотографий для маршрута ${maps[i]['name']}: $e');
          }
        }

        return RunningRoute(
          id: maps[i]['id'].toString(),
          name: maps[i]['name'] ?? 'Без названия',
          points: points,
          distance: maps[i]['distance'] ?? 0.0,
          date: DateTime.tryParse(maps[i]['date'] ?? '') ?? DateTime.now(),
          duration: Duration(seconds: maps[i]['duration'] ?? 0),
          description: maps[i]['description'] ?? '',
          photos: photos,
          is_downloaded: maps[i]['is_downloaded'] ?? 0,
        );
      });
    } catch (e, stackTrace) {
      // Ошибку чтения БД пробрасываем — экран покажет состояние ошибки,
      // а не пустой список (это разные вещи для пользователя).
      debugPrint('Ошибка при загрузке маршрутов: $e, StackTrace: $stackTrace');
      rethrow;
    }
  }

  // Удаление маршрута с обработкой связанных файлов
  Future<void> deleteRoute(String id) async {
    final db = await database;
    try {
      // Сначала получаем информацию о маршруте
      final route = await db.query(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (route.isNotEmpty) {
        // Удаляем связанные фотографии (если они хранятся локально)
        final photosJson = route.first['photos'] as String?;
        if (photosJson != null && photosJson.isNotEmpty) {
          try {
            final photos = (jsonDecode(photosJson) as List).cast<String>();
            for (final photoPath in photos) {
              if (photoPath.startsWith('/')) {
                // Проверяем, что это локальный путь
                final file = File(photoPath);
                if (await file.exists()) {
                  await file.delete();
                  debugPrint('Удалён файл фотографии: $photoPath');
                }
              }
            }
          } catch (e) {
            debugPrint('Ошибка при удалении фотографий: $e');
          }
        }

        // Удаляем запись из базы данных
        await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
        debugPrint('Маршрут с id $id удалён');
      }
    } catch (e) {
      debugPrint('Ошибка удаления маршрута: $e');
      rethrow;
    }
  }

  Future<void> updateRoute(RunningRoute route) async {
    final db = await database;
    try {
      final pointsJson =
          jsonEncode(route.points.map((point) => point.toJson()).toList());
      final photosJson = jsonEncode(route.photos);

      await db.transaction((txn) async {
        final updatedRows = await txn.update(
          _tableName,
          {
            'name': route.name,
            'points': pointsJson,
            'distance': route.distance,
            'date': route.date.toIso8601String(),
            'duration': route.duration.inSeconds,
            'description': route.description,
            'photos': photosJson,
            'is_downloaded': route.is_downloaded,
          },
          where: 'id = ?',
          whereArgs: [route.id],
        );
        if (updatedRows == 0) {
          debugPrint('Маршрут с id ${route.id} не найден для обновления');
        } else {
          debugPrint('Маршрут обновлён: ${route.name} (id: ${route.id})');
        }
      });
    } catch (e) {
      debugPrint('Ошибка обновления маршрута: $e');
      rethrow;
    }
  }

  // Обновление фотографий маршрута
  Future<void> updateRoutePhotos(String routeId, List<String> photos) async {
    final db = await database;
    try {
      final photosJson = jsonEncode(photos);
      await db.update(
        _tableName,
        {'photos': photosJson},
        where: 'id = ?',
        whereArgs: [routeId],
      );
      debugPrint('Фотографии маршрута обновлены: $routeId');
    } catch (e) {
      debugPrint('Ошибка обновления фотографий: $e');
    }
  }

  // Закрытие базы данных
  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
      debugPrint('База данных закрыта');
    }
  }
}
