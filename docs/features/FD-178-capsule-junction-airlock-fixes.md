# FD-178: Fix procedural duct maze — CapsuleRoom, airlocks, gaps, chunks

Splits into independent work items below. Each has its own spec, branch, and Jules session.

---

## TANDA A — CapsuleRoom collision + openings (make_capsule)

**Branch:** `tanda-A/fd178-capsule-collision`

`core_v2/systems/DuctMazeStreamer.gd` function `make_capsule(connections, gy)` (line ~692).

**Problem:** The procedural CapsuleRoom has no collision body — player falls through. Port tubes (`make_arm`) butt against the solid capsule mesh surface; there is no hole for the player to walk through.

**Fix:**
1. Add a `StaticBody` child with trimesh collision (`_get_capsule_mesh(room_radius, room_height).create_trimesh_shape()`) so the shell surface collides.
2. For each connected port direction, add a collision cylinder at the port mouth matching the `make_arm` tube:
   ```gdscript
   var col_body = StaticBody.new()
   var col_shape = CollisionShape.new()
   col_shape.shape = _get_hollow_cylinder(port_len, duct_radius, duct_wall_thickness).create_trimesh_shape()
   col_body.add_child(col_shape)
   col_body.translation = dirs[i] * room_radius
   root.add_child(col_body)
   ```
3. Add a flat floor disc collision inside the capsule so the player has a walkable surface (a `CylinderShape` with small height at capsule bottom).
4. Do NOT modify the visual capsule mesh — collision-only fix (Option C from analysis). The visual shell covers gaps.

**Collision layer/mask:** Use the same values as junction arms (`collision_layer = 0` is fine for procedural tiles; actual collision from player side is handled by the player's own collision detection against any StaticBody).

**Test:** Player can walk into CapsuleRoom from any connected duct and stand on the floor inside.

---

## TANDA B — Enable airlock placement + fix standalone cycle

**Branch:** `tanda-B/fd178-airlocks`

`core_v2/systems/DuctMazeStreamer.gd` and `core_v2/components/AirlockControllerV2.gd`.

**Problem:** `generated_airlocks_enabled` defaults to `false`. When enabled, airlocks may not position correctly against CapsuleRoom ports, and the `standalone_cycle` may not complete (hangs at PRESURIZANDO).

**Fix:**
1. In `_generate_chunk_grid()` or wherever the scene sets up the maze, set `generated_airlocks_enabled = true`.
2. Verify `_select_airlock_cells()` correctly identifies CapsuleRoom cells. The MST generator passes `is_room` flag for rooms — confirm this reaches `cell.is_room`.
3. In `_add_room_airlock()`, verify the position calculation:
   - `tube_reach = room_radius * 2.0` for capsule rooms (C/T/X)
   - `room_radius = duct_radius * 1.6`
   - Airlock chamber inner half is `4.1` units
   - Test that `cell_pos + through * mouth_reach` aligns the chamber's inner door flush with the CapsuleRoom port tube.
4. **Standalone cycle:** `AirlockControllerV2` (`core_v2/components/AirlockControllerV2.gd`) may wait for a scene transition signal that never fires. Add a fallback timer: after 3 seconds in `PRESURIZANDO` state, auto-complete and open the exit door.
   - In `AirlockControllerV2._process()` or state machine: track `time_in_state`, if `state == PRESURIZANDO` and `time_in_state > 3.0 → force state to OPEN_EXIT`.
5. Ensure AirlockZoneV2 triggers the cycle when the player approaches. The zone's `on_player_entered()` should call `airlock_controller.start_cycle()`.

**Test:** In the maze, CapsuleRooms have an AirlockChamber at one tangential port. Approaching it triggers the door cycle (outer closes → PRESURIZANDO → inner opens → player passes).

---

## TANDA C — Fix gaps between duct pieces

**Branch:** `tanda-C/fd178-gaps`

`core_v2/systems/DuctMazeStreamer.gd` — mesh generation and positioning.

**Problem:** Visible gaps (≈1-5 cm) at seams between adjacent pieces (junction arm ↔ straight duct, arc ↔ straight, etc.).

**Diagnosis approach:**
1. Add debug output: for each cell, print its grid position (gx, gy) and the world transform of its tile. Compare adjacent cells to see if transforms differ by exactly `ring_step` in the expected axis.
2. Check `_grid_to_world()` — for adjacent cells at (gx, gy) and (gx, gy+1), the Y offset should be exactly `ring_step`. Floating point in `_axis_y(gy) = gy * ring_step` should be exact, but the basis rotation from tangent/radial may flip sign across the seam.
3. Verify `_get_hollow_cylinder()` produces meshes whose end-cap vertices are exactly at ±length/2 along the local Z axis with no epsilon gap.
4. Check that `make_arm` in junctions calls `_make_junction_arm` with `offset = ring_step * 0.25` and `length = ring_step * 0.5` so total reach from centre = `ring_step * 0.5`. The adjacent straight duct centre is at `ring_step`, with the near end at `ring_step - ring_step * 0.5 = ring_step * 0.5`. These should meet at exactly the same world point.

**Likely fix:** Round cell positions to a tolerance (e.g., snap to 3 decimal places) before placing tiles, to eliminate floating-point drift in the tangent basis calculation.

**Test:** No visible seam between any adjacent duct pieces when viewed from 1m away. Use a camera positioned inside the tube.

---

## TANDA D — Fix chunk boundary connections

**Branch:** `tanda-D/fd178-chunk-boundaries`

`core_v2/systems/DuctMazeStreamer.gd` — `_generate_chunk_grid()` and chunk placement.

**Problem:** Two adjacent chunks may generate different tile types at the seam (e.g., a Junction vs a Straight duct), producing a mismatch: the half-length extents don't match, leaving a gap or overlap.

**Fix (overlap-inflate approach):**
1. Each chunk generates `chunk_rings + 2` rings (one extra at top and bottom).
2. Only render the "inner" `chunk_rings` rings. The extra ring at each boundary is generated for collision/continuity but its geometry is hidden (or merged into the adjacent chunk).
3. Alternative: enforce that the first ring of chunk N+1 has the same MST connections as the last ring of chunk N. This can be done by:
   - Store the last ring's cell data from chunk N
   - Pass it as `seed_ring` to chunk N+1's MST generator
   - The MST gen uses this to force the first ring to match.
4. Simpler stopgap: ensure chunk boundaries always fall on straight duct pieces (DuctRadial), never on junctions or arcs. Filter the seam cells and if they're not `W` (straight), regenerate until they are.

**Test:** Adjacent chunks connect seamlessly — no gap, no overlap, player can walk from chunk 0 to chunk 1 without seeing a seam.

---

## Execution order

Tandas **A** + **B** are independent and can run in parallel (different functions in the same file, minimal overlap). Tanda **C** depends on A being stable (gaps are cosmetic, not blocking). Tanda **D** is lowest priority — chunks need to generate correctly first.

Recommended: A + B in parallel, then C, then D.
