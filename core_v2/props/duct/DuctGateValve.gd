extends "res://core_v2/components/InteractableBaseV2.gd"

# DuctGateValve.gd - Specialized gate that closes on player proximity

signal gate_state_changed(is_open)

onready var anim_player = $AnimationPlayer
onready var proximity_area = $ProximityArea
onready var static_body = $Frame/GateMesh/StaticBody

func _ready():
	# Ensure the gate starts open
	set_active(true, true)
	if proximity_area:
		var err = proximity_area.connect("body_entered", self, "_on_body_entered")
		if err != OK:
			print("[DuctGateValve] Error connecting proximity trigger: ", err)

	if anim_player:
		var err = anim_player.connect("animation_finished", self, "_on_animation_finished")
		if err != OK:
			print("[DuctGateValve] Error connecting animation_finished: ", err)

func _on_body_entered(body):
	# Detection for player (Layer 2 usually)
	if body.name.begins_with("Player") or body.is_in_group("player"):
		if is_active:
			_close_gate()

func _close_gate():
	# Close the gate permanently
	set_active(false)
	is_used = true
	emit_signal("gate_state_changed", false)

func _update_visuals():
	if anim_player:
		if not is_active and anim_player.current_animation != "Close":
			anim_player.play("Close")

func _on_animation_finished(_anim_name: String):
	# Logic once the gate is fully closed
	_on_animation_completed()

func _on_animation_completed():
	._on_animation_completed()
	# The collision is enabled by the animation track 'disabled: false' at end
