import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// [TileProvider], кэширующий тайлы карты в памяти и на диске через
/// `cached_network_image`.
///
/// Зачем: дефолтный сетевой провайдер заново качает и декодирует одни и те же
/// тайлы при каждом появлении карты (в ленте, событиях, на экранах деталей) и
/// между запусками приложения. Кэш убирает повторные загрузки/декодирование —
/// это снимает микро-фризы при прокрутке и снижает нагрузку на тайл-серверы OSM.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(
      getTileUrl(coordinates, options),
      headers: headers,
    );
  }
}
