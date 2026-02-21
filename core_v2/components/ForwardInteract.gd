extends KinematicBody

# ForwardInteract.gd - Proxy for Interaction
# Forwards interaction calls to parent and mirrors parent's state.

var interaction_text = "Interact" setget set_interaction_text, get_interaction_text
var is_active = false setget , get_is_active
var one_off = false setget , get_one_off
var auto_interact = false setget , get_auto_interact
var _auto_triggered = false setget set_auto_triggered, get_auto_triggered

func _ready():
	add_to_group("interactable")

func interact():
	print("[ForwardInteract] Interaction triggered on ", name)
	var p = get_parent()
	if p and p.has_method("interact"):
		p.interact()

func set_active(val):
	var p = get_parent()
	if p and p.has_method("set_active"):
		p.set_active(val)

func set_highlighted(enabled: bool, color: Color = Color.cyan):
	var p = get_parent()
	if p and p.has_method("set_highlighted"):
		p.set_highlighted(enabled, color)

func set_proximity_highlight(enabled: bool, color: Color = Color(0.0, 1.0, 1.0, 0.1)):
	var p = get_parent()
	if p and p.has_method("set_proximity_highlight"):
		p.set_proximity_highlight(enabled, color)

func is_in_group(group: String) -> bool:
	if group == "interactable": return true
	return.is_in_group(group)

# --- PROXY ACCESSORS ---

func get_is_active() -> bool:
	var p = get_parent()
	if p and "is_active" in p: return p.is_active
	return false

func get_one_off() -> bool:
	var p = get_parent()
	if p and "one_off" in p: return p.one_off
	return false

func get_auto_interact() -> bool:
	var p = get_parent()
	if p and "auto_interact" in p: return p.auto_interact
	return false

func get_auto_triggered() -> bool:
	var p = get_parent()
	if p and "_auto_triggered" in p: return p._auto_triggered
	return false

func set_auto_triggered(val):
	var p = get_parent()
	if p and "_auto_triggered" in p: p._auto_triggered = val

func get_interaction_text() -> String:
	var p = get_parent()
	if p and "interaction_text" in p: return p.interaction_text
	return interaction_text

func set_interaction_text(val):
	interaction_text = val
