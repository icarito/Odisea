# Feature Spec: VCamera Cinematic Integration

**Status:** Draft  
**Author:** Kilo (AI Agent)  
**Date:** 2026-02-21  
**Related:** `CinematicManager.gd`, `OYS_Interpreter.gd`, `intro.oys`

---

## 1. Overview

Integrate the **GodotVCamera** plugin into Odisea's cinematic system, treating VCamera as a **camera state** within the existing FSM architecture. This enables priority-based virtual camera blending for intro cinematics and in-game cutscenes.

### Goals

1. **VCamera as FSM State**: Add `VCAM_*` states to `CameraModeState` enum
2. **Safe Transitions**: Leverage existing latch/blend infrastructure for smooth handoffs
3. **OYS Control**: Add `VCAMERA_*` commands for script-driven cinematic sequencing
4. **Backward Compatibility**: Existing `CinematicPathRig` and `CinematicManager` APIs remain functional

### Non-Goals

- Replace `CinematicPathRig` entirely (both systems coexist)
- Real-time VCamera editing during gameplay
- Multi-viewport/split-screen support (future consideration)

---

## 2. Architecture

### 2.1 Current FSM States

```
CameraModeState (existing):
├── FREE_ACTIVE          # Player camera in control
├── TRANSITION_TO_CINEMATIC
├── CINEMATIC_ACTIVE     # CinematicPathRig active
├── TRANSITION_TO_FREE
└── RECOVERY
```

### 2.2 Proposed FSM Extension

```
CameraModeState (extended):
├── FREE_ACTIVE              # Player camera in control
├── TRANSITION_TO_CINEMATIC  # Blending TO CinematicPathRig
├── CINEMATIC_ACTIVE         # CinematicPathRig active
├── TRANSITION_TO_VCAM       # [NEW] Blending TO VCamera system
├── VCAM_ACTIVE              # [NEW] VCameraBrain controlling, highest-priority VCamera active
├── VCAM_BLENDING            # [NEW] Transitioning between VCameras within VCameraBrain
├── TRANSITION_VCAM_TO_FREE  # [NEW] Blending FROM VCamera back to player
├── TRANSITION_TO_FREE       # Blending FROM CinematicPathRig
└── RECOVERY                 # Error recovery state
```

### 2.3 State Diagram

```
                    ┌─────────────────────────────────────────────────┐
                    │                                                 │
                    ▼                                                 │
              ┌──────────┐                                            │
              │   FREE   │◄───────────────────────────────────────────┤
              │  ACTIVE  │                                            │
              └────┬─────┘                                            │
                   │                                                  │
        ┌──────────┴──────────┐                                       │
        │                     │                                       │
        ▼                     ▼                                       │
┌───────────────┐    ┌────────────────┐                              │
│  TRANSITION   │    │  TRANSITION    │                              │
│ TO_CINEMATIC  │    │  TO_VCAM       │                              │
└───────┬───────┘    └───────┬────────┘                              │
        │                    │                                        │
        ▼                    ▼                                        │
┌───────────────┐    ┌────────────────┐    ┌──────────────┐          │
│  CINEMATIC    │    │    VCAM        │───▶│  VCAM        │          │
│   ACTIVE      │    │   ACTIVE       │    │  BLENDING    │          │
└───────┬───────┘    └───────┬────────┘    └──────┬───────┘          │
        │                    │                    │                   │
        │                    └────────────────────┘                   │
        │                             │                               │
        ▼                             ▼                               │
┌───────────────┐            ┌────────────────┐                       │
│  TRANSITION   │            │ TRANSITION     │                       │
│  TO_FREE      │            │ VCAM_TO_FREE   │───────────────────────┘
└───────────────┘            └────────────────┘
```

### 2.4 VCameraBrain Integration

**Key Insight**: `VCameraBrain` IS a `Camera` node. Hybrid mode preserves existing player camera hierarchy.

```
Scene Hierarchy:
├── Pilot_v2
│   └── CameraRig/Yaw/Pitch/SpringArm/Camera (player camera, FREE_ACTIVE)
│
├── VCameraSystem
│   ├── VCameraBrain (Camera, disabled by default)
│   │   └── [controlled by CinematicManager when VCAM_* states active]
│   │
│   ├── IntroVCam_Far (VCamera, priority: 0, enabled: false)
│   │   ├── Follow (target: Pilot)
│   │   └── LookAt (target: Pilot)
│   │
│   ├── IntroVCam_Close (VCamera, priority: 0, enabled: false)
│   │   ├── Follow (target: Pilot, offset: (0, 2, 3))
│   │   └── LookAt (target: Pilot, offset: (0, 1.5, 0))
│   │
│   └── GameplayVCam (VCamera, priority: 0, enabled: false)
│
└── CinematicRigs (existing)
    └── CinematicPathRig [...]
```

