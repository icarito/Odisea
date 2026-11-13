extends Spatial

# MultiToolV2.gd
# Main controller for the Multi-Tool.

signal tool_state_changed()

enum Mode {
	LASER,
	GLOO,
	GRAB
}

export(Mode) var current_mode := Mode.LASER
export(int, 1, 64) var max_gloo_projectiles := 18
export(float, 1.0, 25.0) var grab_max_range := 8.5
export(float, 1.2, 12.0) var grab_min_distance := 1.8
export(float, 1.0, 5000.0) var grab_max_mass := 1600.0
export(float, 1.0, 120.0) var grab_spring_gain := 14.0
export(float, 1.0, 60.0) var grab_max_speed := 16.0
export(float, 0.1, 30.0) var grab_angular_damping := 10.0
export(float, 0.0, 5.0) var gloo_fire_cooldown := 0.18
export(float, 1.0, 80.0) var gloo_projectile_speed := 18.0
export(float, 0.0, 30.0) var gloo_projectile_gravity := 7.5
export(float, 1.0, 600.0) var gloo_projectile_lifetime := 240.0
export(float, 0.03, 1.0) var gloo_launch_radius := 0.09
export(float, 0.05, 1.5) var gloo_blob_radius := 0.35
export(float, 0.05, 5.0) var gloo_cure_time := 0.65
export(float, 0.05, 1.5) var gloo_collision_radius := 0.32
export(float, 0.0, 2.0) var gloo_surface_offset := 0.08
export(int) var gloo_collision_mask := 253 # All gameplay layers except player layer 2.
export(int) var gloo_attached_static_mask := 1
export(float, 0.0, 20.0) var gloo_wake_impulse := 0.0
export(Color) var gloo_color := Color(0.18, 0.88, 0.78, 1.0)
export(Color) var gloo_cured_color := Color(0.46, 0.58, 0.52, 1.0)
export(Color) var gloo_emission_color := Color(0.08, 0.55, 0.48, 1.0)
export(float, 0.0, 3.0) var gloo_emission_energy := 0.45
export(float, 0.2, 8.0) var gloo_laser_heat_time := 1.25
export(float, 0.1, 8.0) var gloo_laser_cool_rate := 1.8
export(float, 0.2, 6.0) var gloo_smoke_scale := 2.0
export(float, 0.2, 6.0) var gloo_explosion_scale := 1.2
export(float, 0.5, 5.0) var gloo_fx_lifetime_scale := 1.8
export(float, 0.0, 2.0) var gloo_fx_camera_offset := 0.35
export(float, 0.0, 3.0) var gloo_laser_heat_spread_radius := 0.75
export(float, 0.0, 2.0) var gloo_merge_distance := 0.28
export(float, 0.0, 2.0) var gloo_merge_radius_gain := 0.45
export(float, 0.0, 1.0) var gloo_joint_bias := 0.15
export(float, 0.0, 4.0) var gloo_joint_damping := 0.9
export(float, 0.0, 20.0) var gloo_joint_impulse_clamp := 1.2
export(float, 1.0, 200.0) var laser_max_range := 50.0
export(int) var laser_collision_mask := 765 # Everything except player layer 2, plus gloo laser hit areas.
export(Color) var laser_color := Color(1.0, 0.3, 0.1)
export(float, 0.05, 2.0) var laser_alpha := 0.6
export(float, 0.0, 8.0) var laser_emission_energy := 2.0

var _active_gloo_projectiles := []
var _is_firing_primary := false
var _gloo_cooldown_left := 0.0
var _grabbed_body: RigidBody = null
var _grab_distance := 2.8

onready var _laser: Spatial = $Laser
onready var _gloo_spawn_point: Position3D = $GlooSpawnPoint
onready var _model: MeshInstance = $Model
onready var _ui: Control = $HUD/UIIndicator

const GlooProjectileScene = preload("res://core_v2/player/MultiToolGloo.tscn")

func _ready():
	_apply_exported_settings()
	_update_mode_visuals()
	if _laser:
		_laser.set_firing(false)
	add_to_group("replay_sync")

