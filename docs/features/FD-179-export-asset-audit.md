# FD-179: Asset export management — auto‑register new resources in export_presets.cfg

## Problem
Each time Jules (or anyone) adds a new resource (scene, texture, material, shader) to the project but forgets to list it in `export_presets.cfg`'s `include_filter`, the exported build breaks at runtime — the resource is simply missing from the `.pck`. This happens every single feature.

Current `export_presets.cfg` has 8 presets (HTML5, Linux, Windows, etc.), each with a slightly different `include_filter` / `exclude_filter` that must be kept in sync manually — they're **not identical** (some include `core_v2/props/exhaust/*`, others `core_v2/update/native/*`). This divergence is itself a source of bugs.

## Goal
Make the export include_filter reliable and self-documenting so that any resource in active use is automatically included.

## Constraints
- Godot 3.x export system: `include_filter` is a comma‑separated string of globs, one per line in the export preset editor. The `exclude_filter` overrides it when a path matches both.
- Cannot use a dynamic script‑based solution at export time (Godot 3 export plugins can run GDScript, but the filter is baked into the preset).
- Must not break existing builds.
- The `exclude_filter` must remain aggressive for dev‑only files (tests, scenes, tools).

## Possible solutions

### Option A — Audit script (recommended first step)
A GDScript tool (or Python script outside Godot) that:
1. Scans the Godot project for all `.tscn`, `.scn`, `.tres`, `.res`, `.gd`, `.shader` files.
2. For each scene/resource, reads its `ext_resource` dependencies recursively.
3. Cross‑references the full dependency tree against `include_filter` in `export_presets.cfg`.
4. Reports any **used** file that would be excluded at export time.
5. Optionally auto‑patches `export_presets.cfg` to add the missing globs.

Run this in CI after every PR merge.

### Option B — Godot export plugin
A small GDScript `EditorExportPlugin` that extends `_export_begin` and dynamically injects files via `add_file`. This way the `include_filter` stays generic and the plugin adds whatever the scene tree actually references.

Downside: Godot 3 export plugins run at export time and can slow the build if they scan the whole project.

### Option C — Consolidate into one canonical include_filter
Make all 8 presets share the **same** `include_filter` string (or as close as possible given platform‑specific differences like native libs). Then maintain that single list and keep it generous — include entire category directories (e.g., `core_v2/props/*`) instead of individual files.

## Recommended approach for this FD

### Phase 1 — Consolidate & audit
1. Normalize all 8 presets in `export_presets.cfg` to use the same base `include_filter` (keep only truly platform‑specific differences like `core_v2/update/native/*.gdns` for desktop only).
2. Write a GDScript tool at `tools/audit_export_includes.gd` that:
   - Reads `export_presets.cfg`
   - Scans the project filesystem for all resources (`.tscn`, `.tres`, `.res`, `.shader`, `.gdshader`, `.png`, `.jpg`, `.hdr`, `.ogg`, `.mp3`, `.glb`, `.obj`, `.fbx`)
   - Matches each file against include/exclude patterns of each preset
   - Reports files that would be excluded but are referenced by at least one scene via ext_resource
3. Print a report with files that need to be added.

### Phase 2 — CI integration
Add the audit script to the CI pipeline as a non‑blocking warning step. If new resources are orphaned from export, CI flags them.

### Phase 3 (future) — Export plugin
If the audit script works well for 2-3 sprints, consider a Godot export plugin that auto‑injects.

## Files to modify
- `export_presets.cfg` — consolidate include_filters across 8 presets
- `tools/audit_export_includes.py` — new audit script (Python, runs outside Godot)
- `.githooks/pre-commit` — add audit script to pre-commit hook
- `.github/workflows/ci.yml` — add audit step for `--all` mode

## Implementation status (prototype done by Odiseo, needs Jules formalization)

### Already done (as prototype):
1. **Fix exclude_filter for hdris**: changed `assets/hdris/*` to `assets/hdris/*.hdr` in all 8 presets, so `2k_stars_milky_way.jpg` (the panorama) is no longer excluded. The 6.4 MB `.hdr` files remain excluded.
2. **Audit script**: `tools/audit_export_includes.py`
   - Parses all 8 presets from `export_presets.cfg`
   - Matching: checks if a file path matches `exclude_filter` globs but NOT `include_filter` globs
   - Respects `export_files` (PoolStringArray): files explicitly listed there are always considered included
   - `--staged` mode (pre-commit): only checks files in git stage
   - `--all` mode (CI): scans entire repo for files with asset extensions
3. **Pre-commit hook**: added `python3 tools/audit_export_includes.py --staged` to `.githooks/pre-commit`

### What Jules should formalize/improve:
1. **GDScript version**: optionally rewrite as GDScript `tools/audit_export_includes.gd` that runs inside Godot editor for more accurate dependency resolution (could read actual `ext_resource` references from scenes)
2. **Consolidate include_filters**: make all 8 presets use the **same** base include_filter string, keeping only truly platform-specific additions (like `core_v2/update/native/*` for desktop)
3. **CI integration**: add audit step to `.github/workflows/ci.yml` that runs `python3 tools/audit_export_includes.py --all` and warns if files are excluded
4. **Edge cases**: 
   - Test with `.hdr` files staged → should warn (correctly, they shouldn't be in build)
   - Test with new `.jpg` referenced by a scene but missing from include_filter → should block commit
   - Verify all `export_files` PoolStringArray paths are correctly parsed (the Python parser handles multiline)

## Test
1. Run `python3 tools/audit_export_includes.py --all` — should report only files that are genuinely excluded (addons not in export_files, test resources, etc.)
2. Stage a file that's in exclude_filter → pre-commit should reject.
3. Export HTML5 build — should succeed and include the panorama, all duct textures, the new capsule room, etc.
4. Verify the 6.4 MB `.hdr` is NOT in the exported build (check .pck size).

## Out of scope
- Dynamic Godot export plugins (Phase 3).
- Fixing Godot 3's inherently fragile export system — we only mitigate it.

## Related notes
- If `project.godot` changes, the update system needs a new binary too (not just pck). This is FD-XXX (separate).
