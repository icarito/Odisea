# Input-Based Replay System — v1 Plan (Godot 3)

## Objective

Implement a **visually deterministic replay system** based on **input simulation**, tolerant to Godot 3’s non-deterministic physics.  
The system uses **snapshots only for drift correction**, not as the primary driver of simulation.

This implementation **intentionally breaks compatibility with previous replay attempts** and redefines input and camera architecture from the ground up.

---

## Non-Negotiable Principles

1. **Simulated input is the single source of truth.**
2. **Recorded state must never drive rotation.**
3. **Replay advances exclusively in `_physics_process`.**
4. **Camera behavior derives only from simulated input.**
5. **Snapshots correct drift; they do not guide simulation.**

Violating any of these guarantees an unstable replay.

---

## High-Level Architecture

- **InputState** — authoritative input layer (live / record / playback)
- **ReplayFrame** — per-physics-frame input data
- **ReplaySnapshot** — periodic correction state
- **ReplayController** — playback orchestration

---

## Step-by-Step Implementation Plan

### 1️⃣ Global `InputState` (Autoload)

Create a global `InputState` singleton with modes:

- `LIVE`
- `RECORD`
- `PLAYBACK`

Responsibilities:

- Store logical actions (bools / axes)
- Store mouse delta
- Provide a unified interface for gameplay and camera code

**Hard rule:**  
> No gameplay or camera script may call `Input.*` directly.

---

### 2️⃣ Gameplay & Camera Refactor

Refactor all gameplay and camera logic (`Player`, `PlayerSpringCam.gd`, etc.) so that:

- They **read exclusively from `InputState`**
- No script:
  - Reads raw mouse input
  - Queries `Input.is_action_pressed`
  - Integrates rotation outside `_physics_process`

Camera rules:

- Rotation is integrated **only from simulated input**
- No smoothing or interpolation outside the physics tick

---

### 3️⃣ Replay Architecture

Explicitly separate:

#### `ReplayFrame`
- Logical input states
- Mouse delta
- One instance per physics frame

#### `ReplaySnapshot`
- Player transform (position only)
- Linear / angular velocity
- Explicit player internal state
- Camera accumulated state

Replay behavior:

- Advances **exactly one frame per physics tick**
- Never depends on real time or render framerate

---

### 4️⃣ Snapshot System (Every 100 Frames)

Each snapshot must contain:

#### Player
- `global_transform.origin`
- `linear_velocity`
- `angular_velocity` (if applicable)
- Explicit internal state (e.g. grounded, stamina, etc.)

#### Camera
- Accumulated yaw / pitch
- Internal offsets
- Any variable that integrates error over time

⚠️ Avoid generic “state dictionaries” without a defined contract.

---

### 5️⃣ Snapshot Restoration

When restoring a snapshot:

1. Restore player state
2. Restore camera accumulated state
3. Reset internal integrators
4. Resume simulation using recorded input

Never:
- Force player `basis`
- Force camera yaw / pitch directly

Rotation must emerge naturally from input replay.

---

### 6️⃣ Hard Reset Before Playback

Before starting playback, perform **exactly one**:

- **Preferred:** reload the main scene
- **Alternative:** restore a full initial snapshot

Additionally:

- Clear `InputState`
- Reset replay counters
- Disable live input influence

---

### 7️⃣ UI, Mouse, and Overlays

- Mouse capture occurs only when **no UI overlays are active**
- During playback:
  - Live input is fully ignored
- UI must never write into `InputState`

---

## Further Considerations

1. **Explicit camera state contract**
   - Document all accumulated variables
2. **Replay lifecycle documentation**
   - record → snapshot → restore → playback
3. **Optional drift detection**
   - state hashing per snapshot

---

## Success Criteria

The system is considered correct if:

- Replay visually matches the original session
- Player and camera rotation are driven solely by replayed input
- Long replays remain stable due to snapshots
- Live user input has zero effect during playback
- The architecture allows future extensions without reintroducing `Input` dependencies

---

## Summary

This replay system is **input-authoritative**, **physics-driven**, and **snapshot-corrected**.

If any part of the system regains control over rotation or reads live input during playback, the replay is invalid by design.
