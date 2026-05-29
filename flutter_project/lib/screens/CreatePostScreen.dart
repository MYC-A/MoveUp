import 'package:flutter/material.dart';
import 'package:flutter_application_1/services_api/post_service.dart';
import 'package:flutter_application_1/widgets/route_details/RouteMap.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/RunningRoute.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class CreatePostScreen extends StatefulWidget {
  final RunningRoute route;

  const CreatePostScreen({super.key, required this.route});

  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late RunningRoute _route;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final PostService _postService = PostService();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _route = RunningRoute(
      id: widget.route.id,
      name: widget.route.name,
      points: List.from(widget.route.points),
      distance: widget.route.distance,
      date: widget.route.date,
      duration: widget.route.duration,
      description: widget.route.description,
      photos: List.from(widget.route.photos),
      is_downloaded: widget.route.is_downloaded,
    );
    _nameController.text = _route.name;
    _descriptionController.text = _route.description;
  }

  Future<void> _addPhoto() async {
    try {
      if (_route.photos.length >= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Максимум 3 фотографии')),
        );
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      final File originalFile = File(pickedFile.path);
      final String compressedPath =
          '${pickedFile.path.replaceAll(RegExp(r'\.\w+$'), '')}_compressed.jpg';
      final XFile? compressedXFile =
          await FlutterImageCompress.compressAndGetFile(
        pickedFile.path,
        compressedPath,
        quality: 70,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );

      final File file =
          compressedXFile != null ? File(compressedXFile.path) : originalFile;

      setState(() {
        _route.photos.add(file.path);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка добавления фото: $e')),
      );
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _route.photos.removeAt(index);
    });
  }

  String _formatDistance(double meters) {
    final km = meters / 1000;
    return '${km.toStringAsFixed(2)} км';
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _savePost() async {
    // Защита: пост нельзя создавать из скачанного чужого маршрута.
    if (_route.is_downloaded == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя создать пост из скачанного маршрута'),
        ),
      );
      return;
    }
    try {
      final routeData = _route.points.map((point) {
        return {
          'latitude': point.coordinates.latitude,
          'longitude': point.coordinates.longitude,
          'timestamp': point.timestamp.toIso8601String(),
        };
      }).toList();

      await _postService.createPost(
        content: _descriptionController.text,
        distance: _route.distance,
        duration: _route.duration.inSeconds,
        routeData: routeData,
        photoPaths: _route.photos,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пост успешно создан!')),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка создания поста: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый пост'),
        actions: [
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Опубликовать пост',
            onPressed: _savePost,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Превью маршрута, чтобы было видно, что именно публикуем.
            if (_route.points.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: RouteMap(route: _route),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.straighten,
                      label: 'Дистанция',
                      value: _formatDistance(_route.distance),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.timer_outlined,
                      label: 'Время',
                      value: _formatDuration(_route.duration),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Создание нового поста',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название маршрута',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Описание маршрута',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            const Text(
              'Фотографии',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _route.photos.length + 1,
              itemBuilder: (context, index) {
                if (index == _route.photos.length) {
                  return GestureDetector(
                    onTap: _addPhoto,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: const Center(
                        child: Icon(Icons.add_a_photo,
                            size: 36, color: Colors.grey),
                      ),
                    ),
                  );
                } else {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_route.photos[index]),
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 18),
                              onPressed: () => _removePhoto(index),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
