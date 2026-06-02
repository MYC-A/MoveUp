Нажмите Ctrl + Shift + P, введите Flutter: Launch Emulator, выберите эмулятор и дождитесь полной загрузки.

Запуск для Android-эмулятора:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000 \
  --dart-define=MEDIA_BASE_URL=http://10.0.2.2:9000 \
  --dart-define=OPEN_ROUTE_API_KEY=your-openroute-key
```
