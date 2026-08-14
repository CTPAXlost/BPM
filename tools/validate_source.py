#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "0.9.5"
EXPECTED_BUILD = "95"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def check(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def validate_required(errors: list[str]) -> None:
    required = (
        "pubspec.yaml",
        "lib/main.dart",
        "lib/core/android_vpn_core.dart",
        "lib/core/amneziawg_bridge.dart",
        "lib/core/vpn_core.dart",
        "lib/services/app_controller.dart",
        "lib/services/catalog_service.dart",
        "lib/services/latency_service.dart",
        "lib/services/storage_service.dart",
        "lib/services/warp_generator_service.dart",
        "lib/screens/home_screen.dart",
        "lib/screens/servers_screen.dart",
        "lib/screens/warp_screen.dart",
        "lib/screens/sources_screen.dart",
        "lib/screens/settings_screen.dart",
        "tools/prepare_android.py",
        "tools/catalog_builder.py",
        ".github/workflows/build.yml",
        "catalog/sources.json",
        "catalog/public_catalog.json",
        "assets/warp/WARP_STR8605.conf",
        "assets/warp/WARP_STR4470.conf",
        "assets/images/theme_nightmare.webp",
        "assets/images/theme_symbiosis.webp",
    )
    for relative in required:
        check((ROOT / relative).is_file(), f"Missing required file: {relative}", errors)

    forbidden = (
        "windows",
        "lib/core/windows_vpn_core.dart",
        "tools/prepare_platforms.py",
        "tools/installer.iss",
        "assets/core/windows",
        "assets/images/app_icon.ico",
        "lib/screens/game_mode_screen.dart",
        "lib/screens/split_tunnel_screen.dart",
        "lib/services/game_mode_service.dart",
        "lib/services/app_selection_service.dart",
        "lib/core/singbox_config_builder.dart",
    )
    for relative in forbidden:
        check(not (ROOT / relative).exists(), f"Obsolete file remains: {relative}", errors)


def validate_version(errors: list[str]) -> None:
    pubspec = read("pubspec.yaml")
    check(
        f"version: {EXPECTED_VERSION}+{EXPECTED_BUILD}" in pubspec,
        "pubspec version is not 0.9.5+95",
        errors,
    )
    check("window_manager" not in pubspec, "Desktop dependency remains", errors)
    check("path_provider" not in pubspec, "Unused desktop dependency remains", errors)
    check("cupertino_icons" not in pubspec, "Unused Cupertino dependency remains", errors)
    check("flutter_lints" not in pubspec, "Unused Flutter lint preset dependency remains", errors)
    analysis = read("analysis_options.yaml")
    check("package:flutter_lints" not in analysis, "Broad lint preset remains enabled", errors)
    check("unused_import: error" in analysis, "Unused imports are not fatal", errors)


def validate_architecture(errors: list[str]) -> None:
    controller = read("lib/services/app_controller.dart")
    core = read("lib/core/android_vpn_core.dart")
    latency = read("lib/services/latency_service.dart")
    shell = read("lib/screens/app_shell.dart")
    workflow = read(".github/workflows/build.yml")

    check("Future<ProbeResult> test(" in core, "Android URL Test is missing", errors)
    check("Future<ProbeResult> quickTest(" in core, "Fast list probe is missing", errors)
    check("pingProfile(profile: parsed.profile)" in core, "Native profile ping is missing", errors)
    test_block = core.split("Future<ProbeResult> test(", 1)[1].split("Future<ProbeResult> validateConnected", 1)[0]
    check("await connect(node, settings)" in test_block, "Full tunnel probe is missing", errors)
    check("await validateConnected(remaining)" in test_block, "VPN-bound HTTPS validation is missing", errors)
    check("await disconnect()" in test_block, "Temporary tunnel cleanup is missing", errors)
    check("HTTPS через VPN прошёл" in controller, "User-facing tunnel validation message is missing", errors)
    check("url_test_failures" in controller, "Repeated failure tracking is missing", errors)
    check("final remove = settings.autoRemoveUnavailable" in controller, "Manual failure removal is missing", errors)
    check("hasBaseInternet" in controller, "Base internet guard is missing", errors)
    check("probeInProgress" in controller, "Controller probe mutex is missing", errors)
    check("_probeInProgress" in core, "Core probe mutex is missing", errors)
    check("_startAwgStatistics" in core, "Native WARP traffic polling is missing", errors)
    check("generateOneWarp" in controller, "Single WARP generation is missing", errors)
    check("warpGenerationCooldown" in controller, "WARP generation cooldown is missing", errors)
    check("core.test(node, timeout" in latency, "Latency service does not delegate real probes", errors)
    check("core.quickTest(node, timeout)" in latency, "Latency service does not delegate quick probes", errors)
    check("? 4" in controller and ": 1" in controller, "Regular probe pool / sequential WARP split is missing", errors)
    check("generateWarpPool" not in controller, "Retired WARP generator remains", errors)
    check("importWarpFromWebsite" not in controller, "Retired WARP website import remains", errors)
    check("final file = await openFile();" in controller, "Unrestricted Android config picker is missing", errors)
    check("Windows" not in workflow and "windows:" not in workflow, "Windows CI job remains", errors)
    check("prepare_android.py" in workflow, "Android patcher is not used", errors)
    check("flutter build apk" in workflow, "Android APK build is missing", errors)
    check("ServersScreen" in shell and "WarpScreen" in shell, "New mobile navigation is incomplete", errors)
    patcher = read("tools/prepare_android.py")
    check("usesCleartextTraffic=\"true\"" not in patcher, "Android cleartext traffic is enabled", errors)
    check("QUERY_ALL_PACKAGES" not in patcher, "Broad package visibility permission remains", errors)
    check("WarpGenActivity" not in patcher, "Retired WarpGen Android activity remains", errors)


def validate_catalog(errors: list[str]) -> None:
    try:
        data = json.loads(read("catalog/public_catalog.json"))
    except Exception as exc:
        errors.append(f"public_catalog.json is invalid: {exc}")
        return
    check(isinstance(data.get("nodes"), list), "Catalog nodes are missing", errors)
    check(bool(data.get("nodes")), "Catalog is empty", errors)


def validate_local_imports(errors: list[str]) -> None:
    expression = re.compile(r"\b(?:import|export|part)\s+['\"]([^'\"]+)['\"]")
    for base in (ROOT / "lib", ROOT / "test"):
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.dart")):
            for target in expression.findall(path.read_text(encoding="utf-8")):
                if target.startswith(("dart:", "package:")):
                    continue
                resolved = (path.parent / target).resolve()
                if not resolved.exists():
                    errors.append(
                        f"{path.relative_to(ROOT)} imports missing file: {target}"
                    )



def _dart_delimiter_error(text: str) -> str | None:
    opening = {'(': ')', '[': ']', '{': '}'}
    closing = {')', ']', '}'}
    stack: list[tuple[str, int]] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        nxt = text[index + 1] if index + 1 < length else ''
        if char == '/' and nxt == '/':
            newline = text.find('\n', index + 2)
            index = length if newline < 0 else newline + 1
            continue
        if char == '/' and nxt == '*':
            end = text.find('*/', index + 2)
            if end < 0:
                return f'unclosed block comment at offset {index}'
            index = end + 2
            continue
        raw = char in {'r', 'R'} and nxt in {"'", '"'}
        if raw:
            index += 1
            char = text[index]
        if char in {"'", '"'}:
            quote = char
            triple = text[index:index + 3] == quote * 3
            index += 3 if triple else 1
            while index < length:
                if triple and text[index:index + 3] == quote * 3:
                    index += 3
                    break
                if not triple and text[index] == quote:
                    index += 1
                    break
                if not raw and text[index] == '\\':
                    index += 2
                else:
                    index += 1
            else:
                return f'unclosed string at offset {index}'
            continue
        if char in opening:
            stack.append((char, index))
        elif char in closing:
            if not stack:
                return f'unexpected {char} at offset {index}'
            opener, opener_index = stack.pop()
            if opening[opener] != char:
                return (
                    f'mismatched {opener} at offset {opener_index} '
                    f'and {char} at offset {index}'
                )
        index += 1
    if stack:
        opener, opener_index = stack[-1]
        return f'unclosed {opener} at offset {opener_index}'
    return None


def validate_dart_structure(errors: list[str]) -> None:
    for base in (ROOT / 'lib', ROOT / 'test'):
        if not base.exists():
            continue
        for path in sorted(base.rglob('*.dart')):
            error = _dart_delimiter_error(path.read_text(encoding='utf-8'))
            if error:
                errors.append(f'{path.relative_to(ROOT)}: {error}')

def validate_no_build_garbage(
    errors: list[str], *, allow_generated: bool = False
) -> None:
    if allow_generated:
        return
    forbidden_parts = {".dart_tool", "build", ".gradle", "__pycache__", "dist"}
    for path in ROOT.rglob("*"):
        if any(part in forbidden_parts for part in path.relative_to(ROOT).parts):
            errors.append(f"Generated file or directory is included: {path.relative_to(ROOT)}")
            break


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Pokolenie VPN source and generated Android project."
    )
    parser.add_argument(
        "--allow-generated",
        action="store_true",
        help=(
            "Allow Flutter/Gradle working directories created during the Android "
            "build. Clean source validation remains strict by default."
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    errors: list[str] = []
    validate_required(errors)
    if not errors:
        validate_version(errors)
        validate_architecture(errors)
        validate_catalog(errors)
        validate_local_imports(errors)
        validate_dart_structure(errors)
        validate_no_build_garbage(errors, allow_generated=args.allow_generated)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        raise SystemExit(1)
    print("Pokolenie VPN 0.9.5 Android source validation: OK")


if __name__ == "__main__":
    main()
