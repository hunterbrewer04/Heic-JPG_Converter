from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, as_completed
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


def convert_one(
    image_file: Path,
    output_dir: Path | None,
    quality: int,
    archive: bool,
    force: bool,
) -> tuple[Status, str]:
    target_dir = output_dir or image_file.parent
    new_name = target_dir / image_file.with_suffix(".jpg").name

    if new_name.exists() and not force:
        return Status.SKIPPED, f"{new_name.name} already exists"

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        with Image.open(image_file) as image:
            save_kwargs = {"quality": quality, "subsampling": 0}
            if exif := image.info.get("exif"):
                save_kwargs["exif"] = exif
            if icc := image.info.get("icc_profile"):
                save_kwargs["icc_profile"] = icc
            image.convert("RGB").save(new_name, **save_kwargs)
    except Exception as e:
        return Status.ERROR, f"{image_file.name}: {e}"

    if archive:
        try:
            archive_dir = image_file.parent / "heic_originals"
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
            if p.suffix.lower() == ".heic":
                files.append(p)
            else:
                print(f"Warning: {p} is not a HEIC file, skipping")
        elif p.is_dir():
            files.extend(p.rglob("*.[hH][eE][iI][Cc]"))
        else:
            print(f"Warning: {p} is not a file or folder, skipping")
    return files


def warn_output_collisions(files: list[Path], output_dir: Path) -> None:
    seen: dict[Path, Path] = {}
    for f in files:
        target = output_dir / f.with_suffix(".jpg").name
        if target in seen:
            print(
                f"Warning: {f} and {seen[target]} both target {target.name}; "
                "only one will be kept"
            )
        else:
            seen[target] = f


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
    parser = argparse.ArgumentParser(description="Convert HEIC images to JPG.")
    parser.add_argument(
        "paths", nargs="+", type=Path,
        help="HEIC file(s) or folder(s) to convert",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="Output folder (default: alongside source)",
    )
    parser.add_argument(
        "-q", "--quality", type=quality_arg, default=95,
        help="JPG quality 1-100 (default: 95)",
    )
    parser.add_argument(
        "--archive", action="store_true",
        help="Move originals to heic_originals/ next to the source after success",
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite existing .jpg files",
    )
    parser.add_argument(
        "-j", "--jobs", type=jobs_arg, default=os.cpu_count() or 1,
        help="Parallel workers (default: all cores)",
    )
    args = parser.parse_args()

    files = collect_files(args.paths)
    if not files:
        print("No HEIC files found.")
        notify("HEIC Converter", "No HEIC files found.")
        return

    if args.output is not None:
        warn_output_collisions(files, args.output)

    counts: Counter[Status] = Counter()
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        futures = [
            pool.submit(
                convert_one, f, args.output,
                args.quality, args.archive, args.force,
            )
            for f in files
        ]
        for fut in tqdm(as_completed(futures), total=len(futures), desc="Converting"):
            try:
                status, message = fut.result()
            except Exception as e:
                status, message = Status.ERROR, f"worker crashed: {e}"
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
