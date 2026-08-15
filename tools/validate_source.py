#!/usr/bin/env python3
from __future__ import annotations
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8-sig')

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--allow-generated', action='store_true')
    args = parser.parse_args()
    errors: list[str] = []
    required = (
        'pubspec.yaml', 'lib/main.dart', 'lib/core/android_vpn_core.dart',
        'lib/core/windows_vpn_core.dart',
        'lib/core/amneziawg_bridge.dart', 'lib/services/app_controller.dart',
        'lib/services/warp_generator_service.dart', 'lib/screens/home_screen.dart',
        'lib/screens/warp_screen.dart', 'lib/screens/settings_screen.dart',
        'assets/audio/toasty.mp3', 'assets/images/toasty_face_cutout.png',
        'assets/warp/WARP_STR5118.conf', 'assets/warp/WARP_STR8605.conf',
        'assets/warp/WARP_STR4470.conf',
        'assets/images/theme_nightmare.webp', 'assets/images/theme_symbiosis.webp',
        'tools/prepare_android.py', '.github/workflows/build.yml',
    )
    for item in required:
        if not (ROOT / item).is_file(): errors.append(f'Missing: {item}')
    forbidden_paths = (
        'catalog', 'lib/services/catalog_service.dart', 'lib/services/latency_service.dart',
        'lib/models/source_definition.dart', 'lib/screens/servers_screen.dart',
        'lib/screens/sources_screen.dart', 'tools/catalog_builder.py',
        '.github/workflows/refresh-catalog.yml',
    )
    for item in forbidden_paths:
        if (ROOT / item).exists(): errors.append(f'Obsolete path remains: {item}')
    pubspec = read('pubspec.yaml')
    if 'version: 1.1.1+111' not in pubspec: errors.append('Wrong version')
    for token in ('singbox_mm', 'uuid:'):
        if token in pubspec: errors.append(f'Obsolete dependency: {token}')
    joined = '\n'.join(path.read_text(encoding='utf-8-sig') for path in (ROOT / 'lib').rglob('*.dart'))
    for token in ('vless://', 'vmess://', 'singbox_mm', 'SourceDefinition', 'CatalogService'):
        if token.lower() in joined.lower(): errors.append(f'Obsolete protocol code remains: {token}')
    controller = read('lib/services/app_controller.dart')
    core = read('lib/core/android_vpn_core.dart')
    for token in ('generateOneWarp', "AssetSource('audio/toasty.mp3')", 'testAllWarpNodes'):
        if token not in controller: errors.append(f'Missing controller feature: {token}')
    for token in ('IncludedApplications', 'ExcludedApplications', 'probeVpnNetwork'):
        if token not in core: errors.append(f'Missing native feature: {token}')
    windows_core = read('lib/core/windows_vpn_core.dart')
    for token in ('/installtunnelservice', '/uninstalltunnelservice', 'AmneziaWGTunnel', 'validateConnected'):
        if token not in windows_core: errors.append(f'Missing Windows feature: {token}')
    if "r'; exit $p.ExitCode'" not in windows_core:
        errors.append('PowerShell process variable is not protected from Dart interpolation')
    expression = re.compile(r"\b(?:import|export|part)\s+['\"]([^'\"]+)['\"]")
    for base in (ROOT / 'lib', ROOT / 'test'):
        if not base.exists(): continue
        for path in base.rglob('*.dart'):
            for target in expression.findall(path.read_text(encoding='utf-8')):
                if not target.startswith(('dart:', 'package:')) and not (path.parent / target).resolve().exists():
                    errors.append(f'{path.relative_to(ROOT)} imports missing {target}')
    if not args.allow_generated:
        for name in ('.dart_tool', '.gradle', 'build', 'dist', '__pycache__'):
            if (ROOT / name).exists(): errors.append(f'Generated directory remains: {name}')
    if errors:
        print('\n'.join(f'ERROR: {e}' for e in errors))
        raise SystemExit(1)
    print('Pokolenie WARP 1.1.1 source validation: OK')

if __name__ == '__main__': main()
