# FD-179: Export asset audit — pre-commit check for missing exports

## Problem
Every time a new asset (scene, texture, material, shader) is added to the project but not listed in `export_presets.cfg`'s `include_filter`, the exported build breaks at runtime. The asset is simply missing from the `.pck`. This has happened repeatedly with every feature.

The `export_presets.cfg` has 8 export presets, each with its own `include_filter` and `exclude_filter`. They have drifted apart — some include `core_v2/props/exhaust/*`, others `core_v2/update/native/*`, others don't. This divergence is itself a source of bugs.

## Goal
A pre-commit hook that checks whether staged asset files would be excluded from export. No more broken builds due to missing includes.

## How export_presets.cfg works (Godot 3)

The file has sections like:

```
[preset.0]
name = "Linux/X11 ARM64"
export_filter = "resources"
export_files = PoolStringArray( "res://scenes/Menu.tscn", ... )
include_filter = "*.gd, assets/hdris/2k_stars_milky_way.jpg, ..."
exclude_filter = "assets/hdris/*.hdr, core_v2/tests/*, ..."
```

Key rules:
- `export_filter = "resources"` means Godot only packs files that match `include_filter` AND are NOT in `exclude_filter`.
- **Exception**: files in `export_files` (the `PoolStringArray`) are ALWAYS included regardless of filters.
- A file matched by BOTH include and exclude → excluded. Exclude wins.
- Globs are comma-separated, support `*` and `**`.
- Godot compares against the path relative to `res://` (e.g. `assets/hdris/2k_stars_milky_way.jpg`).

## Gotchas discovered during prototyping

### 1. exclude_filter wildcards can accidentally catch files you want included
The old exclude had `assets/hdris/*` which caught `2k_stars_milky_way.jpg` (the panorama). Even though the .jpg was in include_filter, the wildcard in exclude won. Fix: only exclude the heavy `.hdr` files: `assets/hdris/*.hdr`.

### 2. export_files has priority over filters
Files listed in the `PoolStringArray` of `export_files` are always included, even if they match exclude_filter. The parser must handle multiline `PoolStringArray( "r1", "r2", ... )` spanning many lines in the `.cfg` file. These are mostly addon scenes and test utilities that are explicitly included despite general exclude patterns.

### 3. The 8 presets have slightly different include_filters
They are not identical. Consolidating them is risky (platform-specific assets like native libs for desktop vs web). Solution: the audit script should check against ALL presets and flag a file as problematic only if it's excluded by EVERY preset that actually exists (or at least by the main ones: HTML5 + Linux + Windows).

### 4. Some files are legitimately excluded
- Test scenes in `core_v2/tests/*` — intentionally not in builds
- `.hdr` files in `assets/hdris/` — too heavy (6.4 MB each), not needed at runtime
- Addon example scenes in `addons/qodot/example_scenes/*`
- Dev-only tool scenes

The audit must distinguish "excluded by mistake" from "excluded on purpose". One heuristic: if the file is referenced by a non-test scene as an `ext_resource`, it's probably needed.

### 5. Performance
Scanning all files in the repo (`--all` mode) takes ~1-2 seconds for ~7000 files. The `--staged` mode (pre-commit) is instant because it only checks files in the git stage. Use `--all` only in CI, not in pre-commit.

## Spec

### 1. Audit script (`tools/audit_export_includes.py`)

**Arguments:**
- `--staged` (default): read files from `git diff --cached --name-only --diff-filter=ACMR`
- `--all`: scan all files in the repo with asset extensions

**Asset extensions to check:**
`.tscn`, `.scn`, `.tres`, `.res`, `.gd`, `.shader`, `.gdshader`, `.jpg`, `.jpeg`, `.png`, `.webp`, `.hdr`, `.exr`, `.ogg`, `.mp3`, `.wav`, `.glb`, `.gltf`, `.obj`, `.fbx`, `.dae`, `.ttf`, `.otf`, `.anim`, `.spk`, `.gdns`, `.gdnlib`, `.oys`, `.json`

**Parsing `export_presets.cfg`:**
- Read line by line
- Detect `[preset.N]` sections
- Extract `name`, `include_filter`, `exclude_filter`
- Parse `export_files` PoolStringArray (may span multiple lines, ends with `)`)
- Return a list of `(preset_name, include_filter, exclude_filter, export_files_set)`

**Matching logic (per file and per preset):**
1. If file is in `export_files` → skip (always included)
2. If file matches `exclude_filter` AND does NOT match `include_filter` → flag as problem
3. If file matches both exclude and include → flag as problem (exclude wins in Godot 3)

**False positive mitigation:**
- If the file is inside `addons/` and NOT in export_files → skip (addons that are not explicitly exported are dev-only)
- If the file is in `core_v2/tests/` → skip (tests are dev-only)

**Exit code:** 0 if no issues, 1 if any issues found (blocks commit in pre-commit).

### 2. Pre-commit hook (`.githooks/pre-commit`)

Add after existing checks:
```
python3 tools/audit_export_includes.py --staged
```

### 3. CI integration (optional, not in pre-commit to avoid slowing pushes)

Add a step in `.github/workflows/ci.yml`:
```yaml
- name: Check export includes
  run: python3 tools/audit_export_includes.py --all
```

Run as warning (non-blocking) — it may report true positives for legitimately excluded files.

## Test plan

1. **Happy path**: stage a `.tscn` file that is properly included → pre-commit passes.
2. **Missing include**: stage a new `.jpg` that's not in include_filter but is in exclude_filter → pre-commit rejects with file path.
3. **Export_files exception**: stage a file from `export_files` that also matches exclude_filter → pre-commit passes.
4. **Heavy .hdr**: stage `assets/hdris/ringed_gas_giant_planet.hdr` → pre-commit warns (correctly — it's excluded on purpose).
5. **Test scene**: stage `core_v2/tests/SomeTest.tscn` → pre-commit passes (not supposed to be in builds).
6. **CI full scan**: run `--all` → output should be clean or contain only known false positives (addons).

## Out of scope
- Dynamic Godot export plugins that inject files at export time (future phase).
- Auto-patching `export_presets.cfg` (the script only reports, it doesn't modify files).
- Consolidating include_filters across presets (that's a separate task if needed).

## Files to create/modify
- `tools/audit_export_includes.py` (new)
- `.githooks/pre-commit` (add audit line)
- `.github/workflows/ci.yml` (add optional audit step)
- `export_presets.cfg` (may need minor fixes for exclude_filter precision)
