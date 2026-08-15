from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parents[1] / "outputs" / "Pokolenie-WARP-v1.2.1-source.zip"
SKIP_PARTS = {
    ".dart_tool",
    ".gradle",
    "__pycache__",
    "android",
    "build",
    "dist",
    "third_party",
}

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUTPUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if not path.is_file() or any(part in SKIP_PARTS for part in relative.parts):
            continue
        archive.write(path, relative.as_posix())

print(OUTPUT)
