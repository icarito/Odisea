# Interaction System Implementation Plan

This document identifies missing and incomplete components in the interaction system and provides a prioritized implementation roadmap.

## Current State Analysis

### ✅ Complete Components

| Component | Location | Status |
|-----------|----------|--------|
| InteractableBaseV2 | `core_v2/components/InteractableBaseV2.gd` | ✅ Fully implemented |
| PropBaseV2 | `core_v2/components/PropBaseV2.gd` | ✅ Auto-wiring works |
| SlidingObjectV2 | `core_v2/components/SlidingObjectV2.gd` | ✅ Complete |
| RotatingObjectV2 | `core_v2/components/RotatingObjectV2.gd` | ✅ Complete |
| PushButtonV2 | `core_v2/components/PushButtonV2.gd` | ✅ Complete |
| PressurePlateV2 | `core_v2/components/PressurePlateV2.gd` | ✅ Complete |
| LogicCircuitManager | `core_v2/systems/circuit/LogicCircuitManager.gd` | ✅ Runtime works |
| CircuitGraphResource | `core_v2/systems/circuit/CircuitGraphResource.gd` | ✅ Data storage works |
| CircuitCable | `core_v2/systems/circuit/CircuitCable.gd` | ✅ Procedural generation |
| InteractableBridge | `core_v2/components/InteractableBridge.gd` | ✅ Basic bridging |
| test_prop.sh | `./test_prop.sh` | ✅ Validation pipeline |

### ⚠️ Incomplete Components

| Component | Issue | Priority |
|-----------|-------|----------|
| CircuitBoard (Visual Editor) | Missing: Add node UI, property inspector, hierarchy sync | High |
| PropBaseV2 | Auto-wiring only checks parent, not children properly | Medium |
| InteractableBridge | No multi-target export array | Medium |
| CircuitCable | CSG mode crashes in editor without scene assigned | Low |

### ❌ Missing Components

| Component | Description | Priority |
|-----------|-------------|----------|
| InteractionSensor | Volume-based detection for player | High |
| Wireless Connection | OLCS WiFi signal type | Low |

### ✅ Already Exists

| Component | Location | Notes |
|-----------|----------|-------|
| Prop Zoo Scene | `core_v2/tests/TestScenePropZoo.tscn` | Auto-discovers props, creates exhibits with levers |

## Implementation Roadmap

### Phase 1: PropBaseV2 Improvements (Priority: HIGH) ✅ COMPLETE

**Goal:** Robust auto-wiring for all hierarchy patterns.

#### Tasks

1. **Fix Child Discovery** ✅
   - Added child discovery in `_auto_wire_switches()`
   - Props now check: explicit path → multi-switch paths → parent → children

2. **Add Multi-Switch Support** ✅
   - Added `export(Array, NodePath) var linked_switch_paths`
   - Connects to all switches in array
   - OR logic: any switch activates prop

3. **Editor Preview**
   - [ ] Show connection lines in 3D view
   - [ ] Gizmo for CableAnchor position

### Phase 2: Interaction Sensor (Priority: MEDIUM) ✅ ALREADY EXISTS

**Status:** Volume-based detection already implemented in `PlayerControllerV2.gd`

The existing implementation includes:
- `_interact_area`: Area node with BoxShape for volume detection
- `_process_interaction()`: Candidate evaluation with distance scoring
- `interactable_in_range` / `interactable_out_of_range` signals
- Highlight system via `set_highlighted()`

**Location:** `core_v2/player/PlayerControllerV2.gd:426-494`

#### Potential Enhancements (Optional)
- [ ] Add angle-to-camera scoring for better target selection
- [ ] Add line-of-sight check to prevent through-wall interaction
- [ ] Extract as separate component for reusability

### Phase 3: Visual Editor Enhancement (Priority: LOW) ✅ PARTIAL

**Goal:** Make the Circuit Board usable for designers.

#### Tasks

1. **Add Node Palette** ✅
   - Toolbar with Add Prop button
   - Gate dropdown: AND, OR, XOR, NOT, DELAY
   - Refresh and Clear buttons

2. **Property Inspector**
   - [ ] Selecting a node shows properties in dock
   - [ ] DELAY gate: editable `delay_time`
   - [ ] Connection: cable material, slack, type dropdown

3. **Hierarchy Sync**
   - [ ] Scan scene tree for parent-child InteractableBaseV2 pairs
   - [ ] Auto-create nodes for hierarchy-linked props
   - [ ] Visual indicator for hierarchy vs manual connections

## File Structure After Implementation

```
core_v2/
├── components/
│   ├── InteractableBaseV2.gd      # ✅ No changes
│   ├── PropBaseV2.gd              # 🔧 Enhanced auto-wiring
│   ├── InteractableBridge.gd      # 🔧 Multi-target support
│   ├── InteractionSensor.gd       # 🆕 New component
│   └── InteractionSensor.tscn     # 🆕 New scene
├── systems/
│   └── circuit/
│       ├── LogicCircuitManager.gd # ✅ No changes
│       ├── CircuitGraphResource.gd# ✅ No changes
│       └── CircuitCable.gd        # 🔧 Editor safety
├── scenes/
│   └── PropStage.tscn             # ✅ Already exists
├── tests/
│   ├── TestScenePropZoo.tscn      # ✅ Already exists
│   └── TestScenePropZoo.gd        # ✅ Already exists
└── scripts/
    └── prop_validator.oys         # ✅ Already exists

addons/
└── odyssey_circuit_editor/
    ├── CircuitBoard.gd            # 🔧 Major enhancement
    ├── CircuitBoard.tscn          # 🔧 Add palette
    ├── NodePalette.tscn           # 🆕 New UI
    └── PropertyInspector.tscn     # 🆕 New UI
```

## Testing Strategy

### Unit Tests

| Component | Test File | Focus |
|-----------|-----------|-------|
| InteractableBaseV2 | `test_interactable_base.gd` | State machine, signals |
| PropBaseV2 | `test_prop_base.gd` | Auto-wiring |
| LogicCircuitManager | `test_logic_circuit.gd` | Gate logic, propagation |
| InteractionSensor | `test_interaction_sensor.gd` | Candidate evaluation |

### Integration Tests (OYS)

| Scenario | Script | Validates |
|----------|--------|-----------|
| Lever → Door | `test_lever_door.oys` | Hierarchy linking |
| AND gate logic | `test_and_gate.oys` | OLCS propagation |
| Cable destruction | `test_cable_sever.oys` | Connection breaking |
| Prop Zoo batch | `test_prop_zoo.oys` | All props animate |

## Effort Estimates

| Phase | Complexity | Status |
|-------|------------|--------|
| Phase 1: PropBaseV2 | Low | ✅ COMPLETE |
| Phase 2: Interaction Sensor | - | ✅ ALREADY EXISTS |
| Phase 3: Visual Editor | High | ⏳ Pending |

## Summary

The interaction system is more complete than initially assessed:

1. **PropBaseV2** - Enhanced with multi-switch support and child discovery
2. **InteractionSensor** - Already implemented in PlayerControllerV2
3. **Visual Editor** - Basic functionality exists, enhancement is optional

## Next Steps

1. **Complete:** PropBaseV2 improvements committed
2. **Documented:** Interaction sensor already works
3. **Optional:** Visual Editor enhancement (low priority)
