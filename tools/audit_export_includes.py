#!/usr/bin/env python3
import os
import re
import sys
import argparse
import subprocess
from pathlib import Path

ASSET_EXTENSIONS = {
    ".tscn", ".scn", ".tres", ".res", ".gd", ".shader", ".gdshader",
    ".jpg", ".jpeg", ".png", ".webp", ".hdr", ".exr", ".ogg", ".mp3",
    ".wav", ".glb", ".gltf", ".obj", ".fbx", ".dae", ".ttf", ".otf",
    ".anim", ".spk", ".gdns", ".gdnlib", ".oys", ".json"
}

# Directories that are dev-only or not intended for export
EXCLUDED_DIRECTORIES = {
    "agents", "dashboard", "android", "docs", "reports", "test_output",
    "ports", ".venv", ".mono", "ci", "build"
}

class Preset:
    def __init__(self, name):
        self.name = name
        self.export_filter = ""
        self.include_filter = ""
        self.exclude_filter = ""
        self.export_files = set()

def parse_export_presets(filepath):
    if not os.path.exists(filepath):
        return []

    presets = []
    current_preset = None

    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    lines = content.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()

        preset_match = re.match(r'\[preset\.(\d+)\]', line)
        if preset_match:
            current_preset = Preset(f"Preset {preset_match.group(1)}")
            presets.append(current_preset)

        if current_preset:
            if line.startswith("name = "):
                current_preset.name = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("export_filter = "):
                current_preset.export_filter = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("include_filter = "):
                current_preset.include_filter = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("exclude_filter = "):
                current_preset.exclude_filter = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("export_files = PoolStringArray("):
                files_str = line.split("(", 1)[1]
                while ")" not in files_str and i + 1 < len(lines):
                    i += 1
                    files_str += " " + lines[i].strip()
                files_str = files_str.split(")", 1)[0]
                files = re.findall(r'"([^"]+)"', files_str)
                current_preset.export_files.update(files)
        i += 1
    return presets

def godot_glob_to_regex(pattern):
    pattern = pattern.strip()
    if not pattern:
        return None

    # Escape all regex specials
    regex = re.escape(pattern)
    # Restore wildcards. We handle ** first.
    # ** matches any characters including /
    regex = regex.replace(r'\*\*', '.*')
    # * matches any characters including / (Godot 3 resources filter is recursive for *)
    regex = regex.replace(r'\*', '.*')
    regex = regex.replace(r'\?', '.')

    # Special case: if the pattern is just an extension like *.gd, it matches anywhere
    if '/' not in pattern and pattern.startswith('*.'):
        return re.compile(r'.*' + regex + '$', re.IGNORECASE)

    return re.compile('^' + regex + '$', re.IGNORECASE)

def matches_any(path, comma_separated_patterns):
    if not comma_separated_patterns:
        return False
    patterns = [p.strip() for p in comma_separated_patterns.split(',')]
    for p in patterns:
        regex = godot_glob_to_regex(p)
        if regex and regex.match(path):
            return True
    return False

def is_asset_included(path, preset):
    res_path = "res://" + path
    if res_path in preset.export_files:
        return True

    if preset.export_filter == "all":
        # In Godot, 'all' filter still respects exclude_filter
        excluded = matches_any(path, preset.exclude_filter)
        return not excluded

    if preset.export_filter == "resources":
        # In Godot 3 'resources' filter, file must be in include AND NOT in exclude
        included = matches_any(path, preset.include_filter)
        excluded = matches_any(path, preset.exclude_filter)

        # Exclude wins in Godot 3
        if excluded:
            return False
        return included

    return False

def get_staged_files():
    try:
        output = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            text=True
        )
        return output.splitlines()
    except Exception:
        return []

def get_all_tracked_files():
    try:
        output = subprocess.check_output(
            ["git", "ls-files"],
            text=True
        )
        return output.splitlines()
    except Exception:
        # Fallback to os.walk if not in git
        assets = []
        for root, dirs, files in os.walk("."):
            # Prune directories
            dirs[:] = [d for d in dirs if d not in {".git", ".import", ".godot"}]
            for f in files:
                rel_path = os.path.relpath(os.path.join(root, f), ".")
                assets.append(rel_path.replace("\\", "/"))
        return assets

def should_skip(path, presets):
    # Mitigation: core_v2/tests/ are dev-only
    if path.startswith("core_v2/tests/"):
        return True

    # Mitigation: top-level excluded directories
    parts = path.split("/")
    if parts[0] in EXCLUDED_DIRECTORIES:
        return True

    # Mitigation: addons/ are dev-only unless explicitly exported
    if path.startswith("addons/"):
        res_path = "res://" + path
        exported_in_any = False
        for p in presets:
            if res_path in p.export_files:
                exported_in_any = True
                break
        if not exported_in_any:
            return True

    return False

def main():
    parser = argparse.ArgumentParser(description="Audit Godot export includes.")
    parser.add_argument("--staged", action="store_true", help="Audit staged files only.")
    parser.add_argument("--all", action="store_true", help="Audit all tracked files.")
    args = parser.parse_args()

    if not args.staged and not args.all:
        args.staged = True

    presets = parse_export_presets("export_presets.cfg")
    if not presets:
        print("Error: Could not find or parse export_presets.cfg")
        return 1

    if args.staged:
        files_to_check = get_staged_files()
        mode_desc = "staged files"
    else:
        files_to_check = get_all_tracked_files()
        mode_desc = "all tracked files"

    problematic_files = []
    checked_count = 0

    for path in files_to_check:
        path = path.replace("\\", "/") # Normalize
        ext = os.path.splitext(path)[1].lower()
        if ext not in ASSET_EXTENSIONS:
            continue

        if should_skip(path, presets):
            continue

        checked_count += 1

        # A file is problematic only if it's NOT included in ANY preset
        included_in_at_least_one = False
        for p in presets:
            if is_asset_included(path, p):
                included_in_at_least_one = True
                break

        if not included_in_at_least_one:
            problematic_files.append(path)

    if problematic_files:
        print(f"Error: Found {len(problematic_files)} assets NOT included in any export preset:")
        for f in problematic_files:
            print(f"  {f}")
        print(f"\nChecked {checked_count} {mode_desc}.")
        return 1

    print(f"Success: All {checked_count} checked assets are properly included in export presets.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
