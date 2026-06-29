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