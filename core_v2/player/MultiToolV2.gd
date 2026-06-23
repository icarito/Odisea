extends Spatial

# MultiToolV2.gd
# Main controller for the Multi-Tool.

enum Mode {
	LASER,
	GLOO
}

export(Mode) var current_mode := Mode.LASER
export(int) var max_gloo_projectiles := 6

var _active_gloo_projectiles := []
var _is_firing_primary := false

onready var _laser: Spatial = $Laser
onready var _gloo_spawn_point: Position3D = $GlooSpawnPoint
onready var _model: MeshInstance = $Model
onready var _ui: Control = $HUD/UIIndicator

const GlooProjectileScene = preload("res://core_v2/player/MultiToolGloo.tscn")

func _ready():
	_update_mode_visuals()
	_laser.set_firing(false)
	add_to_group("replay_sync")

func step(dt: float, input):
	if input == null:
		return

	# Mode switching
	if input.tool_next_mode:
		_switch_mode(1)
	elif input.tool_prev_mode:
		_switch_mode(-1)

	# Firing logic
	match current_mode:
		Mode.LASER:
			_handle_laser_input(input.tool_fire_primary)

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

func _handle_laser_input(is_firing: bool):
	if _is_firing_primary == is_firing:
		return
	
	_is_firing_primary = is_firing
	if _laser:
		_laser.set_firing(is_firing)

# Called by PlayerController when secondary fire is JUST pressed
func fire_gloo():
	if current_mode != Mode.GLOO:
		return
		
	var projectile = GlooProjectileScene.instance()
	get_tree().root.add_child(projectile)
	projectile.launch(_gloo_spawn_point.global_transform)
	
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
