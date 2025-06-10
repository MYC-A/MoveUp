class EventTranslations {
  static const Map<String, String> eventTypeTranslations = {
    'RUNNING': 'Бег',
    'CYCLING': 'Велоспорт',
    'HIKING': 'Пеший туризм',
    'TRAINING': 'Тренировка',
  };

  static const Map<String, String> difficultyTranslations = {
    'новичок': 'Новичок',
    'любитель': 'Любитель',
    'профессионал': 'Профессионал',
  };

  static const Map<String, String> statusTranslations = {
    'AWAITS': 'Ожидает',
    'APPROVED': 'Одобрено',
    'DENIED': 'Отклонено',
  };

  // Функция для получения перевода статуса заявки
  static String getStatusDisplayName(String status) {
    return statusTranslations[status] ?? status;
  }

  // Функция для получения перевода типа мероприятия
  static String getEventTypeDisplayName(String eventType) {
    return eventTypeTranslations[eventType] ?? eventType;
  }

  // Функция для получения перевода сложности
  static String getDifficultyDisplayName(String difficulty) {
    return difficultyTranslations[difficulty] ?? difficulty;
  }

  // Обратное преобразование для отправки на сервер (если нужно)
  static String getEventTypeValue(String displayName) {
    return eventTypeTranslations.entries
        .firstWhere((entry) => entry.value == displayName,
            orElse: () => MapEntry(displayName, displayName))
        .key;
  }

  static String getDifficultyValue(String displayName) {
    return difficultyTranslations.entries
        .firstWhere((entry) => entry.value == displayName,
            orElse: () => MapEntry(displayName, displayName))
        .key;
  }

  static String getStatusValue(String displayName) {
    return statusTranslations.entries
        .firstWhere((entry) => entry.value == displayName,
            orElse: () => MapEntry(displayName, displayName))
        .key;
  }
}
