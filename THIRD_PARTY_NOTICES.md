# Third-party notices

## Flutter packages

The project uses Flutter packages declared in `pubspec.yaml`. Their licenses remain governed by their respective upstream projects.

## singbox_mm

Regular VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and TUIC profiles use the `singbox_mm` Flutter plugin and its Android libbox integration. Retain the package license and its bundled third-party notices when distributing the APK.

## AmneziaWG Android

WARP/WireGuard/AmneziaWG profiles use the official `amnezia-vpn/amneziawg-android` tunnel module fetched by GitHub Actions from the pinned release tag. Its license and corresponding-source obligations must be retained when distributing builds.

## External WARP generators

Single-profile generation uses HTTPS mirrors of the open-source `nellimonix/warp-config-generator-vercel` project after an explicit user action. The generator is MIT licensed and is not operated by Pokolenie VPN. Source: https://github.com/nellimonix/warp-config-generator-vercel
