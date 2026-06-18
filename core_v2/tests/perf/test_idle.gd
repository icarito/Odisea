extends SceneTree

var _count := 0
var _start := 0.0
var _fps := []
var _target := ""
var _cap := 3.0
var _warm := 2.0

func _init():
	var a = OS.get_cmdline_args()
	_target = a[2] if a.size() > 2 else "res://core_v2/levels/TestScene_v2.tscn"
	_cap = float(a[3]) if a.size() > 3 else 3.0
	print("TARGET=", _target, " CAP=", _cap)

func _idle(_delta):
	_count += 1
	if _count == 1:
		change_scene(_target)
		print("OK: queued scene change")
	elif _count < 10:
		var cs = get_current_scene()
		print("IDLE #", _count, " current_scene=", cs.filename if cs else "null")
	elif _count == 10:
		print("DONE")
		quit(0)
	else:
		print("EXTRA IDLE")
		quit(0)
