import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/CreatePostScreen.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/theme/app_radii.dart';
import 'package:flutter_application_1/theme/app_spacing.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/RunningRoute.dart';
import '../services/StorageService.dart';
import 'RouteViewScreen.dart';

class RouteDetailsScreen extends StatefulWidget {
  final RunningRoute route;

  const RouteDetailsScreen({super.key, required this.route});

  @override
  _RouteDetailsScreenState createState() => _RouteDetailsScreenState();
}

class _RouteDetailsScreenState extends State<RouteDetailsScreen> {
  final StorageService _storageService = StorageService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final MapController _mapController = MapController();

  bool get _isDownloaded => widget.route.is_downloaded == 1;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.route.name;
    _descriptionController.text = widget.route.description;
    WidgetsBinding.instance.addPostFrameCallback((_) => _zoomToRoute());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _zoomToRoute() {
    final points = _validPoints;
    if (points.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14);
        return;
      }

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      );
    });
  }

  List<LatLng> get _validPoints => widget.route.points
      .map((point) => point.coordinates)
      .where(_isValidPoint)
      .toList();

  bool _isValidPoint(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  Future<void> addPhotoToRoute() async {
    if (_isDownloaded) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() => widget.route.addPhoto(pickedFile.path));
        await _storageService.updateRoutePhotos(
          widget.route.id,
          widget.route.photos,
        );
      }
    } catch (e) {
      _showSnackBar('Ошибка при добавлении фотографии: $e');
    }
  }

  Future<void> _deletePhoto(int index) async {
    if (_isDownloaded) return;

    try {
      setState(() {
        widget.route.photos.removeAt(index);
      });
      await _storageService.updateRoutePhotos(
        widget.route.id,
        widget.route.photos,
      );
      _showSnackBar('Фотография удалена');
    } catch (e) {
      _showSnackBar('Ошибка при удалении фотографии: $e');
    }
  }

  Future<void> _saveChanges() async {
    try {
      widget.route.name = _nameController.text.trim().isEmpty
          ? 'Без названия'
          : _nameController.text.trim();
      widget.route.description = _descriptionController.text.trim();

      await _storageService.updateRoute(widget.route);
      if (!mounted) return;
      _showSnackBar('Изменения сохранены');
      setState(() {});
    } catch (e) {
      _showSnackBar('Ошибка при сохранении изменений: $e');
    }
  }

  void _openRouteView() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteViewScreen(route: widget.route),
      ),
    );
  }

  void _createPost() {
    if (_isDownloaded) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreatePostScreen(route: widget.route),
      ),
    );
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Маршрут'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveChanges,
            tooltip: 'Сохранить изменения',
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen_outlined),
            onPressed: _openRouteView,
            tooltip: 'Открыть карту',
          ),
          if (!_isDownloaded) ...[
            IconButton(
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: addPhotoToRoute,
              tooltip: 'Добавить фото',
            ),
            IconButton(
              icon: const Icon(Icons.publish_outlined),
              onPressed: _createPost,
              tooltip: 'Создать пост',
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          _RouteMapPreview(
            mapController: _mapController,
            points: _validPoints,
          ),
          const SizedBox(height: AppSpacing.md),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.route.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _isDownloaded
                                ? 'Загруженный маршрут для повторной пробежки'
                                : 'Сохраненный маршрут',
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _RouteBadge(
                      icon: _isDownloaded
                          ? Icons.download_done_outlined
                          : Icons.bookmark_added_outlined,
                      label: _isDownloaded ? 'Загружен' : 'Сохранен',
                      color:
                          _isDownloaded ? AppColors.route : AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _openRouteView,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Пробежать по маршруту'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.route_outlined,
                  label: 'Дистанция',
                  value:
                      '${(widget.route.distance / 1000).toStringAsFixed(2)} км',
                  color: AppColors.route,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.timer_outlined,
                  label: 'Время',
                  value: widget.route.formattedDuration,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Дата',
                  value: widget.route.formattedDate,
                  color: AppColors.activity,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Название'),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Название маршрута',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _SectionTitle('Описание'),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Заметки для будущей пробежки',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          if (_isDownloaded) ...[
            const SizedBox(height: AppSpacing.md),
            const _DownloadedHint(),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Фотографии',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: addPhotoToRoute,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Добавить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (widget.route.photos.isEmpty)
                    Text(
                      'Фотографий пока нет.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    )
                  else
                    _PhotoGallery(
                      photos: widget.route.photos,
                      onDelete: _deletePhoto,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _createPost,
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Создать пост из маршрута'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteMapPreview extends StatelessWidget {
  final MapController mapController;
  final List<LatLng> points;

  const _RouteMapPreview({required this.mapController, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: 280,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('Нет точек маршрута'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 300,
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.runTracker',
            ),
            if (points.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 5,
                    color: AppColors.route,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                _routeMarker(points.first, 'Старт', AppColors.success),
                if (points.length > 1)
                  _routeMarker(points.last, 'Финиш', AppColors.danger),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Marker _routeMarker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 74,
      height: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_pin, color: color, size: 34),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(AppRadii.xs),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RouteBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _DownloadedHint extends StatelessWidget {
  const _DownloadedHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.routeSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.route.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.route),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Загруженный маршрут сохранен как план для пробежки. Здесь можно менять только название и описание, без фото и публикации в ленту.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final List<String> photos;
  final Function(int) onDelete;

  const _PhotoGallery({required this.photos, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: PageView.builder(
        itemCount: photos.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(photos[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.error_outline, color: AppColors.danger),
                    ),
                  ),
                ),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onDelete(index),
                    tooltip: 'Удалить фото',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
