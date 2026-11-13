extends KinematicBody

# ForwardInteract.gd - Proxy for Interaction
# Forwards interaction calls to parent and mirrors parent's state.

var interaction_text = "Interactuar" setget set_interaction_text, get_interaction_text
var interaction_title := "" setget set_interaction_title, get_interaction_title
var interaction_description := "" setget set_interaction_description, get_interaction_description
var interaction_verb_active := "" setget set_interaction_verb_active, get_interaction_verb_active
var interaction_verb_inactive := "" setget set_interaction_verb_inactive, get_interaction_verb_inactive
var interaction_icon: Texture = null setget set_interaction_icon, get_interaction_icon
var is_active = false setget , get_is_active
var one_off = false setget , get_one_off
var auto_interact = false setget , get_auto_interact
var _auto_triggered = false setget set_auto_triggered, get_auto_triggered
var is_interactable = true setget set_is_interactable, get_is_interactable

func _ready():
	set_is_interactable(get_is_interactable())

func interact():
	if not get_is_interactable():
		return
	print("[ForwardInteract] Interaction triggered on ", name)
	if _forward_airlock_owned_interaction():
		return
	var p = get_parent()
	if p and p.has_method("interact"):
		p.interact()

func _forward_airlock_owned_interaction() -> bool:
	var source: Node = self
	if not source.has_meta("airlock_controller_owned") and get_parent():
		source = get_parent()
	if not source.has_meta("airlock_controller_owned") or not bool(source.get_meta("airlock_controller_owned")):
		return false
	if not source.has_meta("airlock_controller_owner_path"):
		return false
	var owner_path = source.get_meta("airlock_controller_owner_path")
	var owner: Node = null
	if owner_path is NodePath:
		owner = get_node_or_null(owner_path)
	if not is_instance_valid(owner):
		return false
	var door_name := String(source.get_meta("airlock_door_name") if source.has_meta("airlock_door_name") else "")
	if owner.has_method("request_door_interaction"):
		owner.request_door_interaction(door_name)
		return true
	return false

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
	if group == "interactable":
		return get_is_interactable() and .is_in_group(group)
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

func get_is_interactable() -> bool:
	var p = get_parent()
	if p and "is_interactable" in p: return p.is_interactable
	return is_interactable

func set_is_interactable(val: bool):
	var p = get_parent()
	if p and "is_interactable" in p: p.is_interactable = val
	is_interactable = val
	if is_interactable:
		if not .is_in_group("interactable"):
			add_to_group("interactable")
	else:
		if .is_in_group("interactable"):
			remove_from_group("interactable")

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

func get_interaction_title() -> String:
	var p = get_parent()
	if p and "interaction_title" in p: return String(p.interaction_title)
	return interaction_title

func set_interaction_title(val: String) -> void:
	interaction_title = val
	var p = get_parent()
	if p and "interaction_title" in p: p.interaction_title = val

func get_interaction_description() -> String:
	var p = get_parent()
	if p and "interaction_description" in p: return String(p.interaction_description)
	return interaction_description

func set_interaction_description(val: String) -> void:
	interaction_description = val
	var p = get_parent()
	if p and "interaction_description" in p: p.interaction_description = val

func get_interaction_verb_active() -> String:
	var p = get_parent()
	if p and "interaction_verb_active" in p: return String(p.interaction_verb_active)
	return interaction_verb_active

func set_interaction_verb_active(val: String) -> void:
	interaction_verb_active = val
	var p = get_parent()
	if p and "interaction_verb_active" in p: p.interaction_verb_active = val

func get_interaction_verb_inactive() -> String:
	var p = get_parent()
	if p and "interaction_verb_inactive" in p: return String(p.interaction_verb_inactive)
	return interaction_verb_inactive

func set_interaction_verb_inactive(val: String) -> void:
	interaction_verb_inactive = val
	var p = get_parent()
	if p and "interaction_verb_inactive" in p: p.interaction_verb_inactive = val

func get_interaction_icon() -> Texture:
	var p = get_parent()
	if p and "interaction_icon" in p: return p.interaction_icon
	return interaction_icon

func set_interaction_icon(val: Texture) -> void:
	interaction_icon = val
	var p = get_parent()
	if p and "interaction_icon" in p: p.interaction_icon = val

func get_interaction_prompt() -> String:
	var p = get_parent()
	if p and p.has_method("get_interaction_prompt"):
		return String(p.get_interaction_prompt())
	return get_interaction_text()

func screen_title() -> String:
	var title := get_interaction_title().strip_edges()
	if title != "":
		return title
	var p = get_parent()
	if p and is_instance_valid(p):
		return String(p.name).replace("_", " ")
	return String(name).replace("_", " ")
