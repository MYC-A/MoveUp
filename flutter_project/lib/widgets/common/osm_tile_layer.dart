import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services_api/cached_tile_provider.dart';

const double osmMapMinZoom = 3.0;
const double osmMapMaxZoom = 18.0;

/// Единый тайловый слой OSM для всего приложения: одинаковый вид и поведение
/// во всех картах — лента, ЛК, события, трекер, детали маршрута. Используйте
/// везде вместо собственных `TileLayer(...)`, чтобы не было разнобоя.
///
/// [retina] на публичном OSM лучше держать выключенным: URL без `{r}` включает
/// simulated-retina в flutter_map, а это запрашивает 4 тайла вместо одного и
/// чаще приводит к 429/серым тайлам на мобильной сети.
///
/// [cacheTiles] включает дисковый кэш для мини-карт. Для живых интерактивных
/// карт можно выключить кэш: штатный `NetworkTileProvider` использует retry и
/// быстрее восстанавливается после временных сетевых ошибок.
TileLayer osmTileLayer({bool retina = false, bool cacheTiles = true}) {
  if (kDebugMode) {
    debugPrint(
      'OSM: create tile layer url=https://tile.openstreetmap.org/{z}/{x}/{y}.png '
      'retina=$retina cacheTiles=$cacheTiles',
    );
  }

  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.moveup.app',
    tileProvider: cacheTiles
        ? CachedTileProvider()
        : NetworkTileProvider(headers: CachedTileProvider.osmHeaders),
    minNativeZoom: 0,
    maxNativeZoom: 19,
    minZoom: 0,
    maxZoom: 19,
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
