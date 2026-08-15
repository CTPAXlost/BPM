#!/usr/bin/env python3
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def png_to_ico(source: Path, destination: Path) -> None:
    png = source.read_bytes()
    if png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
        raise SystemExit(f"Not a PNG file: {source}")
    width, height = struct.unpack(">II", png[16:24])
    if width > 256 or height > 256:
        raise SystemExit("Windows icon source must be at most 256x256")
    icon_dir = struct.pack("<HHH", 0, 1, 1)
    icon_entry = struct.pack(
        "<BBBBHHII",
        0 if width == 256 else width,
        0 if height == 256 else height,
        0,
        0,
        1,
        32,
        len(png),
        6 + 16,
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(icon_dir + icon_entry + png)


def main() -> None:
    png_to_ico(
        ROOT / "assets/images/launcher_256.png",
        ROOT / "windows/runner/resources/app_icon.ico",
    )
    main_cpp = ROOT / "windows/runner/main.cpp"
    text = main_cpp.read_text(encoding="utf-8-sig")
    old = 'L"pokolenie_vpn"'
    if old not in text:
        raise SystemExit("Generated Windows window title was not found")
    main_cpp.write_text(text.replace(old, 'L"Pokolenie WARP"'), encoding="utf-8")
    print("Prepared Pokolenie WARP Windows host")


if __name__ == "__main__":
    main()
