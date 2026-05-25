import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/config/app_config.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class PhotoViewer extends StatelessWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoViewer({
    Key? key,
    required this.photoUrls,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: PhotoViewGallery.builder(
        itemCount: photoUrls.length,
        builder: (context, index) {
          final imageUrl = photoUrls[index].replaceAll(
            'localhost:9000',
            AppConfig.mediaBaseUrlWithoutScheme,
          );
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(
              imageUrl,
              cacheManager: CacheManager(
                Config(
                  'customCacheKey',
                  stalePeriod: const Duration(days: 7),
                  maxNrOfCacheObjects: 100,
                ),
              ),
            ),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
          );
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(
          color: Colors.white,
        ),
        pageController: PageController(initialPage: initialIndex),
        onPageChanged: (index) {},
      ),
    );
  }
}
