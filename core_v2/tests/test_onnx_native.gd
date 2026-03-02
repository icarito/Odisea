extends SceneTree

const ANNA_SCENE_PATH := "res://core_v2/tests/TestScene_ANNA.tscn"

func _init():
	print("[ONNX_TEST] Starting test")
	var scene_res = load(ANNA_SCENE_PATH)
	var scene = scene_res.instance()
	root.add_child(scene)
	
	# Wait a bit
	yield (self.create_timer(1.0), "timeout")
	
	var anna = scene.get_node_or_null("AnnaInterface")
	if not anna:
		anna = preload("res://core_v2/anna/AnnaInterface.gd").new()
		scene.add_child(anna)
		
	var bridge = get_root().find_node("AnnaBridge", true, false)
	if bridge:
		print("[ONNX_TEST] AnnaBridge discovered")
		# We force it offline
		bridge._peers.clear()
		bridge._rl_exit_on_disconnect = false
		bridge.is_rl_mode = true
		
		# Allow it to run for some Physics frames
		for i in range(120):
			bridge._physics_process(1.0 / 60.0)
			
		if bridge._onnx_model:
			print("[ONNX_TEST] SUCCESS! ONNX Model is loaded and running natively.")
		else:
			print("[ONNX_TEST] FAILED: ONNX model null")
			quit(1)
	else:
		print("[ONNX_TEST] FAILED: Bridge not found")
		quit(1)
