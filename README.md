# Image Converter (HEIC / JPG / PNG / GIF)

A Python tool to convert between common image formats using the Pillow library and `pillow-heif` plugin. Point it at any file or folder from the CLI; metadata, quality, and parallelism are handled for you. Includes an optional macOS Finder Quick Action recipe so you can right-click photos and convert without opening a terminal.

**Looking for a menu bar app instead of a CLI?** A native SwiftUI rewrite lives in [`app/`](app/) — no Python runtime needed, uses macOS's built-in Image I/O. See [`app/README.md`](app/README.md) for build and install instructions.

---

## Features

- **Input**: HEIC, HEIF, JPG, JPEG, PNG, GIF, TIFF, BMP, WEBP — single files, multiple files, or whole folders (recursively).
- **Output**: JPG (default), PNG, or GIF — pick with `-f/--output-format`.
- **Preserves EXIF + ICC profile** for JPEG/PNG outputs (date taken, GPS, orientation, camera info).
- **Parallel conversion** using all CPU cores by default.
- **Progress bar** for batch jobs.
- Skips files that already have an output sibling (override with `--force`).
- Same-format inputs (e.g. dropping a `.png` while converting to PNG) are skipped unless `--force` is set.
- Optional `--archive` flag tucks originals into an `image_originals/` subfolder.
- **macOS desktop notification** when the batch finishes — useful when running from Finder.

---

## Requirements

- Python 3.9+
- Pillow
- pillow-heif
- tqdm

---

## Installation

```bash
git clone git@github.com:hunterbrewer04/Heic-JPG_Converter.git
cd Heic-JPG_Converter
pip install -r requirements.txt
```

---

## Usage

```bash
python main.py PATH [PATH ...] [options]
```

### Examples

Convert a single photo to JPG (the default):
```bash
python main.py ~/Downloads/IMG_1234.HEIC
```

Convert every supported image in a folder (recursive) to PNG:
```bash
python main.py ~/Pictures/iphone_dump -f png
```

Convert a mix of files and folders to GIF, into a separate folder:
```bash
python main.py ~/Desktop/photo1.HEIC ~/Pictures/trip -f gif -o ~/Pictures/converted
```

Move originals into an `image_originals/` subfolder after successful conversion:
```bash
python main.py ~/Pictures/iphone_dump --archive
```

### Options

| Flag | Description |
| --- | --- |
| `-o, --output DIR` | Write output files into `DIR` instead of alongside the source files. |
| `-f, --output-format` | Output format: `jpg` (default), `png`, or `gif`. |
| `-q, --quality N` | Output quality 1-100 (used only for JPG; default: 95). |
| `--archive` | After converting, move the original into `image_originals/` next to it. |
| `--force` | Overwrite existing outputs and re-encode same-format inputs (default is to skip). |
| `-j, --jobs N` | Number of parallel workers (default: all CPU cores). |

---

## macOS Finder Quick Action

You can wire `main.py` into a right-click menu in Finder so you never have to open a terminal:

1. Open **Automator** → **New Document** → **Quick Action**.
2. At the top of the workflow:
   - **"Workflow receives current"** → `image files or folders`
   - **"in"** → `Finder`
3. Add a **Run Shell Script** action.
   - **Shell:** `/bin/zsh`
   - **Pass input:** `as arguments`
   - Script body:
     ```bash
     /usr/bin/env python3 /full/path/to/Heic-JPG_Converter/main.py "$@"
     ```
4. Save it as `Convert images`.
5. Optionally, in **System Settings → Keyboard → Keyboard Shortcuts → Services**, assign a shortcut.

Now you can select one or many images (or a folder) in Finder, right-click → Quick Actions → **Convert images**. A macOS notification will pop up when it's done. To target PNG or GIF, edit the shell script to append `-f png` or `-f gif`.

---

## License

MIT
