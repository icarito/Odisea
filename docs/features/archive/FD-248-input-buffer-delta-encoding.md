# FD-248: CoreV2 Input Buffer Delta Encoding

**Status:** In Progress
**Priority:** High
**Effort:** Medium
**Branch:** main (no feature branch — work directly on main)
**Created:** 2026-08-11
**Completed:** -

## Problem

`SessionManager.gd` records full `InputDataV2.to_dict()` per frame into the
replay buffer even when the player's input hasn't changed. Each frame entry
is ~20+ keys (boolean flags, float vectors, mouse delta) serialized as a
Dictionary → per-frame allocation churn on low-end Android, GC pressure, and
growing JSON replay files (minutes of recording → MB of JSON).

Dome_Intro went from 7→30+ FPS via GPU/LOD work, but the input-buffer path
remains a per-frame hot-path cost during recording sessions.

## Solution

**Delta-encoded input buffer** — same determinism, smaller footprint:

1. Full snapshot at frame 0 (already exists).
2. For subsequent frames, compare serialized input against the previous
   frame. If identical → emit compact "hold" marker with run-length. If
   changed → emit frame index + full input dict.
3. Determinism: replay reconstructs identical per-frame input sequence.
   `InputProviderV2.set_replay_data` contract stays the same (per-frame
   array), or gets an expander so ghost replay / OYS paths are untouched.
4. Ghost data and drift checkpoints: already sparse (only written when data
   exists) — keep as-is, keyed by frame index.

### Considered Options

- **Option A: per-frame full dict** (current) — simple, correct, expensive.
- **Option B: delta with hold markers (selected)** — keeps array/JSON
  interface, big size cut on idle/dialog scenes (80-95% reduction), low
  risk for determinism, modest code delta.
- **Option C: binary PackedByteArray codec** — max gain, breaks JSON
  consumers (ghosts, OYS tooling, central replay analysis). Rejected for
  now; note as follow-up.

## Files to Modify

- `core_v2/autoloads/SessionManager.gd` — record loop (~L1441), save path
  (~L1696), load path (~L1976), play_buffer / _play_buffer_internal
  (~L2105)
- `core_v2/input/InputDataV2.gd` — add canonical equality helper
  (compare `is_equal_to(other)` avoiding floating noise)
- `core_v2/input/InputProviderV2.gd` — `set_replay_data` / expander for
  compact format (~L244)
- `core_v2/systems/OYS_Resolver.gd` — verify buffer format compatibility
  for `.oys` replays (~L55)
- `tools/bench_input_buffer.gd` — new benchmark tool (follows
  `tools/bench_*.gd` pattern)

## Measurement (before optimization)

Jules must first add instrumentation to quantify:

1. Per-frame buffer append cost (`OS.get_ticks_usec` around `buffer.append`
   in recording loop).
2. Buffer size in memory after N frames (idle session vs active session).
3. JSON file size for a fixed-length recording (60s idle + 60s movement).
4. JSON save/load time via `_json_print_normalized` vs a compact format.

## Optimization Steps

1. Add `InputDataV2.is_equal_to(other: InputDataV2) -> bool` — canonical
   comparison avoiding floating-noise differences.
2. In `SessionManager` recording loop: check equality against previous
   frame; if equal → emit "hold" marker; if changed → emit full frame entry
   with index. Hold markers encode run-length so 1000 idle frames become a
   single compact entry.
3. `stop_and_save_recording`: write compact format (array of entries; each
   either `{"hold": N}` or `{"frame": idx, "input": {...}}`).
4. `load_and_play` / `_play_buffer_internal`: detect compact vs legacy
   format; expand hold markers back to per-frame input for playback.
   Keep legacy loader as fallback for old `.json` replays.
5. Update `OYS_Resolver._convert_frames_to_buffer` output to match new
   compact format.

## Backwards Compatibility

- Loader must detect format (legacy: array of just `{"input": ...}` or
  `{"snapshot": ...}` entries; new: array of `{"hold": N}` / `{"frame": idx,
  "input": ...}` entries).
- Old replay files continue to work via legacy code path.
- New recordings use compact format.

## Determinism Contract

- Replay of a compact-format recording must produce **identical**
  `final_expected_state` and drift validation results as the uncompressed
  version.
- Existing tests must pass unchanged:
  `core_v2/tests/test_determinism_v2.gd`
  `core_v2/tests/perf_test.oys`

## Estimated Gains (target)

| Scenario | Before (est.) | After (target) |
|----------|--------------|----------------|
| 60s idle recording | ~36K frames, ~20 MB JSON | ~2 KB compact |
| 60s active recording | ~36K frames, ~20 MB JSON | ~8-14 MB (mouse_delta always non-zero) |
| Per-frame allocation | 1 dict + 2-4 arrays | 0 (hold frames) or 1 small struct (changed) |
| Save time (JSON) | O(N) serialization | O(changed_frames) serialization |

Actual measurements from bench tool (step 1) will produce concrete numbers.

## Verification

1. Run `test_determinism_v2.gd` — must pass old and new format.
2. Record a 120s session with mixed idle/active, save compact, replay —
   drift validation must pass.
3. Ghost replays still work (ghost_manager path, compact format expansion).
4. OYS `.oys` replays still work (compact format in OYS_Resolver output).
5. Benchmark report from `tools/bench_input_buffer.gd` comparing old vs new.
