import 'package:flutter/material.dart';
import '../models/RunningRoute.dart';
import '../services/StorageService.dart';
import 'RouteDetailsScreen.dart';

class RouteHistoryScreen extends StatefulWidget {
  const RouteHistoryScreen({super.key});

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  late TabController _tabController;

  List<RunningRoute> myRoutes = [];
  List<RunningRoute> downloadedRoutes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRoutes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutes() async {
    setState(() => _isLoading = true);
    try {
      final routes = await _storageService.loadRoutes();
      setState(() {
        myRoutes = routes.where((route) => route.is_downloaded == 0).toList();
        downloadedRoutes =
            routes.where((route) => route.is_downloaded == 1).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Ошибка загрузки маршрутов');
    }
  }

  Future<void> _deleteRoute(RunningRoute route) async {
    final shouldDelete = await _showDeleteConfirmationDialog(route.name);
    if (!shouldDelete) return;

    try {
      await _storageService.deleteRoute(route.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Маршрут "${route.name}" удалён'),
            action: SnackBarAction(
              label: 'Отменить',
              onPressed: () => _restoreRoute(route),
            ),
          ),
        );
      }
      await _loadRoutes();
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Ошибка при удалении маршрута');
      }
    }
  }

  Future<bool> _showDeleteConfirmationDialog(String routeName) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Подтверждение удаления'),
            content:
                Text('Вы уверены, что хотите удалить маршрут "$routeName"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child:
                    const Text('Удалить', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restoreRoute(RunningRoute route) async {
    try {
      await _storageService.saveRoute(route);
      await _loadRoutes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Маршрут восстановлен')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Ошибка восстановления маршрута');
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История маршрутов'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Мои маршруты'),
            Tab(text: 'Загруженные маршруты'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRouteList(myRoutes, canDelete: true),
                _buildRouteList(downloadedRoutes, canDelete: true),
              ],
            ),
    );
  }

  Widget _buildRouteList(List<RunningRoute> routes, {bool canDelete = false}) {
    if (routes.isEmpty) {
      return const Center(
        child: Text(
          'Нет сохраненных маршрутов',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: routes.length,
        itemBuilder: (context, index) {
          final route = routes[index];
          return _buildRouteItem(route, canDelete);
        },
      ),
    );
  }

  Widget _buildRouteItem(RunningRoute route, bool canDelete) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToRouteDetails(route),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteRoute(route),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Дистанция: ${(route.distance / 1000).toStringAsFixed(2)} км',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Длительность: ${_formatDuration(route.duration)}',
                style: const TextStyle(fontSize: 14),
              ),
              if (route.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  route.description,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}ч ${minutes}м ${seconds}с';
    } else if (minutes > 0) {
      return '${minutes}м ${seconds}с';
    } else {
      return '${seconds}с';
    }
  }

  void _navigateToRouteDetails(RunningRoute route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteDetailsScreen(route: route),
      ),
    );
  }
}
