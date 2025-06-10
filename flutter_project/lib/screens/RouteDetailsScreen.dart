import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/CreatePostScreen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import '../models/RunningRoute.dart';
import 'RouteViewScreen.dart';
import '../services/StorageService.dart';
import 'package:latlong2/latlong.dart';

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
  final double _mapHeight = 300;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.route.name;
    _descriptionController.text = widget.route.description;
    WidgetsBinding.instance.addPostFrameCallback((_) => _zoomToRoute());
  }

  void _zoomToRoute() {
    if (widget.route.points.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(
      widget.route.points.map((point) => point.coordinates).toList(),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    });
  }

  Future<void> addPhotoToRoute() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        setState(() => widget.route.addPhoto(pickedFile.path));
        await _storageService.updateRoutePhotos(
            widget.route.id, widget.route.photos);
      }
    } catch (e) {
      _showSnackBar('Ошибка при добавлении фотографии: $e');
    }
  }

  Future<void> _deletePhoto(int index) async {
    try {
      setState(() {
        widget.route.photos.removeAt(index);
      });
      await _storageService.updateRoutePhotos(
          widget.route.id, widget.route.photos);
      _showSnackBar('Фотография удалена');
    } catch (e) {
      _showSnackBar('Ошибка при удалении фотографии: $e');
    }
  }

  Future<void> _saveChanges() async {
    try {
      widget.route.name =
          _nameController.text.isEmpty ? "Без названия" : _nameController.text;
      widget.route.description = _descriptionController.text;

      await _storageService.updateRoute(widget.route);
      _showSnackBar('Изменения сохранены');
    } catch (e) {
      _showSnackBar('Ошибка при сохранении изменений: $e');
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали маршрута',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent, Colors.lightBlue],
              stops: [0.3, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          _AppBarIcon(
            icon: Icons.save,
            onPressed: _saveChanges,
            tooltip: 'Сохранить изменения',
          ),
          _AppBarIcon(
            icon: Icons.add_a_photo,
            onPressed: addPhotoToRoute,
            tooltip: 'Добавить фото',
          ),
          _AppBarIcon(
            icon: Icons.map,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RouteViewScreen(route: widget.route),
              ),
            ),
            tooltip: 'Полноэкранная карта',
          ),
          _AppBarIcon(
            icon: Icons.edit,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreatePostScreen(route: widget.route),
              ),
            ),
            tooltip: 'Создать пост',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color(0xFFF5F5F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Карта
              _MapSection(
                mapController: _mapController,
                route: widget.route,
                height: _mapHeight,
              ),

              // Основная информация
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _InfoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle('Название маршрута'),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: 'Введите название',
                              border: InputBorder.none,
                            ),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _InfoTile(
                            icon: Icons.timer,
                            label: 'Время',
                            value: widget.route.formattedDuration,
                          ),
                          _InfoTile(
                            icon: Icons.directions_run,
                            label: 'Дистанция',
                            value:
                                '${(widget.route.distance / 1000).toStringAsFixed(2)} км',
                          ),
                          _InfoTile(
                            icon: Icons.calendar_today,
                            label: 'Дата',
                            value: widget.route.formattedDate,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle('Описание маршрута'),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              hintText: 'Введите описание',
                              border: InputBorder.none,
                            ),
                            maxLines: 4,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Фотографии
              if (widget.route.photos.isNotEmpty)
                _PhotoGallery(
                  photos: widget.route.photos,
                  onDelete: _deletePhoto,
                ),

              if (widget.route.photos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'Добавьте фотографии маршрута',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Вспомогательные виджеты
class _AppBarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  const _AppBarIcon({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 24,
    );
  }
}

class _MapSection extends StatelessWidget {
  final MapController mapController;
  final RunningRoute route;
  final double height;

  const _MapSection({
    required this.mapController,
    required this.route,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter:
                route.points.firstOrNull?.coordinates ?? const LatLng(0, 0),
            initialZoom: 14.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
              userAgentPackageName: 'com.example.runTracker',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: route.points.map((p) => p.coordinates).toList(),
                  strokeWidth: 4.0,
                  color: Colors.blueAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Widget child;

  const _InfoCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
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
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blueAccent),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blueAccent,
          ),
        ),
      ],
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
      height: 280,
      child: PageView.builder(
        itemCount: photos.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.file(
                    File(photos[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.error, color: Colors.red),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
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
