import os
import sys
import argparse
import subprocess
import re
import fnmatch

# Asset extensions that should be tracked for export
ASSET_EXTENSIONS = {
    '.tscn', '.scn', '.tres', '.res', '.gd', '.shader', '.gdshader',
    '.jpg', '.jpeg', '.png', '.webp', '.hdr', '.exr', '.tga',
    '.ogg', '.mp3', '.wav',
    '.glb', '.gltf', '.obj', '.fbx', '.dae',
    '.ttf', '.otf',
    '.anim', '.spk', '.gdns', '.gdnlib', '.oys', '.json',
    '.material', '.pub'
}

# Directories to ignore for the audit
IGNORE_DIRS = {
    '.git', '.import', 'build', '.ci-cache', 'reports', 'test_output',
    '.github', 'ci', '.vscode', '.venv', '.mono', 'notebooks',
    'agents', 'dashboard', 'docs'
}

def get_staged_files():
    """Returns a list of staged files using git."""
    try:
        cmd = ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMR']
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.splitlines()
    except subprocess.CalledProcessError:
        return []

def get_all_files():
    """Returns a list of all asset files in the repository."""
    all_files = []
    for root, dirs, files in os.walk('.'):
        # Skip ignored directories
        rel_root = os.path.relpath(root, '.')
        if rel_root == '.':
            parts = []
        else:
            parts = rel_root.split(os.sep)

        if any(part.startswith('.') or part in IGNORE_DIRS for part in parts):
            continue

        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in ASSET_EXTENSIONS:
                filepath = os.path.relpath(os.path.join(root, f), '.')
                # Normalize to use /
                filepath = filepath.replace('\\', '/')
                all_files.append(filepath)
    return all_files

def parse_export_presets(filepath):
    """Parses export_presets.cfg and returns a list of presets with their filters."""
    presets = []
    if not os.path.exists(filepath):
        return presets

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        with open(filepath, 'r', encoding='iso-8859-1') as f:
            content = f.read()

    # Split by sections [preset.N]
    sections = re.split(r'\[preset\.(\d+)\]', content)

    # sections[0] is everything before first preset
    for i in range(1, len(sections), 2):
        preset_index = sections[i]
        preset_content = sections[i+1]

        # Stop if we hit another main section like [preset.N.options]
        main_preset_part = preset_content.split('\n[')[0]

        name_match = re.search(r'name\s*=\s*"([^"]+)"', main_preset_part)
        name = name_match.group(1) if name_match else f"Preset {preset_index}"

        include_filter = ""
        include_match = re.search(r'include_filter\s*=\s*"([^"]*)"', main_preset_part)
        if include_match:
            include_filter = include_match.group(1)

        exclude_filter = ""
        exclude_match = re.search(r'exclude_filter\s*=\s*"([^"]*)"', main_preset_part)
        if exclude_match:
            exclude_filter = exclude_match.group(1)

        export_files = set()
        export_files_match = re.search(r'export_files\s*=\s*PoolStringArray\s*\((.*?)\)', main_preset_part, re.DOTALL)
        if export_files_match:
            files_str = export_files_match.group(1)
            paths = re.findall(r'"res://([^"]+)"', files_str)
            for p in paths:
                export_files.add(p)

        presets.append({
            'name': name,
            'include': [f.strip() for f in include_filter.split(',') if f.strip()],
            'exclude': [f.strip() for f in exclude_filter.split(',') if f.strip()],
            'export_files': export_files
        })
    return presets

def godot_glob_match(filepath, pattern):
    """
    Checks if filepath matches a Godot-style glob pattern.
    Godot globs:
    - *.gd matches any file ending in .gd in any directory.
    - assets/*.png matches any png in assets/ but NOT in assets/sub/.
    - assets/** matches everything in assets/ recursively.
    """
    filepath = filepath.replace('\\', '/')
    pattern = pattern.replace('\\', '/')

    # Extension-only pattern
    if '/' not in pattern:
        return fnmatch.fnmatch(filepath, pattern) or fnmatch.fnmatch(os.path.basename(filepath), pattern)

    # Recursive pattern
    if '**' in pattern:
        p = pattern.replace('**/', '___RECURSIVE___')
        p = p.replace('**', '___RECURSIVE___')
        p = fnmatch.translate(p)
        p = p.replace('___RECURSIVE___', '.*')
        return re.match(p, filepath) is not None

    # Standard glob match
    return fnmatch.fnmatch(filepath, pattern)

def matches_any(filepath, patterns):
    """Checks if a filepath matches any of the glob patterns."""
    for pattern in patterns:
        if godot_glob_match(filepath, pattern):
            return True
    return False

def is_file_included(filepath, preset):
    """Determines if a file is included in a specific preset."""
    if filepath in preset['export_files']:
        return True

    if matches_any(filepath, preset['exclude']):
        return False

    if matches_any(filepath, preset['include']):
        return True

    return False

def main():
    parser = argparse.ArgumentParser(description="Audit staged assets for export inclusion.")
    parser.add_argument('--staged', action='store_true', help="Check only staged files (default if no args).")
    parser.add_argument('--all', action='store_true', help="Check all files in the repo.")
    args = parser.parse_args()

    if not args.all and not args.staged:
        args.staged = True

    if args.all:
        files = get_all_files()
    else:
        files = get_staged_files()

    presets = parse_export_presets('export_presets.cfg')
    if not presets:
        print("No export presets found in export_presets.cfg")
        return

    issues = []
    files_checked_count = 0

    for f in files:
        f = f.replace('\\', '/')
        ext = os.path.splitext(f)[1].lower()

        if ext in ASSET_EXTENSIONS:
            if f.startswith('core_v2/tests/') or f.startswith('tests/'):
                continue

            if f.startswith('addons/'):
                in_any_export_files = any(f in p['export_files'] for p in presets)
                if not in_any_export_files:
                    continue

            files_checked_count += 1

            included_in_any = False
            for p in presets:
                if is_file_included(f, p):
                    included_in_any = True
                    break

            if not included_in_any:
                issues.append(f)

    if issues:
        print(f"\n[EXPORT AUDIT] Found {len(issues)} asset(s) that will be EXCLUDED from all export presets:")
        for f in issues:
            print(f"  ❌ {f}")
        print("\nPossible solutions:")
        print("1. Add the file (or a wildcard) to 'include_filter' in export_presets.cfg")
        print("2. List the file explicitly in 'export_files' for the relevant presets")
        print("3. If it's a test or dev-only tool, move it to 'core_v2/tests/' or 'addons/'")
        sys.exit(1)
    else:
        if args.all:
            print(f"[EXPORT AUDIT] Success: All {files_checked_count} assets are included in at least one export preset.")
        elif files_checked_count > 0:
            print(f"[EXPORT AUDIT] OK: All {files_checked_count} staged assets are covered by export presets.")
        else:
            print(f"[EXPORT AUDIT] No staged assets to check.")

if __name__ == "__main__":
    main()