func step(dt: float, input):
	if input == null:
		return
	if _gloo_cooldown_left > 0.0:
		_gloo_cooldown_left = max(0.0, _gloo_cooldown_left - dt)

	# Mode switching
	if input.tool_next_mode:
		_switch_mode(1)
	elif input.tool_prev_mode:
		_switch_mode(-1)

	# Firing logic
	match current_mode:
		Mode.LASER:
			_handle_laser_input(input.tool_fire_primary)
		Mode.GLOO:
			if input.tool_fire_primary:
				_fire_gloo()
		Mode.GRAB:
			_step_grab(dt, input.tool_fire_primary)

	# Clean up any freed projectiles from our list
	var prev_count: int = _active_gloo_projectiles.size()
	var i = 0
	while i < _active_gloo_projectiles.size():
		if not is_instance_valid(_active_gloo_projectiles[i]):
			_active_gloo_projectiles.remove(i)
		else:
			i += 1
	
	if _active_gloo_projectiles.size() != prev_count:
		emit_signal("tool_state_changed")

	if _ui and _ui.has_method("update_info"):
		_ui.update_info(current_mode, _active_gloo_projectiles.size(), max_gloo_projectiles)

func _switch_mode(dir: int):
	var mode_count = Mode.size()
	current_mode = (current_mode + dir + mode_count) % mode_count
	
	# Stop firing current weapon if switching
	if _is_firing_primary:
		_handle_laser_input(false)
	if _grabbed_body != null:
		release_grab()
	
	_update_mode_visuals()
	emit_signal("tool_state_changed")

func _update_mode_visuals():
	if not _model: return
	
	var mat = _model.get_surface_material(0)
	if not mat:
		mat = SpatialMaterial.new()
		_model.set_surface_material(0, mat)
	
	match current_mode:
		Mode.LASER:
			mat.albedo_color = Color.red
		Mode.GLOO:
			mat.albedo_color = Color.cyan
		Mode.GRAB:
			mat.albedo_color = Color(1.0, 0.72, 0.15)

func _apply_exported_settings() -> void:
	if _laser and _laser.has_method("configure"):
		_laser.configure(laser_max_range, laser_collision_mask, laser_color, laser_alpha, laser_emission_energy)

func _handle_laser_input(is_firing: bool):
	if _is_firing_primary == is_firing:
		return
	
	_is_firing_primary = is_firing
	if _laser:
		_laser.set_firing(is_firing)

func fire_gloo() -> void:
	_fire_gloo()

func _fire_gloo():
	if current_mode != Mode.GLOO:
		return
	if _gloo_cooldown_left > 0.0:
		return
		
	var projectile = GlooProjectileScene.instance()
	get_tree().root.add_child(projectile)
	if projectile.has_method("configure"):
		projectile.configure(gloo_projectile_speed, gloo_projectile_gravity, gloo_projectile_lifetime, gloo_launch_radius, gloo_blob_radius, gloo_cure_time, gloo_collision_radius, gloo_surface_offset, gloo_collision_mask, gloo_attached_static_mask, gloo_wake_impulse, gloo_color, gloo_cured_color, gloo_emission_color, gloo_emission_energy, gloo_laser_heat_time, gloo_laser_cool_rate, gloo_smoke_scale, gloo_explosion_scale, gloo_fx_lifetime_scale, gloo_fx_camera_offset, gloo_laser_heat_spread_radius, gloo_merge_distance, gloo_merge_radius_gain, gloo_joint_bias, gloo_joint_damping, gloo_joint_impulse_clamp)
	projectile.launch(_gloo_spawn_point.global_transform)
	_gloo_cooldown_left = gloo_fire_cooldown
	
	_active_gloo_projectiles.append(projectile)
	
	if _active_gloo_projectiles.size() > max_gloo_projectiles:
		var oldest = _active_gloo_projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.fade_out()

	emit_signal("tool_state_changed")

func _step_grab(dt: float, is_holding: bool) -> void:
	if not is_holding:
		if _grabbed_body != null:
			release_grab()
		return
	if _grabbed_body == null or not is_instance_valid(_grabbed_body) or _grabbed_body.mode != RigidBody.MODE_RIGID:
		_grabbed_body = null
		var candidate := _find_grab_candidate()
		if candidate != null:
			grab_body(candidate)
	if _grabbed_body == null or not is_instance_valid(_grabbed_body):
		return
	if _is_player_standing_on(_grabbed_body):
		release_grab()
		return
	var origin: Vector3 = global_transform.origin
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var target_pos: Vector3 = origin + forward * _grab_distance
	var to_target: Vector3 = target_pos - _grabbed_body.global_transform.origin
	var desired_vel: Vector3 = to_target * grab_spring_gain
	if desired_vel.length() > grab_max_speed:
		desired_vel = desired_vel.normalized() * grab_max_speed
	_grabbed_body.linear_velocity = desired_vel
	_grabbed_body.angular_velocity = _grabbed_body.angular_velocity.move_toward(Vector3.ZERO, grab_angular_damping * dt)
	_grabbed_body.sleeping = false

