# Архитектура 0.9.4

- `AppController` — каталог, выбор профиля, URL Test, обновление, карантин.
- `AndroidVpnCore` — sing-box для обычных протоколов и AmneziaWG bridge для WARP.
- `LatencyService` — контроль базового интернета и вызов URL Test без VPN.
- `CatalogService` — встроенный/удалённый каталог и подписки.
- `WarpGeneratorService` — создание одного AWG 1.5 конфига через резервируемые HTTPS-зеркала и проверка формата ответа.
- `prepare_android.py` — патч Android host-проекта после `flutter create`.

URL Test и системное подключение являются отдельными путями выполнения.
