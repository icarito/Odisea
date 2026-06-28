extends "res://core_v2/actors/AgentBase.gd"

class_name CargolDroneV2

# Cargol Drone V2 - Specialized Companion Agent
# Inherits from AgentBase for core movement and state logic.

# --- EXPORTED CONFIGURATION ---
export(float) var max_lift_capacity := 500.0 # Mass limit for cargo
export(float) var player_far_threshold := 15.0

# --- SIGNALS ---
signal player_too_far

# --- STATE VARIABLES (Snapshotted) ---
var cargo_uid := "" # Path of attached cargo (original path)

# Internal refs
var _attached_node: Spatial = null
var _original_parent_path := ""
var _interaction_target: Node = null
var _bob_time := 0.0

# --- NODES ---
onready var cargo_anchor: Position3D = null

func _init():
	# AgentBase already adds to replay_sync and agent
	add_to_group("cargol_drone")

func _ready():
	# CargoAnchor setup (retained from original CargolDroneV2)
	var parent_node = get_parent()
	
	if has_node("CargoAnchor"):
		cargo_anchor = get_node("CargoAnchor")
	else:
		cargo_anchor = Position3D.new()
		cargo_anchor.name = "CargoAnchor"
		add_child(cargo_anchor)

	if parent_node:
		call_deferred("_reparent_cargo_anchor", parent_node)

	# Register as OYS Actor (legacy support)
	var sm = get_node_or_null("/root/SessionManager")
	if sm:
		if sm.has_method("register_oys_actor"):
			sm.register_oys_actor("CargolDrone", self)
		if sm.has_signal("oys_registry_reset"):
			sm.connect("oys_registry_reset", self, "_on_oys_registry_reset")

	_update_visuals()

func _reparent_cargo_anchor(parent_node: Node) -> void:
	if not is_instance_valid(cargo_anchor) or not is_instance_valid(parent_node):
		return
	if cargo_anchor.get_parent() == parent_node:
		return
	if cargo_anchor.get_parent():
		cargo_anchor.get_parent().remove_child(cargo_anchor)
	parent_node.add_child(cargo_anchor)

# --- OVERRIDES ---

func _on_state_changed(new_state):
	match new_state:
		State.IDLE, State.FOLLOW_TARGET, State.MOVE_TO:
			_update_led(Color(0.2, 0.4, 1.0)) # Blue
			_set_status_light_intensity(0.8)
		State.FOLLOW_PATH, State.RETURN_HOME:
			_update_led(Color(0.2, 1.0, 0.4)) # Green
			_set_status_light_intensity(1.5)
		State.ALERT, State.SEARCH:
			_update_led(Color(1.0, 0.2, 0.2)) # Red
			_set_status_light_intensity(2.0)
	
	if new_state != State.IDLE:
		_interaction_target = null

func _set_status_light_intensity(intensity: float):
	var light = get_node_or_null("StatusLight")
	if light and light is Light:
		light.light_energy = intensity

func step(dt: float) -> void:
	.step(dt) # Call AgentBase.step
	
	# Keep anchor in sync
	if cargo_anchor and cargo_anchor.get_parent() != self:
		cargo_anchor.global_transform = global_transform
		
	# Companion specific logic: Check distance to player
	_check_player_distance()
	
	# Remote interaction check
	if _interaction_target and is_instance_valid(_interaction_target):
		if global_transform.origin.distance_to(_interaction_target.global_transform.origin) < 1.5:
			_perform_remote_interact()

	# Visual effects: Charge Field
	var charge_field = get_node_or_null("ChargeField")
	if charge_field:
		charge_field.visible = _attached_node != null

	# Visual effects: Bobbing and rotation when idle or moving slowly
	_bob_time += dt
	var mesh = get_node_or_null("MeshInstance")
	if mesh:
		var bob = sin(_bob_time * 1.5) * 0.05
		mesh.translation.y = bob
		mesh.rotate_y(dt * 0.2)

func _check_player_distance():
	if current_state == State.FOLLOW_TARGET and _follow_target and _follow_target.is_in_group("player"):
		var dist = global_transform.origin.distance_to(_follow_target.global_transform.origin)
		if dist > player_far_threshold:
			emit_signal("player_too_far")

# --- CARGOL SPECIALIZED API ---

func go_to_and_interact(pos: Vector3, target_node: Node):
	_interaction_target = target_node
	move_to(pos)

func _perform_remote_interact():
	if _interaction_target and _interaction_target.has_method("interact"):
		print("[Cargol] Interacting with: ", _interaction_target.name)
		_interaction_target.interact()
	_interaction_target = null

func pickup(target_node_path) -> void:
	var path_str = str(target_node_path)
	var target = get_node_or_null(path_str)

	if not target and get_tree().current_scene:
		target = get_tree().current_scene.find_node(path_str, true, false)

	if not target:
		var p = get_parent()
		if p:
			target = p.find_node(path_str, true, false)

	if target and target is Spatial:
		if target == self: return
		if target is RigidBody:
			if target.mass > max_lift_capacity:
				printerr("[Cargol] Cargo too heavy: ", target.mass)
				return

			var original_parent = target.get_parent()
			_original_parent_path = original_parent.get_path()
			cargo_uid = str(target.get_path())

			original_parent.remove_child(target)
			cargo_anchor.add_child(target)
			target.transform = Transform.IDENTITY

			target.mode = RigidBody.MODE_KINEMATIC
			target.collision_layer = 0
			target.collision_mask = 0
			target.linear_velocity = Vector3.ZERO
			target.angular_velocity = Vector3.ZERO
			target.sleeping = true

			_attached_node = target
			print("[Cargol] Picked up: ", target.name)
	else:
		printerr("[Cargol] Pickup failed, invalid target: ", path_str)

func release(impulse: Vector3) -> void:
	if _attached_node:
		var target = _attached_node
		cargo_anchor.remove_child(target)

		var original_parent = get_node_or_null(_original_parent_path)
		if not original_parent:
			original_parent = get_tree().current_scene

		if original_parent:
			var launch_transform = cargo_anchor.global_transform
			original_parent.add_child(target)
			target.global_transform = launch_transform

		if target is RigidBody:
			target.mode = RigidBody.MODE_RIGID
			target.collision_layer = 1
			target.collision_mask = 1
			target.sleeping = false
			target.linear_velocity = Vector3.ZERO
			target.angular_velocity = Vector3.ZERO
			target.apply_central_impulse(impulse + _canonical_velocity)

		print("[Cargol] Released: ", target.name)
		_attached_node = null
		cargo_uid = ""
		_original_parent_path = ""

func query_cargo() -> Dictionary:
	if _attached_node:
		var mass = 0.0
		if _attached_node is RigidBody:
			mass = _attached_node.mass
		return {
			"attached": true,
			"mass": mass,
			"name": _attached_node.name,
			"type": "RigidBody"
		}
	return {"attached": false}

# --- VISUAL FEEDBACK ---

func _on_oys_registry_reset() -> void:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("register_oys_actor"):
		sm.register_oys_actor("CargolDrone", self)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	var data = .get_snapshot()
	data["cargo_uid"] = cargo_uid
	data["orig_parent"] = _original_parent_path
	return data

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	cargo_uid = data.get("cargo_uid", "")
	_original_parent_path = data.get("orig_parent", "")
	
	if cargo_anchor.get_child_count() > 0:
		_attached_node = cargo_anchor.get_child(0) as Spatial
