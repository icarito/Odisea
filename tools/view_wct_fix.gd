extends SceneTree

# Captura el rig nuevo: pose de reposo con pivotes marcados y 4 frames de
# marcha. Instancia bajo padre escalado 0.01 como en el nivel.

var _frames := 0
var _shot := 0
var _cam: Camera
var _vp: Viewport
var _rig: Node
var _shots := [
	{"name": "f0", "wait": 8, "size": 8.0},
	{"name": "f1", "wait": 23, "size": 8.0},
	{"name": "f2", "wait": 38, "size": 8.0},
	{"name": "f3", "wait": 53, "size": 8.0},
	{"name": "f4", "wait": 68, "size": 8.0},
	{"name": "f5", "wait": 83, "size": 8.0},
	{"name": "f6", "wait": 98, "size": 8.0},
	{"name": "f7", "wait": 113, "size": 8.0},
]

func _init() -> void:
	var holder := Spatial.new()
	holder.scale = Vector3(0.01, 0.01, 0.01)
	get_root().add_child(holder)
	var rig: Node = (load("res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn") as PackedScene).instance()
	holder.add_child(rig)
	_rig = rig

	_vp = Viewport.new()
	_vp.size = Vector2(1280, 1280)
	_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(_vp)
	_cam = Camera.new()
	_vp.add_child(_cam)
	_cam.current = true
	_cam.far = 100.0
	_cam.projection = Camera.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.ambient_light_energy = 1.0
	_cam.environment = env
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	_vp.add_child(sun)

func _idle(_delta: float) -> bool:
	_frames += 1
	if _frames < 41:
		return false
	if _shot >= _shots.size():
		quit(0)
		return true
	var s: Dictionary = _shots[_shot]
	if _frames >= 40 + int(s.wait) and _frames % 5 == 0:
		# centro visual real del rig (el origen del nodo no coincide con el mesh)
		var aabb := _visual_aabb(_rig)
		var target: Vector3 = aabb.position + aabb.size * 0.5
		_cam.size = s.size
		# camara lateral: desde +X, la pierna plana en (y,z)
		_cam.look_at_from_position(target + Vector3(6.0, 0.0, 0.0), target, Vector3(0, 1, 0))
		var img: Image = _vp.get_texture().get_data()
		img.flip_y()
		var nm: String = "wct_fix_%s" % s.name
		img.save_png("test_output/props/%s.png" % nm)
		print("[Fix] %s.png t=%.2f" % [nm, float(_rig._time)])
		_shot += 1
	return false

func _visual_aabb(root: Node) -> AABB:
	var lo := Vector3(1e18, 1e18, 1e18)
	var hi := -lo
	var stack := [root]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance:
			var ab: AABB = n.get_aabb()
			var c: Vector3 = n.global_transform.xform(ab.position + ab.size * 0.5)
			var r: float = ab.size.length() * 0.5
			lo = Vector3(min(lo.x, c.x - r), min(lo.y, c.y - r), min(lo.z, c.z - r))
			hi = Vector3(max(hi.x, c.x + r), max(hi.y, c.y + r), max(hi.z, c.z + r))
		for c2 in n.get_children():
			stack.push_back(c2)
	return AABB(lo, hi - lo)
