from __future__ import annotations

import sys
from pathlib import Path

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from main import (  # noqa: E402
    FORMATS,
    INPUT_EXTENSIONS,
    Status,
    collect_files,
    convert_one,
    dedupe_by_output,
)


def _make_rgb_image(path: Path, size: tuple[int, int] = (8, 8)) -> None:
    Image.new("RGB", size, color=(123, 45, 67)).save(path)


def _make_rgba_image(path: Path, size: tuple[int, int] = (8, 8)) -> None:
    Image.new("RGBA", size, color=(123, 45, 67, 128)).save(path)


def test_formats_registry_has_three_entries():
    assert set(FORMATS.keys()) == {"jpg", "png", "gif"}


def test_jpg_supports_quality_others_dont():
    assert FORMATS["jpg"].supports_quality is True
    assert FORMATS["png"].supports_quality is False
    assert FORMATS["gif"].supports_quality is False


def test_input_extensions_cover_common_formats():
    expected = {".heic", ".heif", ".jpg", ".jpeg", ".png", ".gif",
                ".tif", ".tiff", ".bmp", ".webp"}
    assert expected <= INPUT_EXTENSIONS


def test_collect_files_accepts_mixed_extensions(tmp_path: Path):
    for name in ("a.heic", "b.jpg", "c.png", "d.gif", "e.txt"):
        (tmp_path / name).touch()
    found = {p.name for p in collect_files([tmp_path])}
    assert found == {"a.heic", "b.jpg", "c.png", "d.gif"}


def test_collect_files_warns_for_unsupported_individual_file(tmp_path: Path, capsys):
    f = tmp_path / "notes.txt"
    f.touch()
    out = collect_files([f])
    assert out == []
    assert "not a supported image" in capsys.readouterr().out


def test_dedupe_by_output_respects_format_extension(tmp_path: Path):
    a = tmp_path / "x.heic"
    b = tmp_path / "x.jpg"
    a.touch(); b.touch()
    deduped = dedupe_by_output([a, b], tmp_path, "png")
    # both target tmp_path/x.png — one is dropped
    assert len(deduped) == 1


def test_convert_one_writes_png_for_png_target(tmp_path: Path):
    src = tmp_path / "src.jpg"
    _make_rgb_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=False, format_key="png")
    assert status == Status.CONVERTED
    out = tmp_path / "src.png"
    assert out.exists()
    with Image.open(out) as im:
        assert im.format == "PNG"


def test_convert_one_writes_gif_for_gif_target(tmp_path: Path):
    src = tmp_path / "src.jpg"
    _make_rgb_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=False, format_key="gif")
    assert status == Status.CONVERTED
    out = tmp_path / "src.gif"
    assert out.exists()
    with Image.open(out) as im:
        assert im.format == "GIF"


def test_convert_one_skips_when_same_format(tmp_path: Path):
    src = tmp_path / "already.png"
    _make_rgb_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=False, format_key="png")
    assert status == Status.SKIPPED


def test_convert_one_treats_jpeg_extension_as_same_as_jpg(tmp_path: Path):
    src = tmp_path / "photo.jpeg"
    _make_rgb_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=False, format_key="jpg")
    assert status == Status.SKIPPED


def test_convert_one_force_reencodes_same_format(tmp_path: Path):
    src = tmp_path / "again.png"
    _make_rgb_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=True, format_key="png")
    assert status == Status.CONVERTED


def test_convert_one_flattens_alpha_for_jpg(tmp_path: Path):
    src = tmp_path / "alpha.png"
    _make_rgba_image(src)
    status, _ = convert_one(src, tmp_path, quality=95, archive=False, force=False, format_key="jpg")
    assert status == Status.CONVERTED
    out = tmp_path / "alpha.jpg"
    with Image.open(out) as im:
        assert im.mode == "RGB"


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
