import 'package:flutter/material.dart';
import '../../models/RunningRoute.dart';

class RouteStats extends StatelessWidget {
  final RunningRoute route;

  const RouteStats({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(
              context,
              Icons.calendar_today_rounded,
              'Дата',
              route.formattedDate,
            ),
            _buildDivider(),
            _buildStatItem(
              context,
              Icons.timer_rounded,
              'Время',
              route.formattedDuration,
            ),
            _buildDivider(),
            _buildStatItem(
              context,
              Icons.straighten_rounded,
              'Расстояние',
              '${route.distance.toStringAsFixed(2)} км',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: Color(0xFF00B871),
          size: 24,
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Color(0xFF3A3A3A),
    );
  }
}
