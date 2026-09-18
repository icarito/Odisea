#!/usr/bin/env python3
"""
tools/i18n_extract.py
Automated string extraction tool for Odisea (Godot 3, GDScript 1.x / TSCN).
Scans .gd and .tscn files (excluding addons/), extracts Spanish UI strings,
and merges them idempotently into locale/ui_strings.csv (keys,es,en).
"""

import sys
import os
import re
import csv
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = REPO_ROOT / "locale" / "ui_strings.csv"

# Extensions to exclude string literals
FILE_EXTENSIONS_PATTERN = re.compile(
    r'\.(png|tscn|gd|wav|ogg|mp3|tres|res|cfg|json|txt|md|shader|gdot|sfx|jpg|jpeg|svg|po|pot|translation)$',
    re.IGNORECASE
)

# Properties to extract in .gd
GD_PROP_PATTERN = re.compile(
    r'(?:\.\b|\b)(text|dialog_text|bbcode_text|placeholder_text|hint_tooltip|interaction_text)\s*=\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')'
)

# Functions to extract in .gd (tr(...) / TranslationServer.tr(...))
GD_TR_PATTERN = re.compile(
    r'(?:\bTranslationServer\s*\.\s*|\b)tr\s*\(\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')'
)

# Line-anchored properties in .tscn
TSCN_PROP_PATTERN = re.compile(
    r'^\s*(text|placeholder_text|hint_tooltip|bbcode_text|dialog_text)\s*=\s*"((?:[^"\\]|\\.)*)"'
)

# Exclusions regexes for GDScript lines
GD_EXCLUDE_LINE = re.compile(
    r'^\s*(#|print|prints|printerr|push_error|push_warning|assert|class_name\b|extends\b)'
)

def unescape_gd_string(s: str) -> str:
    """Strip quotes and decode standard GDScript string escape sequences."""
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        s = s[1:-1]
    # Handle standard unescapes
    s = s.replace('\\"', '"').replace("\\'", "'").replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
    return s

def should_exclude(literal: str) -> bool:
    """Check whether a string literal should be excluded from extraction."""
    s = literal.strip()
    if len(s) <= 1:
        return True
    if s.startswith("res://") or s.startswith("user://"):
        return True
    if "/" in s and not " " in s:  # typical file or node path without spaces
        return True
    if FILE_EXTENSIONS_PATTERN.search(s):
        return True
    # Ignore purely numeric, dimension (e.g. 1280x720) or symbol strings
    if re.match(r'^[0-9\s.,:;%\-+*/\\()_#@!=<>|xX]+$', s):
        return True
    return False

def scan_gd_file(file_path: Path) -> set:
    strings = set()
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Warning: could not read {file_path}: {e}", file=sys.stderr)
        return strings

    for line in lines:
        stripped = line.strip()
        if GD_EXCLUDE_LINE.match(stripped):
            continue
        # Remove inline comments
        comment_idx = line.find("#")
        code_part = line[:comment_idx] if comment_idx != -1 else line

        # Search tr(...)
        for match in GD_TR_PATTERN.finditer(code_part):
            raw_str = match.group(1)
            clean_str = unescape_gd_string(raw_str)
            if not should_exclude(clean_str):
                strings.add(clean_str)

        # Search property assignments
        for match in GD_PROP_PATTERN.finditer(code_part):
            raw_str = match.group(2)
            clean_str = unescape_gd_string(raw_str)
            if not should_exclude(clean_str):
                strings.add(clean_str)

    return strings

def scan_tscn_file(file_path: Path) -> set:
    strings = set()
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Warning: could not read {file_path}: {e}", file=sys.stderr)
        return strings

    for line in lines:
        match = TSCN_PROP_PATTERN.match(line)
        if match:
            raw_val = match.group(2)
            clean_str = unescape_gd_string(f'"{raw_val}"')
            if not should_exclude(clean_str):
                strings.add(clean_str)

    return strings

def scan_codebase(root_dir: Path) -> set:
    extracted = set()
    for entry in root_dir.rglob("*"):
        if not entry.is_file():
            continue
        rel = entry.relative_to(root_dir)
        # Exclude addons/ and hidden directories (.git, .import, etc.)
        if any(part.startswith('.') for part in rel.parts):
            continue
        if len(rel.parts) > 0 and rel.parts[0] == "addons":
            continue

        if entry.suffix == ".gd":
            extracted.update(scan_gd_file(entry))
        elif entry.suffix == ".tscn":
            extracted.update(scan_tscn_file(entry))

    return extracted

def load_existing_csv(csv_file: Path) -> dict:
    """
    Returns a dict: key -> en_translation
    """
    existing = {}
    if not csv_file.exists():
        return existing

    with open(csv_file, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if not header:
            return existing
        for row in reader:
            if not row:
                continue
            key = row[0]
            en_val = row[2] if len(row) >= 3 else ""
            existing[key] = en_val
    return existing

def save_csv(csv_file: Path, keys_map: dict):
    csv_file.parent.mkdir(parents=True, exist_ok=True)
    sorted_keys = sorted(keys_map.keys())
    with open(csv_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["keys", "es", "en"])
        for key in sorted_keys:
            writer.writerow([key, key, keys_map[key]])

def main():
    print(f"[i18n_extract] Scanning codebase at {REPO_ROOT}...")
    extracted_keys = scan_codebase(REPO_ROOT)

    if not extracted_keys:
        print("[i18n_extract] ERROR: No UI strings extracted! Exiting with status 1.", file=sys.stderr)
        sys.exit(1)

    existing_map = load_existing_csv(CSV_PATH)

    new_count = 0
    orphan_count = 0

    merged_map = {}

    # All extracted keys
    for k in extracted_keys:
        if k in existing_map:
            merged_map[k] = existing_map[k]
        else:
            merged_map[k] = ""
            new_count += 1

    # Preserve orphans
    for k, en_val in existing_map.items():
        if k not in extracted_keys:
            merged_map[k] = en_val
            orphan_count += 1

    save_csv(CSV_PATH, merged_map)

    total_keys = len(merged_map)
    print(f"[i18n_extract] Done.")
    print(f"  Total keys in CSV: {total_keys}")
    print(f"  Extracted active keys: {len(extracted_keys)}")
    print(f"  New keys added: {new_count}")
    print(f"  Orphan keys preserved: {orphan_count}")

if __name__ == "__main__":
    main()
