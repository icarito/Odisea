extends SceneTree

# Captura Dome_Prologue con una camera apuntando al walking_cargo_transporter_rig.
# Uso: godot3-bin --path . -s tools/capture_wct_level.gd -- <nombre_salida>

var _frames := 0
var _out_name := "wct_level"
var _cam_pos := Vector3(2.6, 1.7, 1.4)
var _cam_target_off := Vector3(0, 1.5, 0)

func _init() -> void:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--" and i + 1 < args.size():
			_out_name = args[i + 1]
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
	set_meta("target", target)
	set_meta("cam", cam.translation)
	print("[CaptureWCT] cam=%s target=%s" % [cam.translation, target])

func _idle(_delta: float) -> bool:
	_frames += 1
	if _frames == 40:
		var img: Image = root.get_texture().get_data()
		img.flip_y()
		img.save_png("/tmp/kilo/diag_spike/%s.png" % _out_name)
		print("[CaptureWCT] guardado /tmp/kilo/diag_spike/%s.png (frames=%d)" % [_out_name, _frames])
		return true
	return false
