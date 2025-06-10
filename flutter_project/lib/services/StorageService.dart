import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/RunningRoute.dart';
import '../models/RoutePoint.dart';

class StorageService {
  static const String _tableName = 'routes';
  static Database? _database;

  // Получение размера базы данных
  Future<int> getDatabaseSize() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');
    final file = File(path);

    if (await file.exists()) {
      return file.lengthSync();
    } else {
      print('Файл базы данных не найден: $path');
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

  // Вывод размера базы данных
  void printDatabaseSize() async {
    try {
      final sizeInBytes = await getDatabaseSize();
      final formattedSize = formatSize(sizeInBytes);
      print('Размер базы данных: $formattedSize');
    } catch (e) {
      print('Ошибка при получении размера базы данных: $e');
    }
  }

  // Создание резервной копии базы данных
  Future<void> backupDatabase() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');
    final backupPath = join(dbPath.path, 'running_routes_backup.db');
    try {
      if (await File(path).exists()) {
        await File(path).copy(backupPath);
        print('Создана резервная копия базы данных: $backupPath');
      } else {
        print('Файл базы данных не найден для резервного копирования: $path');
      }
    } catch (e) {
      print('Ошибка при создании резервной копии: $e');
    }
  }

  // Получение экземпляра базы данных
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      print('База данных уже открыта');
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  // Инициализация базы данных
  Future<Database> _initDatabase() async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, 'running_routes.db');
    print('Инициализация базы данных по пути: $path');

    try {
      final exists = await databaseExists(path);
      print('База данных существует: $exists');

      final db = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
        onOpen: (db) async {
          print('База данных открыта, версия: ${await db.getVersion()}');
        },
      );

      // Проверка существования таблицы
      final tableExists = (Sqflite.firstIntValue(
                await db.rawQuery(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$_tableName'"),
              ) ??
              0) >
          0;
      print('Таблица $_tableName существует: $tableExists');
      if (!tableExists) {
        print('Создаём таблицу $_tableName');
        await _onCreate(db, 1);
      }

      return db;
    } catch (e) {
      print('Ошибка инициализации базы данных: $e');
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
          is_downloaded INTEGER DEFAULT 0
        )
      ''');
      print('Таблица создана: $_tableName');
    } catch (e) {
      print('Ошибка при создании таблицы: $e');
      rethrow;
    }
  }

  // Сохранение маршрута
  Future<void> saveRoute(RunningRoute route) async {
    final db = await database;
    try {
      final pointsJson =
          jsonEncode(route.points.map((point) => point.toJson()).toList());
      final photosJson = jsonEncode(route.photos);

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
            'is_downloaded': route.is_downloaded ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      print('Маршрут сохранён: ${route.name}');
      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tableName'));
      print('Количество маршрутов в базе: $count');
      final maps = await db.query(_tableName);
      print('Содержимое таблицы после сохранения: $maps');
      printDatabaseSize();
      await backupDatabase();
    } catch (e) {
      print('Ошибка сохранения маршрута: $e');
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      print('Маршрут скачан: ${route.name}');
      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tableName'));
      print('Количество маршрутов в базе: $count');
      final maps = await db.query(_tableName);
      print('Содержимое таблицы после скачивания: $maps');
      printDatabaseSize();
      await backupDatabase();
    } catch (e) {
      print('Ошибка скачивания маршрута: $e');
      rethrow;
    }
  }

  // Загрузка маршрутов
  Future<List<RunningRoute>> loadRoutes() async {
    final db = await database;
    print('Загрузка маршрутов из базы данных...');

    try {
      final List<Map<String, dynamic>> maps = await db.query(_tableName);
      print('Загружено записей из таблицы: ${maps.length}');
      print('Содержимое таблицы: $maps');

      return List.generate(maps.length, (i) {
        final pointsJson = maps[i]['points'] as String?;
        List<RoutePoint> points = [];
        if (pointsJson != null && pointsJson.isNotEmpty) {
          try {
            points = (jsonDecode(pointsJson) as List)
                .map((point) => RoutePoint.fromJson(point))
                .toList();
          } catch (e) {
            print(
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
            print(
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
      print('Ошибка при загрузке маршрутов: $e, StackTrace: $stackTrace');
      return [];
    }
  }

  // Удаление маршрута
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
                  print('Удалён файл фотографии: $photoPath');
                }
              }
            }
          } catch (e) {
            print('Ошибка при удалении фотографий: $e');
          }
        }

        // Удаляем запись из базы данных
        await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
        print('Маршрут с id $id удалён');
        printDatabaseSize();
      }
    } catch (e) {
      print('Ошибка удаления маршрута: $e');
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
            'is_downloaded': route.is_downloaded ?? 0,
          },
          where: 'id = ?',
          whereArgs: [route.id],
        );
        if (updatedRows == 0) {
          print('Маршрут с id ${route.id} не найден для обновления');
        } else {
          print('Маршрут обновлён: ${route.name} (id: ${route.id})');
        }
      });

      final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tableName'));
      print('Количество маршрутов в базе: $count');
      final maps = await db.query(_tableName);
      print('Содержимое таблицы после обновления: $maps');
      printDatabaseSize();
      await backupDatabase();
    } catch (e) {
      print('Ошибка обновления маршрута: $e');
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
      print('Фотографии маршрута обновлены: $routeId');
    } catch (e) {
      print('Ошибка обновления фотографий: $e');
    }
  }

  // Закрытие базы данных
  Future<void> closeDatabase() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
      print('База данных закрыта');
    }
  }
}
