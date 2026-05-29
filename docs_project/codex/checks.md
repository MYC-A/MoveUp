# Статус проверок

Дата последних проверок: 2026-05-29.

## Что проходит

- `flutter test` проходит. Сейчас в проекте фактически есть smoke test логина.
- `dart analyze lib/screens_api/feed_screen.dart` проходит без ошибок после оптимизации карты в ленте.
- `python -m compileall app` для backend проходит.
- Ручная проверка `EventCreate` подтверждала: короткий маршрут принимается, маршрут больше 200 км отклоняется.

## Что пока не проходит

`flutter analyze` по всему проекту пока падает на старых файлах внутри `flutter_project/lib/test/`.

Главный блокер:

- `flutter_project/lib/test/feed_screen1.dart:412` - `PhotoViewer` не определен для `_PostItemState`.

Еще есть предупреждения:

- duplicate/unused imports в `lib/test/feed_screen1.dart` и `lib/test/feed_screen.dart`.
- unused/dead code в `GpsFilter.dart`, `FullScreenMap.dart`, `SelectParticipantsModal.dart`, `event_screen.dart`.
- deprecated `withOpacity` в нескольких UI-файлах.

Важно: папка `lib/test/` находится внутри `lib`, поэтому Flutter анализирует ее как часть приложения. Либо эти файлы надо чинить, либо выносить из `lib`.

## Текущий git status после последних правок

На момент создания этих заметок изменен:

- `flutter_project/lib/screens_api/feed_screen.dart` - оптимизация карты маршрута в ленте.

Также в рабочем дереве была untracked папка:

- `.devcontainer/`.