func _find_grab_candidate() -> RigidBody:
	if not is_inside_tree():
		return null
	var origin: Vector3 = global_transform.origin
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var space_state := get_world().direct_space_state
	var exclude := []
	var player := _find_owner_player()
	if player != null:
		exclude.append(player)
	var hit := space_state.intersect_ray(origin, origin + forward * grab_max_range, exclude, gloo_collision_mask)
	if hit and hit.get("collider", null) is RigidBody:
		var rb := hit["collider"] as RigidBody
		if _can_grab_body(rb):
			return rb
	return null

func _can_grab_body(rb: RigidBody) -> bool:
	if rb == null or not is_instance_valid(rb):
		return false
	if rb.mode != RigidBody.MODE_RIGID:
		return false
	if rb.mass > grab_max_mass:
		return false
	if _is_player_standing_on(rb):
		return false
	return true

func _find_owner_player() -> Node:
	var n: Node = get_parent()
	for _i in range(6):
		if n == null:
			return null
		if n.is_in_group("player"):
			return n
		n = n.get_parent()
	return null

func _is_player_standing_on(rb: RigidBody) -> bool:
	var player := _find_owner_player()
	if player != null and "_platform_collider" in player and player._platform_collider == rb:
		return true
	return false

func grab_body(rb: RigidBody, hold_distance: float = -1.0) -> bool:
	if not _can_grab_body(rb):
		return false
	_grabbed_body = rb
	if hold_distance > 0.0:
		_grab_distance = clamp(hold_distance, grab_min_distance, grab_max_range)
	else:
		var d: float = global_transform.origin.distance_to(rb.global_transform.origin)
		_grab_distance = clamp(d, grab_min_distance, grab_max_range)
	_grabbed_body.sleeping = false
	emit_signal("tool_state_changed")
	return true

func release_grab() -> void:
	if _grabbed_body != null and is_instance_valid(_grabbed_body):
		_grabbed_body.sleeping = false
	_grabbed_body = null
	emit_signal("tool_state_changed")

func get_grabbed_body() -> RigidBody:
	if _grabbed_body != null and is_instance_valid(_grabbed_body):
		return _grabbed_body
	return null

# --- PUBLIC QUERY API FOR SUITOS / MULTITOOL SCREEN ---
# Note: MultiToolV2 currently has no real thermal heat simulation (only export configs
# in MultiToolLaser). Heat is intentionally excluded from state readouts.

func get_mode_name() -> String:
	match current_mode:
		Mode.LASER: return "LASER"
		Mode.GLOO: return "GLOO"
		Mode.GRAB: return "GRAB"
	return "LASER"

func get_charge_info() -> Dictionary:
	var active_count := 0
	for p in _active_gloo_projectiles:
		if is_instance_valid(p):
			active_count += 1
	return {
		"active": active_count,
		"max": max_gloo_projectiles,
		"grabbing": _grabbed_body != null and is_instance_valid(_grabbed_body)
	}

func get_snapshot() -> Dictionary:
	var proj_paths = []
	for p in _active_gloo_projectiles:
		if is_instance_valid(p):
			proj_paths.append(str(p.get_path()))
	var grabbed_path := ""
	if _grabbed_body != null and is_instance_valid(_grabbed_body) and _grabbed_body.is_inside_tree():
		grabbed_path = str(_grabbed_body.get_path())
	
	return {
		"mode": current_mode,
		"projectiles": proj_paths,
		"grabbed": grabbed_path,
		"grab_dist": _grab_distance
	}

func restore_snapshot(data: Dictionary):
	if data.has("mode"):
		current_mode = int(data["mode"])
		_update_mode_visuals()
	
	if data.has("projectiles"):
		_active_gloo_projectiles.clear()
		for path in data["projectiles"]:
			var p = get_node_or_null(path)
			if is_instance_valid(p):
				_active_gloo_projectiles.append(p)
	_grabbed_body = null
	if data.has("grabbed") and String(data["grabbed"]) != "":
		var g = get_node_or_null(String(data["grabbed"]))
		if is_instance_valid(g) and g is RigidBody:
			_grabbed_body = g as RigidBody
	if data.has("grab_dist"):
		_grab_distance = float(data["grab_dist"])
