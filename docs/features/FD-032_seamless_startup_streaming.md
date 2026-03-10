# FD-032: Seamless Startup Streaming

**Status:** In Progress
**Priority:** High
**Effort:** Large
**Created:** 2026-03-09
**Completed:** -

## Problem

`BaseTerrace.tscn` is currently the project `main_scene`, so startup pays the full cost of instancing the entire level up front. That includes heavy scatter, optional interiors, shader warmup, camera systems, and decorative props before the player has control.

`OptionalNodeManager` already defers some scatter work, but it acts after the scene is instantiated. That helps runtime cost, not cold-start latency.

The target experience is a seamless loader: the game should start quickly, show a lightweight shell immediately, and hide heavy loading behind camera motion, train travel, cinematics, or other authored transitions.

## Solution

Adopt a phased startup architecture:

1. Add a minimal `Boot` scene as the new `main_scene`.
2. Reuse `SceneManager` and `ResourceLoader.load_interactive()` as the primary loading path.
3. Add `StartupTrace` instrumentation to capture real startup milestones in `user://startup_trace.json`.
4. Split `BaseTerrace` into a lightweight shell and streamable chunks in later phases.
5. Use `InstancePlaceholder` only as an authoring aid for preplanned chunk anchors, not as the primary streaming mechanism.

### Phase 0: Instrumentation

- Add `StartupTrace` autoload.
- Record key milestones:
  - autoload ready points
  - boot scene ready
  - scene transition requested
  - scene ready
  - startup gate opened
  - shader warmup started/completed
- Save the trace to `user://startup_trace.json`.

### Phase 1: Boot Shell

- Replace direct startup into `BaseTerrace.tscn` with `core_v2/bootstrap/Boot.tscn`.
- `BootLoader.gd` immediately requests the gameplay scene through `SceneManager.goto_scene(...)` with progress UI.
- Keep CLI replay/script/export compatibility by skipping normal boot autoload only for flows that already control scene loading.

### Phase 2: Chunked Terrace

- Extract `BaseTerrace` into:
  - `BaseTerraceShell.tscn`
  - `TerraceCoreGameplay.tscn`
  - `TerraceScatterBoxes.tscn`
  - `TerraceCryopods.tscn`
  - `TerraceInteriorWide.tscn`
  - `TerraceSecondaryFX.tscn`
- Load critical gameplay first and secondary decoration later.
- Keep decorative cryopods visual-only during cold start and reconstruct their collision procedurally after the startup gate instead of authoring a second collider-only scene.
- Treat `Scatter3D` as authoring/placement data, not as the batching mechanism. For cryopod decor, keep `Scatter3D2` editable as the layout source for now, but move repeated details such as `PersonCard` silhouettes and deferred colliders to chunk-level runtime builders. Reserve scene instances only for gameplay-relevant or nearby variants.
- `BaseTerraceCryopodDecor` now supports an editor bake flow that emits a compact layout resource (`BaseTerraceCryopodDecorLayout.tres`) and a separate runtime scene that reconstructs `MultiMesh` batches from that layout. The authored scene stays editable; the runtime scene stays small.
- The runtime `MultiMesh` batches must preserve source `GeometryInstance` flags for shell and glass (`cast_shadow`, `layers`, `use_in_baked_light`). The procedural `PersonCard` LOD should not cast or receive shadows, otherwise the interior pods pick up misleading directional-light shadows that were not part of the original decorative setup.

### Phase 3: Seamless Masking

- Use train travel, intro camera motion, tunnel occlusion, or cinematic framing to hide chunk polling and attach points.
- Delay non-critical shader warmup and optional visuals until after first control or after the player enters a masked zone.

### Phase 4: Decoration Strategy

