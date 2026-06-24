extends Spatial

# MultiToolV2.gd
# Main controller for the Multi-Tool.

enum Mode {
	LASER,
	GLOO
}

export(Mode) var current_mode := Mode.LASER
export(int, 1, 64) var max_gloo_projectiles := 18
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

onready var _laser: Spatial = $Laser
onready var _gloo_spawn_point: Position3D = $GlooSpawnPoint
onready var _model: MeshInstance = $Model
onready var _ui: Control = $HUD/UIIndicator

const GlooProjectileScene = preload("res://core_v2/player/MultiToolGloo.tscn")

func _ready():
	_apply_exported_settings()
	_update_mode_visuals()
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

	# Clean up any freed projectiles from our list
	var i = 0
	while i < _active_gloo_projectiles.size():
		if not is_instance_valid(_active_gloo_projectiles[i]):
			_active_gloo_projectiles.remove(i)
		else:
			i += 1
	
	if _ui and _ui.has_method("update_info"):
		_ui.update_info(current_mode, _active_gloo_projectiles.size(), max_gloo_projectiles)

func _switch_mode(dir: int):
	var mode_count = Mode.size()
	current_mode = (current_mode + dir + mode_count) % mode_count
	
	# Stop firing current weapon if switching
	if _is_firing_primary:
		_handle_laser_input(false)
	
	_update_mode_visuals()

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
		projectile.configure(gloo_projectile_speed, gloo_projectile_gravity, gloo_projectile_lifetime, gloo_launch_radius, gloo_blob_radius, gloo_cure_time, gloo_collision_radius, gloo_surface_offset, gloo_collision_mask, gloo_attached_static_mask, gloo_wake_impulse, gloo_color, gloo_cured_color, gloo_emission_color, gloo_emission_energy, gloo_laser_heat_time, gloo_laser_cool_rate, gloo_smoke_scale, gloo_explosion_scale, gloo_joint_bias, gloo_joint_damping, gloo_joint_impulse_clamp)
	projectile.launch(_gloo_spawn_point.global_transform)
	_gloo_cooldown_left = gloo_fire_cooldown
	
	_active_gloo_projectiles.append(projectile)
	
	if _active_gloo_projectiles.size() > max_gloo_projectiles:
		var oldest = _active_gloo_projectiles.pop_front()
		if is_instance_valid(oldest):
			oldest.fade_out()

func get_snapshot() -> Dictionary:
	var proj_paths = []
	for p in _active_gloo_projectiles:
		if is_instance_valid(p):
			proj_paths.append(str(p.get_path()))
	
	return {
		"mode": current_mode,
		"projectiles": proj_paths
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
