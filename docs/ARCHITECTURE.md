# Архитектура 0.9.0

- `AppController` — каталог, выбор профиля, URL Test, обновление, карантин.
- `AndroidVpnCore` — sing-box для обычных протоколов и AmneziaWG bridge для WARP.
- `LatencyService` — контроль базового интернета и вызов URL Test без VPN.
- `CatalogService` — встроенный/удалённый каталог и подписки.
- `WarpGenBridge` — импорт одного WARP-конфига через разрешённый WebView.
- `WarpProvisioningService` — локальная ключевая пара, регистрация Cloudflare и пул WARP endpoint-ов.
- `prepare_android.py` — патч Android host-проекта после `flutter create`.

URL Test и системное подключение являются отдельными путями выполнения.
