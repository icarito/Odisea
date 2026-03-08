from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[1]
EXPORT_PRESETS = REPO_ROOT / "export_presets.cfg"


def _preset_block(name: str) -> str:
    text = EXPORT_PRESETS.read_text()
    pattern = re.compile(r"\[preset\.\d+\]\n(.*?)(?=\n\[preset\.\d+\]|\Z)", re.S)
    for match in pattern.finditer(text):
        block = match.group(0)
        if f'name="{name}"' in block:
            return block
    raise AssertionError(f"Preset {name!r} not found in export_presets.cfg")


def test_html5_export_includes_all_reachable_resources():
    block = _preset_block("HTML5")
    assert 'export_filter="all_resources"' in block
    assert 'vram_texture_compression/for_desktop=true' in block
    assert 'vram_texture_compression/for_mobile=true' in block
