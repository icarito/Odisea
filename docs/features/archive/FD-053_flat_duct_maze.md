# FD-053: Flat Duct Maze (Scaffold-based)

**Status:** Draft v1
**Priority:** P1
**Effort:** Medium
**Created:** 2026-06-27
**Based on:** FD-052 (abandoned polar approach)

## Goal

Replace the polar/radial duct maze with a flat 2D grid maze using the existing
ScaffoldMSTGenerator. Once working, it can later be wrapped into a cylinder.

## Design

### Grid

- `ScaffoldMSTGenerator` runs on a flat XZ grid (no wrap_x, no polar projection).
- Cell size: 4m × 4m. Each cell is either empty or a duct piece.
- Height is constant (Y=0), no vertical levels in v1.
- Generator produces MST with connections N/E/S/W.
- 8×8 grid (64 cells), or adjustable via exports.

### Pieces (same 7 variants as FD-052)

| Variant | Geometry | Collision |
|---------|----------|-----------|
| E | Dead-end stub 1m + cap | CylinderShape(r=2, h=1) |
| W (rot 0) | DuctRadial: cylinder 4m, Z=forward | CylinderShape(r=2, h=4) |
| W (rot 90) | DuctElbow: 90° arc, r=2m | BoxShape per segment |
| C | Junction 2 arms | Sphere(r=2.5) + 2 CylinderShape |
| T | Junction 3 arms | Sphere + 3 cylinders |
| X | Junction 4 arms | Sphere + 4 cylinders |
| S | Incline: sloped duct (not used in v1) | — |

### Materials

Same as FD-052: DuctHull.tres, DuctFloorGrate.tres, DuctConduit.tres.

### Test Scene

`core_v2/tests/DuctPieceTestScene.tscn` — one piece of each type on a flat
plane, spaced 10m apart, with a Label3D above each showing name + status.

### Player

No zero-gravity. Player starts at (0, 2, 5) with standard controller.

## Files

### New
- `core_v2/systems/DuctMazeStreamerFlat.gd` — flat version of the streamer

### Modified
- `scenes/levels/act0_duct_maze.tscn` — uses DuctMazeStreamerFlat
- `core_v2/tests/DuctPieceTestScene.tscn` — flat scene with labels

### Deleted (from FD-052)
- `core_v2/systems/DuctMazeSpawner.gd`
- `core_v2/systems/DuctMazeStreamer.gd`
- `core_v2/systems/DuctMazeStreamer.tscn`
- `core_v2/props/duct/*` (all individual CSG tiles, already deleted)
- `scenes/levels/act0_duct_maze.tscn` (rewritten)

## Tandas

### Tanda 1: DuctMazeStreamerFlat + DuctPieceTestScene

1. Write `DuctMazeStreamerFlat.gd`:
   - Extends Spatial, tool
   - Export: grid_width=8, grid_depth=8, room_count=2, extra_cycles=2
   - Instantiates ScaffoldMSTGenerator, generates grid
   - `_grid_to_world(gx, gy)` → Transform with Z=forward, X=right, Y=up
     (no polar math, just: `Vector3(gx*4, 0, gy*4)`)
   - `instantiate_tile()` → same logic as FD-052: Radials for "W" straight,
     Elbows for "W" curved (rotation 90/270), Junctions for C/T/X, Endcaps
   - All collision on layer 7 (Prop)
   - `_ready()` calls `generate()` always (runs in editor)
   - Mesh procedural: `_get_hollow_cylinder()` with SurfaceTool (same code
     as FD-052). Materials from `res://core_v2/props/duct/*.tres`.
   - Structural rings and floor grates as visual detail.

2. Write/rewrite `core_v2/tests/DuctPieceTestScene.tscn` + `.gd`:
   - Flat ground plane.
   - One piece of each type, spaced 10m apart.
   - Label3D above each piece showing name.
   - Player at origin with standard controller.
   - No zero-gravity.

### Tanda 2: Integration + Polish

1. Hook `act0_duct_maze.tscn` to the new streamer.
2. Remove old FD-052 files.
3. Test in editor: pieces visible, player walks through them, camera passes
   through walls (layer Prop), collisions work.
