# Статус проверок

Дата последних проверок: 2026-06-01.

## Green checks

Flutter:

```text
flutter analyze
No issues found! (ran in 5.9s)

flutter test
Login screen smoke test
All tests passed!
```

Backend:

```text
python -m compileall app
OK

python -m pytest
27 passed, 5 warnings in 2.50s
```

Backend test files:

- `tests/test_auth_schema.py`.
- `tests/test_event_schema.py`.
- `tests/test_security.py`.
- `tests/test_uploads.py`.

CI:

- `.github/workflows/ci.yml` запускает backend compile/tests и Flutter analyze/tests.
- Backend CI на Python 3.11.
- Flutter CI на Flutter 3.27.1 stable.

## Warnings

Pytest предупреждения не ломают сборку, но их стоит помнить:

- Pydantic V2 deprecation: class-based `config` где-то еще используется.
- `passlib` использует deprecated `crypt`, который будет удален в Python 3.13.
- `python-jose` предупреждает про `datetime.utcnow()`.

## Важное изменение относительно старого состояния

Раньше общий `flutter analyze` падал на `flutter_project/lib/test/feed_screen1.dart`. В текущем состоянии анализ зеленый: legacy/test-проблемы либо исправлены, либо убраны из анализируемого пути.
