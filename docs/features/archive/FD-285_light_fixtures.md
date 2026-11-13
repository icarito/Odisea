# FD-285: Light fixtures upgrade (reflective path studs + sconce glass)

**Status:** Planned
**Priority:** High
**Effort:** Medium
**Created:** 2026-09-01
**Completed:** -

## Problem

Two fixture problems in the dome lighting language:

1. The SciFiLightPathV2 routes use full-size markers. The design calls for small
   **reflective studs** (small plastic-style road studs) along the path. There is no model:
   the stud must be generated procedurally.
2. The wall sconce fixture originally had a glass cover that was removed for performance
   (GLES2 transparency). What remains is a bare bulb that reads too retro compared to the
   rest of the fixture language.

Both must read correctly across the three dome light states defined in FD-284
(DARK / LOW-POWER / FULL).

## Environment setup (IMPORTANT — do this first)

This environment has no Godot installed. Install Godot 3 via apt before running any
validation:

```bash
sudo apt-get update && sudo apt-get install -y godot3
```

Then run all prop validations and screenshots with the apt binary:

- Prop screenshot validation: `./test_prop.sh <PropName> --editor-path=$(which godot3)`
  (validates that the prop renders differently across states; requires a minimum pixel
  delta between states — see `test_prop.sh` header).
- Unit tests: `./runtest.sh -a <test_file>` with the godot3 binary.

Do not skip visual validation: the deliverable includes screenshots of the new fixtures.

## Solution

### A. Reflective path studs (generated, MultiMesh)

- New component `core_v2/components/PathStudLayer.gd`: attached to (or reading from) the
  existing `LightPathV2` marker routes (e.g. `DomeIntro_SpokeLightPath_markers.tres`).
  At `_ready` it builds a `MultiMeshInstance` from the path's marker transforms — one draw
  call, zero lights, adapts to any dome automatically (no per-scene authoring).
- Stud mesh: generated procedurally with `SurfaceTool` — flattened hemisphere / beveled
  disc, **< 200 triangles**, shared as a single resource.
- Material: opaque metallic base + fresnel rim that brightens toward the camera
  (fake retroreflection). GLES2-safe: no real transparency, no reflections.
- State behavior (read from `DomeLightState` if present, else expose a settable state):
  - FULL: subtle emissive core on all studs.
  - LOW-POWER: only every Nth stud emissive, slow blink pattern.
  - DARK: no emissive, metallic base only.
- Replaces (or augments) the current full-size markers; keep the old marker scene
  functional for other uses.

### B. Wall sconce glass + bulb replacement

- Recover the previously removed glass mesh from git history if available
  (`git log --all --follow core_v2/props/scifi_lights/SciFiWallSconceV2*`); otherwise
  generate a simple curved cap (low poly).
- Glass material: **opaque frosted glass** — baked lighting means no real transparency is
  needed; emission comes from the lightmap. Zero GLES2 transparency cost.
- Replace the retro bulb visual inside the sconce with a horizontal emissive panel/tube
  (closer to the existing SciFiRecessedWallLightV2 language).
- Keep `IndustrialCagedSconce` as the service-area variant: do not delete it.

### Considered Options

- **Option A**: model studs in Blender and place per scene — rejected: no asset, per-scene
  authoring cost, does not adapt to other domes.
- **Option B**: runtime MultiMesh layer reading LightPathV2 routes — selected: one draw
  call, auto-adapts, no authoring.
- **Option C**: real transparent glass on sconces — rejected: GLES2 transparency cost was
  the reason it was removed; opaque frosted reads just as well with baked light.

## Constraints

- Godot 3.x / GDScript 1.x: `yield` with strings, `connect()` classic, no `@onready`, no
  Godot 4 syntax.
- GLES2: no new transparency, no new post-processing.
- No gameplay signal changes; fixtures only read state.
- Do not touch deterministic core_v2 logic beyond optional read-only hooks to
  `DomeLightState`.

## Files to Modify

- `core_v2/components/PathStudLayer.gd` (new) + generated stud mesh resource
- `core_v2/props/scifi_lights/SciFiLightPathV2.gd` (modify: optional stud layer hook)
- `core_v2/props/scifi_lights/SciFiWallSconceV2.tscn` + materials (modify: glass + panel)
- `core_v2/tests/test_path_stud_layer.gd` (new)
- `docs/features/FD-285_light_fixtures.md` (this file)

## Verification

1. `./runtest.sh -a ./core_v2/tests/test_path_stud_layer.gd` — MultiMesh builds from a
   route, stud count matches markers, state switch changes emissive pattern.
2. `./test_prop.sh SciFiWallSconceV2 --editor-path=$(which godot3)` — sconce renders and
   differs across states (screenshot delta check passes).
3. `./test_prop.sh SciFiPathMarkerV2 --editor-path=$(which godot3)` — path fixture still
   valid after the hook.
4. `godot3 --headless` project load without script errors
   (e.g. `godot3 --headless --quit` in the project root).
5. Screenshots of sconce (glass + panel) and studs in the three states attached to the PR.
