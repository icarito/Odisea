extends SceneTree

# Captura Dome_Prologue con una camera apuntando al walking_cargo_transporter_rig.
# Uso: godot3-bin --path . -s tools/capture_wct_level.gd -- <nombre_salida>

var __capture_frame := 130
var _frames := 0
var _out_name := "wct_level"
var _cam_pos := Vector3(2.6, 1.7, 1.4)
var _cam_target_off := Vector3(0, 1.5, 0)

func _init() -> void:
	var args := OS.get_cmdline_args()
	var user_args := []
	var sep := false
	for a in args:
		if a == "--":
			sep = true
			continue
		if sep:
			user_args.append(a)
	if user_args.size() >= 1:
		_out_name = user_args[0]
	if user_args.size() >= 2:
		__capture_frame = int(user_args[1])
	var level: Node = (load("res://core_v2/levels/interiors/Dome_Prologue.tscn") as PackedScene).instance()
	root.add_child(level)
	var walker := level.find_node("walking_cargo_transporter_rig", true, false)
	if walker == null:
		printerr("walker no encontrado")
		quit(1)
		return
	var cam := Camera.new()
	cam.name = "DiagCamera"
	cam.fov = 55
	root.add_child(cam)
	cam.make_current()
	# angulo canonico: desde el lado del piloto, altura de ojos, mirando al hub
	var target: Vector3 = walker.global_transform.origin + _cam_target_off
	cam.translation = walker.global_transform.origin + _cam_pos
	cam.look_at(target, Vector3.UP)
	set_meta("walker", walker)
	set_meta("cam", cam)

func _idle(_delta: float) -> bool:
	_frames += 1
	var walker: Spatial = get_meta("walker")
	var cam: Camera = get_meta("cam")
	cam.current = true
	var target: Vector3 = walker.global_transform.origin + Vector3(0, 2.4, 0)
	cam.translation = target + Vector3(8.0, 2.2, 7.0)
	cam.look_at(target, Vector3.UP)
	if _frames == int(__capture_frame):
		var img: Image = root.get_texture().get_data()
		img.flip_y()
		img.save_png("test_output/props/%s.png" % _out_name)
		print("[CaptureWCT] guardado test_output/props/%s.png (frames=%d)" % [_out_name, _frames])
		return true
	return false
