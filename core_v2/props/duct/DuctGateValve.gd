extends "res://core_v2/components/InteractableBaseV2.gd"

# DuctGateValve.gd - Specialized gate that can be operated through the interaction system.

signal gate_state_changed(is_open)

export(bool) var close_on_proximity := false

onready var anim_player = $AnimationPlayer
onready var proximity_area = $ProximityArea
onready var static_body = $Frame/GateMesh/StaticBody
onready var gate_collision_shape = $Frame/GateMesh/StaticBody/CollisionShape

func _ready():
	._ready()
	_ensure_interaction_area()
	if proximity_area and close_on_proximity:
		var err = proximity_area.connect("body_entered", self, "_on_body_entered")
		if err != OK:
			print("[DuctGateValve] Error connecting proximity trigger: ", err)

	if anim_player:
		var err = anim_player.connect("animation_finished", self, "_on_animation_finished")
		if err != OK:
			print("[DuctGateValve] Error connecting animation_finished: ", err)

func _on_body_entered(body):
	# Detection for player (Layer 2 usually)
	if close_on_proximity and (body.name.begins_with("Player") or body.is_in_group("player")):
		if is_active:
			_close_gate()

func _close_gate():
	# Close the gate permanently
	set_active(false)
	is_used = true
	emit_signal("gate_state_changed", false)

func interact() -> void:
	var was_active := is_active
	.interact()
	if was_active != is_active:
		_play_gate_state()
		emit_signal("gate_state_changed", is_active)

func _update_visuals():
	_play_gate_state()

func _play_gate_state() -> void:
	if anim_player:
		if is_active:
			if gate_collision_shape and gate_collision_shape.disabled:
				return
			if anim_player.has_animation("Close") and (anim_player.current_animation != "Close" or not anim_player.is_playing()):
				anim_player.play_backwards("Close")
		elif gate_collision_shape and not gate_collision_shape.disabled and not anim_player.is_playing():
			return
		elif anim_player.current_animation != "Close" or not anim_player.is_playing():
			anim_player.play("Close")

func _on_animation_finished(_anim_name: String):
	# Logic once the gate is fully closed
	_on_animation_completed()

func _on_animation_completed():
	._on_animation_completed()
	# The collision is enabled by the animation track 'disabled: false' at end

func _ensure_interaction_area() -> void:
	if has_node("InteractionArea"):
		return
	var area := Area.new()
	area.name = "InteractionArea"
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	var shape := CollisionShape.new()
	var sphere := SphereShape.new()
	sphere.radius = 3.2
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
