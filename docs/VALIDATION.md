# Проверка проекта

Локально без Flutter SDK:

```bash
python tools/validate_source.py
python -m compileall -q tools tests
python -m unittest discover -s tests -v
```

В GitHub Actions дополнительно выполняются строгий Flutter Analyzer, Flutter-тесты, генерация Android-проекта, повторный preflight и сборка arm64 APK.