---

## 3. Component Changes

### 3.1 CinematicManager.gd Changes

#### New Enum Values

```gdscript
enum CameraModeState {
    FREE_ACTIVE,
    TRANSITION_TO_CINEMATIC,
    CINEMATIC_ACTIVE,
    TRANSITION_TO_VCAM,       # NEW
    VCAM_ACTIVE,              # NEW
    VCAM_BLENDING,            # NEW
    TRANSITION_VCAM_TO_FREE,  # NEW
    TRANSITION_TO_FREE,
    RECOVERY
}
```

#### New Methods

```gdscript
func activate_vcamera(vcam: VCamera, duration: float = 1.0, ease: float = -2.0) -> int
func blend_to_vcamera(vcam: VCamera, duration: float = 1.0) -> void
func deactivate_vcamera(duration: float = 1.0) -> void
func get_active_vcamera() -> VCamera
func find_vcamera(name: String) -> VCamera
```

### 3.2 OYS_Interpreter.gd Changes

#### New Commands

| Command | Syntax | Description |
|---------|--------|-------------|
| `VCAMERA` | `VCAMERA name="<vcam_name>" [duration=1.0]` | Activate a VCamera by name |
| `VCAMERA_BLEND` | `VCAMERA_BLEND name="<vcam_name>" [duration=1.0]` | Blend to a different VCamera |
| `VCAMERA_RETURN` | `VCAMERA_RETURN [duration=1.0]` | Return to player camera |
| `VCAMERA_SHAKE` | `VCAMERA_SHAKE translation="(x,y,z)" rotation="(x,y,z)"` | Add shake to active VCamera |

---

## 4. Transition Handling

### 4.1 FREE → VCAM_ACTIVE

```
T=0.0: _current_state = TRANSITION_TO_VCAM
T=0.0: _engage_input_latch(player_camera)
T=0.0: VCameraBrain.current = true
T=0.0: target_vcam.enabled = true, priority = 100
T=Duration: _current_state = VCAM_ACTIVE
T=Duration+LATCH_TIMEOUT: Input latch released
```

### 4.2 VCAM_ACTIVE → FREE

```
T=0.0: _current_state = TRANSITION_VCAM_TO_FREE
T=0.0: _engage_input_latch(vcam_brain)
T=Duration: player_camera.current = true
T=Duration: All VCameras disabled, priority = 0
T=Duration: _current_state = FREE_ACTIVE
```

### 4.3 Alignment on Exit

```gdscript
func _align_player_rig_to_vcam(vcam: VCamera, player_cam: Camera):
    var vcam_forward = -vcam.global_transform.basis.z
    var yaw_angle = atan2(vcam_forward.x, vcam_forward.z)
    # Align player yaw/pitch to match VCamera orientation
```

---

## 5. OYS Script Example

```oys
SECTION "Intro"
    PRINT "ACTO I"
    SET_TIME_SCALE 0.5
    CINEMATIC
    
    VCAMERA name="IntroFar" duration=2.0
    WAIT 2.0
    
    PRINT "Elías, despierta..."
    PLAY_ANIM "Confused"
    
    VCAMERA_BLEND name="IntroClose" duration=1.5
    WAIT 1.5
    
    VCAMERA_SHAKE translation="(0.1, 0.1, 0)" rotation="(0, 0, 3)"
    
    VCAMERA_BLEND name="IntroFinal" duration=2.0
    SET_TIME_SCALE 1.0
    WAIT 2.0
    
    VCAMERA_RETURN duration=1.0
    INTERACTIVE
```

---

## 6. Testing Strategy

| Test | Description |
|------|-------------|
| `test_vcamera_state_transitions` | Verify FSM transitions between VCAM states |
| `test_vcamera_priority_blending` | Multiple VCameras, highest priority wins |
| `test_vcamera_oys_commands` | OYS interpreter executes VCAMERA commands |
| `test_vcamera_alignment_on_exit` | Player camera aligns correctly after VCamera |

---

## 7. Migration Path

### Phase 1: Core Integration
1. Add new states to `CameraModeState` enum
2. Implement VCamera API in CinematicManager
3. Add OYS commands
4. Create `VCameraSystem.tscn` template

### Phase 2: Scene Adoption
1. Add `VCameraSystem` to `BaseTerrace.tscn`
2. Create intro VCameras
3. Update `intro.oys`

### Phase 3: Polish
1. Debug overlay
2. Editor tooling
3. Performance profiling

---

## 8. Open Questions

1. **VCameraBrain vs Player Camera Hierarchy**: Hybrid mode chosen (separate VCameraBrain)
2. **Follow Target Resolution**: Both NodePath and runtime OYS override supported
3. **Replay Determinism**: Need deterministic Shake seeds for replays
