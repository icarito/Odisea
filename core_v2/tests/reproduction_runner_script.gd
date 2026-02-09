extends SceneTree

const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")

func _init():
	print("Starting BLEND reproduction test...")
	var root = Node.new()
	root.name = "Root"
	get_root().add_child(root)
	
	# Mock Player
	var player = Node.new()
	player.name = "Pilot"
	player.set_script(preload("res://core_v2/tests/MockPlayer.gd"))
	root.add_child(player)
	
	# Interpreter
	var interpreter = OYS_Interpreter.new(root)
	
	var file = File.new()
	if file.open("res://core_v2/tests/reproduction_blend.oys", File.READ) != OK:
		print("Error opening script file")
		quit()
		return
		
	var content = file.get_as_text()
	file.close()
	
	interpreter.parse(content)
	
	# Run
	# Since run() yields, we need to handle it.
	# But we are in _init of SceneTree... 
	# We should do this in a node in the tree.
	
	var runner = Node.new()
	runner.set_script(preload("res://core_v2/tests/TestRunner.gd"))
	runner.interpreter = interpreter
	root.add_child(runner)
	
	print("Test runner initialized.")
