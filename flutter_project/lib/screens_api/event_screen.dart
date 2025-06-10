import 'package:flutter/material.dart';
import 'package:flutter_application_1/models_api/Event.dart';
import 'package:flutter_application_1/screens_api/CreateEventScreen.dart';
import 'package:flutter_application_1/services_api/EventService.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_application_1/services_api/Helper.dart';
import 'package:flutter_application_1/services_api/EventTranslations.dart';

class EventScreen extends StatefulWidget {
  @override
  _EventScreenState createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  final EventService _eventService = EventService();
  final List<Event> _events = [];
  int _skip = 0;
  final int _limit = 10;
  bool _isLoading = false;
  bool _hasMore = true;
  final List<MapController> _mapControllers = [];
  final ScrollController _scrollController = ScrollController();
  int? _latestEventId;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    for (var controller in _mapControllers) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents({bool refresh = false}) async {
    if (_isLoading || (!_hasMore && !refresh)) return;
    setState(() {
      _isLoading = true;
      if (refresh) {
        _skip = 0;
        _events.clear();
        _mapControllers.clear();
        _hasMore = true;
        _latestEventId = null;
      }
    });

    try {
      final newEvents = await _eventService.getEvents(
        skip: _skip,
        limit: _limit,
        sortBy: 'id',
        sortOrder: 'desc',
      );
      setState(() {
        _events.addAll(newEvents);
        _skip += _limit;
        _hasMore = newEvents.length == _limit;
        _mapControllers.addAll(
            List.generate(newEvents.length, (index) => MapController()));
        if (newEvents.isNotEmpty) {
          _latestEventId =
              _events.map((e) => e.id).reduce((a, b) => a > b ? a : b);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки мероприятий: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshEvents() async {
    if (_isRefreshing || _latestEventId == null) return;

    setState(() {
      _isRefreshing = true;
    });

    // Анимация прокрутки к началу
    await _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    try {
      final newEvents = await _eventService.getEvents(
        skip: 0,
        limit: _limit,
        sortBy: 'id',
        sortOrder: 'desc',
      );

      final newEventsToAdd =
          newEvents.where((event) => event.id > _latestEventId!).toList();
      if (newEventsToAdd.isNotEmpty) {
        setState(() {
          _events.insertAll(0, newEventsToAdd);
          _mapControllers.insertAll(0,
              List.generate(newEventsToAdd.length, (index) => MapController()));
          _latestEventId = _events.first.id;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${newEventsToAdd.length} новых мероприятий')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обновления: $e')),
      );
    } finally {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  void _zoomToRoute(List<LatLng> routePoints, MapController mapController) {
    if (routePoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(routePoints);
    mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return "Не указано";
    return Helper.formatDateTime(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Список мероприятий',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh, color: Colors.black),
            onPressed: _refreshEvents,
          ),
          IconButton(
            icon: Icon(Icons.add, color: Colors.black),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateEventScreen()),
              );
              if (result == true) {
                _refreshEvents();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshEvents,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo.metrics.pixels ==
                    scrollInfo.metrics.maxScrollExtent &&
                _hasMore &&
                !_isLoading) {
              _loadEvents();
            }
            return true;
          },
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                itemCount: _events.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _events.length) {
                    return Center(child: CircularProgressIndicator());
                  }
                  final event = _events[index];
                  return _buildEventCard(event, index);
                },
              ),
              if (_isRefreshing)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      margin: EdgeInsets.all(8),
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(Event event, int index) {
    return Card(
      margin: EdgeInsets.all(8.0),
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.map, color: Colors.blue),
                  onPressed: event.routeData.isEmpty
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullScreenMap(
                                routePoints: event.routePoints,
                              ),
                            ),
                          );
                        },
                ),
              ],
            ),
            SizedBox(height: 8),
            if (event.description != null && event.description!.isNotEmpty)
              Text(
                event.description!,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.directions_run, size: 18, color: Colors.grey[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Тип: ${EventTranslations.getEventTypeDisplayName(event.eventType)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.terrain, size: 18, color: Colors.grey[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Сложность: ${EventTranslations.getDifficultyDisplayName(event.difficulty)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Начало: ${_formatDateTime(event.startTime)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_available, size: 18, color: Colors.grey[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Окончание: ${_formatDateTime(event.endTime)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people, size: 18, color: Colors.grey[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Свободные места: ${event.availableSeats}/${event.maxParticipants}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            _buildMap(event, index),
            SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: event.availableSeats > 0
                    ? () => _participateEvent(event.id)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: Text(
                  event.availableSeats > 0
                      ? 'Записаться на мероприятие'
                      : 'Мест нет',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(Event event, int index) {
    if (event.routeData.isEmpty) {
      return Text(
        'Маршрут не указан',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[700],
        ),
      );
    }

    final routePoints = event.routePoints;

    return VisibilityDetector(
      key: Key('map_${event.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _zoomToRoute(routePoints, _mapControllers[index]);
          });
        }
      },
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: FlutterMap(
            mapController: _mapControllers[index],
            options: MapOptions(
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.none,
              ),
              initialCenter: routePoints.isNotEmpty
                  ? routePoints.first
                  : LatLng(55.7558, 37.6176),
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    color: Colors.blue,
                    strokeWidth: 4.0,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: routePoints.first,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_run,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  if (routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: routePoints.last,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _participateEvent(int eventId) async {
    try {
      await _eventService.participateEvent(eventId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Вы успешно записаны на мероприятие!')),
      );
    } catch (e) {
      String errorMessage = 'Ошибка записи';
      if (e.toString().contains("Организатор не может")) {
        errorMessage = "Организатор не может записаться на свое мероприятие";
      } else if (e.toString().contains("Нет свободных мест")) {
        errorMessage = "Все места заняты";
      } else if (e.toString().contains("уже является участником")) {
        errorMessage = "Вы уже записаны на это мероприятие";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }
}

class FullScreenMap extends StatefulWidget {
  final List<LatLng> routePoints;

  const FullScreenMap({Key? key, required this.routePoints}) : super(key: key);

  @override
  _FullScreenMapState createState() => _FullScreenMapState();
}

class _FullScreenMapState extends State<FullScreenMap> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomToRoute(List<LatLng> routePoints) {
    final bounds = LatLngBounds.fromPoints(routePoints);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Карта маршрута'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.routePoints.isNotEmpty
                  ? widget.routePoints.first
                  : LatLng(55.7558, 37.6176),
              initialZoom: 13.0,
              onMapReady: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Future.delayed(Duration(milliseconds: 500), () {
                    _zoomToRoute(widget.routePoints);
                  });
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routePoints,
                    color: Colors.blue,
                    strokeWidth: 4.0,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (widget.routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: widget.routePoints.first,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.directions_run,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  if (widget.routePoints.isNotEmpty)
                    Marker(
                      width: 30.0,
                      height: 30.0,
                      point: widget.routePoints.last,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_in_${widget.hashCode}',
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    );
                  },
                  child: Icon(Icons.add),
                ),
                SizedBox(height: 10),
                FloatingActionButton(
                  mini: true,
                  heroTag: 'zoom_out_${widget.hashCode}',
                  onPressed: () {
                    _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    );
                  },
                  child: Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
