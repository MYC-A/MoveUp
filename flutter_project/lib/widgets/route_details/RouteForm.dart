import 'package:flutter/material.dart';

class RouteForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController descriptionController;

  const RouteForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.descriptionController,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Информация о маршруте',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: TextFormField(
              controller: nameController,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                labelText: 'Название маршрута',
                labelStyle: TextStyle(
                  color: Color(0xFF00B871),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.route_rounded, color: Color(0xFF00B871)),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите название маршрута';
                }
                return null;
              },
            ),
          ),
          SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: TextFormField(
              controller: descriptionController,
              maxLines: null,
              minLines: 3,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                labelText: 'Описание',
                labelStyle: TextStyle(
                  color: Color(0xFF00B871),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                prefixIcon: Icon(
                  Icons.description_rounded,
                  color: Color(0xFF00B871),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
