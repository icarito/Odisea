Odisea Prop Pipeline & Validation Specification (V2)

1. Overview

This document defines the standard for creating, testing, and validating interactive props in "Odisea". It establishes a strict "Prop Contract" to ensure determinism for the Replay System and introduces an automated CLI workflow (test_prop.sh) to allow AI Agents and Developers to validate assets headlesssly.

2. The Prop Contract (PropBase)

All interactive objects (doors, levers, fans) must inherit from InteractableBase.

2.1 Core Principles

Determinism: Visual state is a pure function of anim_progress (float 0.0 to 1.0).

Separation of Concerns: Logic resides in the parent; Visuals reside in _update_visuals().

Tooling: Scripts must use the tool keyword to preview logic in the Editor without running the game.

2.2 GDScript Specification

tool
extends InteractableBase
class_name PropBase

# --- COMPOSABILITY EXPORTS ---
# Automatic linking: If null, checks for parent/children in _ready
export(NodePath) var linked_switch_path 
export(Array, NodePath) var visual_parts_paths

# --- DEBUG & VALIDATION ---
export(bool) var debug_draw = false

func _ready():
    super._ready()
    _auto_wire_switches()

func _update_visuals():
    # MANDATORY: Map anim_progress (0.0 - 1.0) to visual properties
    var t = _ease_custom(anim_progress)
    
    # Example: Move parts
    for path in visual_parts_paths:
        var part = get_node_or_null(path)
        if part:
            # Logic implementation specific to the prop type
            pass


3. Switch Composability Strategy

Designers must be able to link switches (Interactors) to Props (Receivers) easily.

3.1 Hierarchy-Based Linking (Implicit)

If a PropBase is a child of a Switch (or vice-versa, depending on scene tree preference), or they share a common LogicGroup parent, they should auto-connect on _ready().

3.2 Direct Export Linking (Explicit)

Designers can drag-and-drop a Switch node into the linked_switch_path export variable.

Implementation Logic:

func _auto_wire_switches():
    if linked_switch_path:
        var switch = get_node(linked_switch_path)
        switch.connect("state_changed", self, "_on_switch_toggle")
        return

    # Fallback: Check parent
    if get_parent().has_signal("state_changed"):
        get_parent().connect("state_changed", self, "_on_switch_toggle")


4. Automation Pipeline (test_prop.sh)

We introduce a shell wrapper to interface between the AI Agent and the Godot Engine.

4.1 Workflow

Input: User/Agent invokes test_prop.sh --target="AirlockDoor" --base64.

Search: Script finds AirlockDoor.tscn in res://core/props/.

Execution: Runs Godot with PropStage.tscn and injects env vars.

OYS Logic: Godot runs prop_validator.oys.

Output: * Saves screenshots to res://test_output/.

If --base64 is set, prints the base64 string of the final state to stdout.

4.2 Environment Variables

The Godot SessionManager must read these OS environment variables:

OYS_PROP_PATH: Full resource path to the target .tscn.

OYS_AUTO_RUN: If true, immediately starts the validation OYS script.

5. Odyssey Script Template (prop_validator.oys)

This script runs inside the engine to perform the visual verification.

Logic Flow:

LOAD target prop into the stage.

WAIT for physics settling.

CAPTURE State 0 (Idle/Closed).

ACTIVATE the prop (simulate interaction).

WAIT for half of animation duration.

CAPTURE State 1 (Starting/Halfway).

WAIT for half of animation duration.

CAPTURE State 2 (Active/Open).