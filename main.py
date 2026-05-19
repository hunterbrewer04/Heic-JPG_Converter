from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from PIL import Image
from pillow_heif import register_heif_opener
from tqdm import tqdm

register_heif_opener()


class Status(str, Enum):
    CONVERTED = "converted"
    SKIPPED = "skipped"
    ERROR = "error"


@dataclass(frozen=True)
class FormatSpec:
    extension: str          # output suffix (no leading dot)
    pillow_format: str      # value for Image.save(format=...)
    supports_quality: bool  # JPEG only
    needs_rgb: bool         # JPEG and GIF lose / quantize alpha


FORMATS: dict[str, FormatSpec] = {
    "jpg": FormatSpec("jpg", "JPEG", supports_quality=True,  needs_rgb=True),
    "png": FormatSpec("png", "PNG",  supports_quality=False, needs_rgb=False),
    "gif": FormatSpec("gif", "GIF",  supports_quality=False, needs_rgb=True),
}

INPUT_EXTENSIONS: frozenset[str] = frozenset({
    ".heic", ".heif", ".jpg", ".jpeg", ".png", ".gif",
    ".tif", ".tiff", ".bmp", ".webp",
})

# Aliases used for the same-format skip check (".jpeg" inputs map to "jpg" output).
_EXTENSION_ALIASES: dict[str, str] = {"jpeg": "jpg", "tiff": "tif"}


def _normalized_ext(path: Path) -> str:
    raw = path.suffix.lower().lstrip(".")
    return _EXTENSION_ALIASES.get(raw, raw)


def convert_one(
    image_file: Path,
    output_dir: Path | None,
    quality: int,
    archive: bool,
    force: bool,
    format_key: str,
) -> tuple[Status, str]:
    spec = FORMATS[format_key]
    target_dir = output_dir or image_file.parent
    new_name = target_dir / (image_file.stem + "." + spec.extension)

    if not force and _normalized_ext(image_file) == spec.extension:
        return Status.SKIPPED, f"{image_file.name} is already {spec.extension}"

    if new_name.exists() and not force:
        return Status.SKIPPED, f"{new_name.name} already exists"

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        with Image.open(image_file) as image:
            save_kwargs: dict = {}
            if spec.supports_quality:
                save_kwargs["quality"] = quality
                save_kwargs["subsampling"] = 0
            if spec.pillow_format in ("JPEG", "PNG"):
                if exif := image.info.get("exif"):
                    save_kwargs["exif"] = exif
                if icc := image.info.get("icc_profile"):
                    save_kwargs["icc_profile"] = icc
            img = image.convert("RGB") if spec.needs_rgb else image
            img.save(new_name, format=spec.pillow_format, **save_kwargs)
    except Exception as e:
        return Status.ERROR, f"{image_file.name}: {e}"

    if archive:
        try:
            archive_dir = image_file.parent / "image_originals"
            archive_dir.mkdir(exist_ok=True)
            shutil.move(image_file, archive_dir / image_file.name)
        except Exception as e:
            return Status.ERROR, f"{new_name.name} saved but archive failed: {e}"

    return Status.CONVERTED, new_name.name


def notify(title: str, message: str) -> None:
    if sys.platform != "darwin":
        return
    script = (
        f"display notification {json.dumps(message)} "
        f"with title {json.dumps(title)} sound name \"Glass\""
    )
    subprocess.run(["osascript", "-e", script], check=False)


def collect_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for p in paths:
        if p.is_file():
            if p.suffix.lower() in INPUT_EXTENSIONS:
                files.append(p)
            else:
                print(f"Warning: {p} is not a supported image, skipping")
        elif p.is_dir():
            for child in p.rglob("*"):
                if child.is_file() and child.suffix.lower() in INPUT_EXTENSIONS:
                    files.append(child)
        else:
            print(f"Warning: {p} is not a file or folder, skipping")
    return files


def dedupe_by_output(files: list[Path], output_dir: Path, extension: str) -> list[Path]:
    seen: dict[Path, Path] = {}
    deduped: list[Path] = []
    for f in files:
        target = output_dir / (f.stem + "." + extension)
        if target in seen:
            print(
                f"Warning: {f} collides with {seen[target]} at {target.name}; "
                "skipping the later one to avoid concurrent writes"
            )
            continue
        seen[target] = f
        deduped.append(f)
    return deduped


def quality_arg(value: str) -> int:
    iv = int(value)
    if not 1 <= iv <= 100:
        raise argparse.ArgumentTypeError("quality must be between 1 and 100")
    return iv


def jobs_arg(value: str) -> int:
    iv = int(value)
    if iv < 1:
        raise argparse.ArgumentTypeError("jobs must be >= 1")
    return iv


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert images between HEIC, JPG, PNG, and GIF.")
    parser.add_argument(
        "paths", nargs="+", type=Path,
        help="Image file(s) or folder(s) to convert",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="Output folder (default: alongside source)",
    )
    parser.add_argument(
        "-f", "--output-format", choices=list(FORMATS.keys()), default="jpg",
        help="Output format: jpg, png, or gif (default: jpg)",
    )
    parser.add_argument(
        "-q", "--quality", type=quality_arg, default=95,
        help="Output quality 1-100 (used only for JPG; default: 95)",
    )
    parser.add_argument(
        "--archive", action="store_true",
        help="Move originals to image_originals/ next to the source after success",
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite existing output files (and re-encode same-format inputs)",
    )
    parser.add_argument(
        "-j", "--jobs", type=jobs_arg, default=os.cpu_count() or 1,
        help="Parallel workers (default: all cores)",
    )
    args = parser.parse_args()

    files = collect_files(args.paths)
    if not files:
        print("No supported images found.")
        notify("HEIC Converter", "No supported images found.")
        return

    if args.output is not None:
        files = dedupe_by_output(files, args.output, args.output_format)

    counts: Counter[Status] = Counter()
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        future_to_path = {
            pool.submit(
                convert_one, f, args.output,
                args.quality, args.archive, args.force, args.output_format,
            ): f
            for f in files
        }
        for fut in tqdm(as_completed(future_to_path), total=len(future_to_path), desc="Converting"):
            try:
                status, message = fut.result()
            except Exception as e:
                status, message = Status.ERROR, f"worker crashed on {future_to_path[fut].name}: {e}"
            counts[status] += 1
            tqdm.write(f"{status.value}: {message}")

    notify(
        "HEIC Converter",
        f"Converted {counts[Status.CONVERTED]}, "
        f"skipped {counts[Status.SKIPPED]}, "
        f"errored {counts[Status.ERROR]}",
    )


if __name__ == "__main__":
    main()
