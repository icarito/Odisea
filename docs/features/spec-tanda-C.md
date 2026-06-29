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