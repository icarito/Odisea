extends InteractableBaseV2
class_name LeverV2

# LeverV2.gd - Vertical lever prop
# Emits lever_toggled(is_on) and supports resistance.

# --- EXPORTS ---
export(bool) var lever_on := false setget set_lever_on
export(float) var lever_speed := 2.0
export(float) var resistance := 0.0 # Future use for holding interaction

# --- SIGNALS ---
signal lever_toggled(is_on)

func set_lever_on(v: bool) -> void:
	lever_on = v
	set_active(v)

func _ready():
	# Sync initial state
	if lever_on != is_active:
		set_active(lever_on, true)

	anim_duration = 1.0 / lever_speed if lever_speed > 0 else 1.0
	_update_visuals()

func _update_visuals() -> void:
	var handle = get_node_or_null("Handle")
	if handle:
		# Down (is_active=false, progress=0) -> 0 degrees
		# Up (is_active=true, progress=1) -> -90 degrees
		var rotation_x = -90.0 * anim_progress
		handle.rotation_degrees.x = rotation_x

func _on_animation_completed() -> void:
	._on_animation_completed()
	lever_on = is_active
	emit_signal("lever_toggled", is_active)

func interact() -> void:
	.interact()
	# Sound or other feedback could go here
