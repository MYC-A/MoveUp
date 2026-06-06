import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services_api/cached_tile_provider.dart';

/// Единый тайловый слой OSM для всего приложения: одинаковый вид и поведение
/// (кэш тайлов, предзагрузка соседних, перезапрос ошибочных) во всех картах —
/// лента, ЛК, события, трекер, детали маршрута. Используйте везде вместо
/// собственных `TileLayer(...)`, чтобы не было разнобоя и серых пятен.
///
/// [retina] — на экранах с высокой плотностью пикселей подтягивает тайлы
/// большего зума и сжимает их, убирая «мыло». Включайте на крупных/статичных
/// картах (детали маршрута, трекер). По умолчанию выключено, чтобы не удваивать
/// сетевые запросы в списках с множеством мини-карт (лента).
TileLayer osmTileLayer({bool retina = false}) {
  if (kDebugMode) {
    debugPrint(
      'OSM: create tile layer url=https://tile.openstreetmap.org/{z}/{x}/{y}.png '
      'retina=$retina',
    );
  }

  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.moveup.app',
    tileProvider: CachedTileProvider(),
    keepBuffer: 3,
    panBuffer: 1,
    retinaMode: retina,
    errorTileCallback: (tile, error, stackTrace) {
      if (!kDebugMode) return;
      debugPrint(
        'OSM: tile load failed z=${tile.coordinates.z} '
        'x=${tile.coordinates.x} y=${tile.coordinates.y}: $error',
      );
    },
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    tileDisplay: const TileDisplay.fadeIn(
      duration: Duration(milliseconds: 180),
      startOpacity: 0,
      reloadStartOpacity: 0,
    ),
  );
}
