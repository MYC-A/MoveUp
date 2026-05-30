import 'package:flutter_map/flutter_map.dart';

import '../../services_api/cached_tile_provider.dart';

/// Единый тайловый слой OSM для всего приложения: одинаковый вид и поведение
/// (кэш тайлов, предзагрузка соседних, перезапрос ошибочных) во всех картах —
/// лента, ЛК, события, трекер, детали маршрута. Используйте везде вместо
/// собственных `TileLayer(...)`, чтобы не было разнобоя и серых пятен.
TileLayer osmTileLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.moveup.app',
    tileProvider: CachedTileProvider(),
    keepBuffer: 3,
    panBuffer: 1,
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    tileDisplay: const TileDisplay.fadeIn(
      duration: Duration(milliseconds: 180),
      startOpacity: 0,
      reloadStartOpacity: 0,
    ),
  );
}
