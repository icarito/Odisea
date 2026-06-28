#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import argparse

# Asset extensions to check as per FD-179
ASSET_EXTENSIONS = {
    ".tscn", ".scn", ".tres", ".res", ".gd", ".shader", ".gdshader",
    ".jpg", ".jpeg", ".png", ".webp", ".hdr", ".exr", ".ogg", ".mp3",
    ".wav", ".glb", ".gltf", ".obj", ".fbx", ".dae", ".ttf", ".otf",
    ".anim", ".spk", ".gdns", ".gdnlib", ".oys", ".json"
}

def get_staged_files():
    try:
        output = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
            text=True
        )
        return [line.strip() for line in output.splitlines() if line.strip()]
    except subprocess.CalledProcessError:
        return []

def get_all_assets():
    assets = []
    for root, dirs, files in os.walk("."):
        if ".git" in dirs:
            dirs.remove(".git")
        if ".import" in dirs:
            dirs.remove(".import")

        for file in files:
            path = os.path.relpath(os.path.join(root, file), ".")
            if any(path.lower().endswith(ext) for ext in ASSET_EXTENSIONS):
                assets.append(path)
    return assets

def godot_glob_to_regex(pattern):
    pattern = pattern.strip()
    if not pattern:
        return None

    # Replace Godot-style wildcards with regex
    # We use temporary markers to avoid overlapping replacements
    p = pattern.replace("**", "___DOUBLE_STAR___").replace("*", "___SINGLE_STAR___")
    p = re.escape(p)

    # ** matches everything including /
    p = p.replace("___DOUBLE_STAR___", ".*")
    # * matches everything except / (in the context of export filters)
    p = p.replace("___SINGLE_STAR___", "[^/]*")

    # If pattern doesn't contain a slash, it matches anywhere in the path
    if "/" not in pattern:
        return re.compile(f"(^|.*/){p}$", re.IGNORECASE)
    else:
        # Patterns starting with / (or just relative paths from root in Godot)
        # Godot paths in export presets don't start with / but are relative to res://
        return re.compile(f"^{p}$", re.IGNORECASE)

class Preset:
    def __init__(self, name):
        self.name = name
        self.include_filters = []
        self.exclude_filters = []
        self.export_files = set()

    def is_included(self, path):
        path_alt = path.replace(os.sep, "/")
        res_path = "res://" + path_alt

        # Rule: export_files has priority over filters
        if res_path in self.export_files:
            return True

        # Rule: Must match include_filter
        matched_include = False
        for regex in self.include_filters:
            if regex.search(path_alt): # search because of our (^|.*/) prefix for no-slash patterns
                matched_include = True
                break

        if not matched_include:
            return False

        # Rule: AND NOT match exclude_filter (Exclude wins)
        for regex in self.exclude_filters:
            if regex.search(path_alt):
                return False

        return True

def parse_presets(filepath):
    if not os.path.exists(filepath):
        return []

    presets = []
    current_preset = None

    with open(filepath, "r") as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("[preset."):
            current_preset = Preset(f"Preset {len(presets)}")
            presets.append(current_preset)
        elif current_preset is not None:
            if line.startswith("name ="):
                current_preset.name = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("include_filter ="):
                val = line.split("=", 1)[1].strip().strip('"')
                parts = [p.strip() for p in val.split(",") if p.strip()]
                current_preset.include_filters = [godot_glob_to_regex(p) for p in parts]
            elif line.startswith("exclude_filter ="):
                val = line.split("=", 1)[1].strip().strip('"')
                parts = [p.strip() for p in val.split(",") if p.strip()]
                current_preset.exclude_filters = [godot_glob_to_regex(p) for p in parts]
            elif line.startswith("export_files = PoolStringArray("):
                content = line[line.find("(")+1:]
                while ")" not in content and i + 1 < len(lines):
                    i += 1
                    content += " " + lines[i].strip()
                if ")" in content:
                    content = content[:content.find(")")]
                files = re.findall(r'"([^"]+)"', content)
                current_preset.export_files.update(files)
        i += 1
    return presets

def main():
    parser = argparse.ArgumentParser(description="Audit Godot export includes")
    parser.add_argument("--staged", action="store_true", help="Check only staged files")
    parser.add_argument("--all", action="store_true", help="Check all asset files")
    args = parser.parse_args()

    # Default to staged if no arguments provided
    if not args.staged and not args.all:
        args.staged = True

    if args.all:
        files_to_check = get_all_assets()
    else:
        staged = get_staged_files()
        files_to_check = [f for f in staged if any(f.lower().endswith(ext) for ext in ASSET_EXTENSIONS)]

    if not files_to_check:
        if args.staged:
            print("No staged assets to check.")
        else:
            print("No assets found in project.")
        return 0

    presets = parse_presets("export_presets.cfg")
    if not presets:
        print("Error: No export presets found in export_presets.cfg")
        return 1

    # Directories to ignore (dev-only, tools, etc.)
    IGNORE_DIRS = {
        "agents/", "dashboard/", "docs/", "reports/", "test_output/",
        "ports/", "android/", ".venv/", ".mono/", "core_v2/tests/",
        ".vscode/", ".github/", ".githooks/", "tools/"
    }

    IGNORE_FILES = {
        "vercel.json", "project.godot", "export_presets.cfg", "CHANGELOG.md",
        "README.md", "AGENTS.md", "package.json", "package-lock.json"
    }

    problems = []
    for path in files_to_check:
        path_alt = path.replace(os.sep, "/")
        if path_alt.startswith("./"):
            path_alt = path_alt[2:]

        # False positive mitigation
        # 1. Check ignored directories and files
        if any(path_alt.startswith(d) for d in IGNORE_DIRS):
            continue
        if path_alt in IGNORE_FILES:
            continue

        # 2. addons/ -> skip unless explicitly in export_files
        if path_alt.startswith("addons/"):
            explicitly_exported = False
            res_path = "res://" + path_alt
            for p in presets:
                if res_path in p.export_files:
                    explicitly_exported = True
                    break
            if not explicitly_exported:
                continue

        # 3. Specifically excluded heavy files on purpose as per FD-179
        if path_alt.endswith(".hdr") or path_alt.endswith(".exr"):
            continue

        # 4. Git-related and other non-asset files that might slip in
        if path_alt.startswith(".git/") or path_alt == "project.godot":
            continue

        included_anywhere = False
        for p in presets:
            if p.is_included(path):
                included_anywhere = True
                break

        if not included_anywhere:
            problems.append(path)

    if problems:
        print(f"Error: Found {len(problems)} asset(s) excluded from ALL export presets:")
        for p in problems:
            print(f"  {p}")
        print("\nThese files will be missing from the exported .pck.")
        print("Please add them to 'include_filter' in 'export_presets.cfg'.")
        return 1

    print(f"Audit complete. All {len(files_to_check)} asset(s) are correctly included in at least one export preset.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
