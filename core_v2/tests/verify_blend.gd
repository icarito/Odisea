extends SceneTree

const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")

# Mock Player Class
class MockPlayer extends Node:
	var input_history = []
	
	func inject_input(data):
		# Store input with frame number
		input_history.append({
			"frame": Engine.get_frames_drawn(),
			"data": data
		})
		print("[MockPlayer] Frame ", Engine.get_frames_drawn(), " Input: ", data)

	
	# Needed for OYS_Interpreter _find_player fallback
	func _init():
		name = "Pilot"

# Test Runner Class
class TestRunner extends Node:
	var interpreter
	var player
	
	func _ready():
		print("Starting BLEND verification...")
		player = MockPlayer.new()
		get_tree().root.add_child(player)
		
		interpreter = OYS_Interpreter.new(get_tree().root)
		
		var script = """
		BLEND 0.1
			FW 0.1
			LOOK 45
		END
		"""
		
		interpreter.parse(script)
		
		# Run interpreter
		var state = interpreter.run()
		if state is GDScriptFunctionState:
			yield (state, "completed")
		
		print("Interpreter finished.")
		verify_results()
		get_tree().quit()

	func verify_results():
		var history = player.input_history
		print("Input history size: ", history.size())
		
		var has_move = false
		var has_look = false
		var parallel_frames = 0
		
		# We expect multiple frames where BOTH move and look inputs occurred
		# Since inject_input is called separately for each, we check if we have distinct calls in same frame
		var frame_inputs = {}
		
		for entry in history:
			var f = entry.frame
			if not frame_inputs.has(f):
				frame_inputs[f] = []
			frame_inputs[f].append(entry.data)
			
		for f in frame_inputs:
			var inputs = frame_inputs[f]
			var frame_has_move = false
			var frame_has_look = false
			
			for data in inputs:
				if data.has("move_vec") and data.move_vec[1] != 0:
					frame_has_move = true
				if data.has("mouse_delta") and data.mouse_delta[1] != 0:
					frame_has_look = true
			
			if frame_has_move and frame_has_look:
				parallel_frames += 1
		
		# Prevent unused variable warning
		var _unused = [has_move, has_look]
		
		print("Parallel frames detected: ", parallel_frames)
		
		if parallel_frames > 0:
			print("SUCCESS: BLEND command executed Move and Look in parallel.")
		else:
			print("FAILURE: Did not detect parallel execution.")
			for f in frame_inputs:
				print("Frame ", f, ": ", frame_inputs[f])

func _init():
	var runner = TestRunner.new()
	root.add_child(runner)
