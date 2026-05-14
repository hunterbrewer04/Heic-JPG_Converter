# HEIC to JPG Converter

A Python tool to convert HEIC images to JPG format using the Pillow library and `pillow-heif` plugin. Point it at any file or folder from the CLI; metadata, quality, and parallelism are handled for you. Includes an optional macOS Finder Quick Action recipe so you can right-click photos and convert without opening a terminal.

**Looking for a menu bar app instead of a CLI?** A native SwiftUI / `MenuBarExtra` rewrite lives in [`app/`](app/) — no Python runtime needed, uses macOS's built-in Image I/O for HEIC → JPEG. See [`app/README.md`](app/README.md) for build and install instructions.

---

## Features

- Converts HEIC files (single file, multiple files, or whole folders — recursively).
- **Preserves EXIF metadata** (date taken, GPS, orientation, camera info).
- Saves at **quality 95 with 4:4:4 chroma** by default — visually lossless for photos.
- **Parallel conversion** using all CPU cores by default.
- **Progress bar** for batch jobs.
- Skips files that already have a `.jpg` sibling (override with `--force`).
- Optional `--archive` flag tucks original HEICs into a `heic_originals/` subfolder.
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

Convert a single photo:
```bash
python main.py ~/Downloads/IMG_1234.HEIC
```

Convert every HEIC in a folder (recursive):
```bash
python main.py ~/Pictures/iphone_dump
```

Multiple inputs (mixing files and folders works — Automator passes args this way):
```bash
python main.py ~/Desktop/photo1.HEIC ~/Desktop/photo2.HEIC ~/Pictures/trip
```

Send all output to a separate folder:
```bash
python main.py ~/Pictures/iphone_dump -o ~/Pictures/converted
```

Move originals into a `heic_originals/` subfolder after successful conversion:
```bash
python main.py ~/Pictures/iphone_dump --archive
```

### Options

| Flag | Description |
| --- | --- |
| `-o, --output DIR` | Write JPGs into `DIR` instead of alongside the source files. |
| `-q, --quality N` | JPG quality 1-100 (default: 95). |
| `--archive` | After converting, move the original HEIC into `heic_originals/` next to it. |
| `--force` | Overwrite existing `.jpg` files (default is to skip). |
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
4. Save it as `Convert HEIC to JPG`.
5. Optionally, in **System Settings → Keyboard → Keyboard Shortcuts → Services**, assign a shortcut.

Now you can select one or many HEICs (or a folder) in Finder, right-click → Quick Actions → **Convert HEIC to JPG**. A macOS notification will pop up when it's done.

---

## License

MIT