- Replace authored-at-start scatter for decorative boxes/criopods with data-driven manifests, proxies, or `MultiMesh`.
- Spawn full `PushableBoxV2` only when interaction is possible or nearby.
- For decorative cryopods that need collision later, prefer one chunk-level runtime builder that walks the already-authored visuals and creates shared-shape `StaticBody` colliders after startup masking. Avoid one script per prop and avoid a dedicated collider `.tscn` when the authored visuals already define the transforms.
- Decorative cryopod materials may use reduced-resolution texture copies. For `BaseTerrace`, the current direction is to standardize the `DisplayCase_2` textures on the reduced set because the target presentation is SD and the original 1K textures are not paying for themselves.
- The current preferred cryopod decor path is: authored source scene -> baked layout resource -> runtime scene builds `shell`, `glass`, and `PersonCard` `MultiMesh` batches from external resources, plus deferred runtime colliders generated from the same layout. Use one collider per pod when gameplay needs per-pod collision separation.

## Determinism Constraint

The aggressive box hibernation path is not only a CPU optimization. It is also part of the replay/determinism contract for `PushableBoxV2`.

`PushableBoxV2` belongs to `replay_sync` and persists runtime state through snapshots. Any future startup or streaming optimization must preserve that handoff.

Rules for later phases:

- Do not replace a live `PushableBoxV2` with a proxy during recording or replay.
- Do not treat hibernation as a purely visual optimization; its snapshot handoff must remain valid.
- Use proxies or manifest-only decoration only for boxes that are guaranteed non-interactive before the session reaches them.
- If a streamed chunk can contain boxes that may already have moved, chunk attach must restore authoritative snapshot state before the box becomes active.

### Considered Options

- **Keep `BaseTerrace` as `main_scene` and defer more from `OptionalNodeManager`**: low risk, but it does not remove the initial scene instancing cost.
- **Use `PropEmitterArea` for startup scatter**: rejected for cold start, because the current emitter pre-instantiates its pool in `_ready()`.
- **Use `InstancePlaceholder` everywhere**: useful for editor-authored anchors, but not sufficient as the main loader because replacement still happens on the main thread.
- **Selected**: `Boot` shell + `SceneManager` interactive loading + startup trace + later chunk extraction.

## InstancePlaceholder Decision

`InstancePlaceholder` is not the main route for this feature.

It is acceptable for:

- keeping authored chunk anchor positions in the editor
- delaying instantiation of a known subtree until its resource is already loaded

It is not sufficient for:

- background loading by itself
- hiding large cold-start stalls
- replacing the need for chunk-level load orchestration

The primary loading route remains `ResourceLoader.load_interactive()` through `SceneManager`.

## Files to Modify

- `project.godot` (modify)
- `core_v2/bootstrap/Boot.tscn` (new)
- `core_v2/bootstrap/BootLoader.gd` (new)
- `core_v2/autoloads/StartupTrace.gd` (new)
- `core_v2/autoloads/SessionManager.gd` (modify)
- `core_v2/autoloads/HardwareProfile.gd` (modify)
- `core_v2/autoloads/OptionalNodeManager.gd` (modify)
- `core_v2/levels/ShaderWarmupTrigger.gd` (modify)
- `core_v2/levels/chunks/BaseTerraceCryopodDecor.tscn` (modify)
- `core_v2/levels/chunks/BaseTerraceCryopodDecor.gd` (new)
- `core_v2/levels/chunks/BaseTerraceCryopodDecorRuntime.tscn` (new)
- `core_v2/levels/chunks/BaseTerraceCryopodDecorRuntime.gd` (new)
- `core_v2/levels/chunks/CryopodDecorLayoutResource.gd` (new)
- `core_v2/props/CriopodParallaxDecor.tscn` (modify)

## Verification

1. Launch the project normally and confirm the loading overlay appears immediately while the gameplay scene is loaded through `Boot`.
2. Inspect `user://startup_trace.json` and verify milestone timestamps for boot request, scene ready, and startup gate.
3. Run a replay such as `user://replay_1773095917.json` and verify CLI replay still loads the recorded scene correctly.
4. Compare startup trace data before and after future chunk-splitting work.
