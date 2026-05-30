/// Оценка сожжённых калорий по дистанции и массе тела.
///
/// Упрощённая формула для бега/ходьбы: ~1.036 ккал на кг массы на километр.
/// Если вес не задан — берём средний 70 кг.
int estimateCalories(double distanceMeters, {double? weightKg}) {
  if (distanceMeters <= 0) return 0;
  final km = distanceMeters / 1000.0;
  final weight = (weightKg != null && weightKg > 0) ? weightKg : 70.0;
  return (weight * km * 1.036).round();
}
