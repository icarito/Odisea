extends GdUnitTestSuite

const PipeNetworkResourceScript := preload("res://core_v2/systems/pipe/PipeNetworkResource.gd")

func test_valid_branch_passes_validation() -> void:
	var script: Script = PipeNetworkResourceScript
	assert_object(script).is_not_null()

	var res: Resource = auto_free(Resource.new())
	res.set_script(script)
	
	var root: Node = auto_free(Node.new())
	root.name = "Root"
	
	var tank: Node = Node.new()
	tank.name = "Tank"
	root.add_child(tank)

	var v1: Node = Node.new()
	v1.name = "Valve1"
	root.add_child(v1)

	var f1: Node = Node.new()
	f1.name = "Fissure1"
	root.add_child(f1)

	var p1: Node = Node.new()
	p1.name = "Pipe1"
	root.add_child(p1)

	var p2: Node = Node.new()
	p2.name = "Pipe2"
	root.add_child(p2)

	var p3: Node = Node.new()
	p3.name = "Pipe3"
	root.add_child(p3)

	var p4: Node = Node.new()
	p4.name = "Pipe4"
	root.add_child(p4)

	res.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{
					"pipe_run": NodePath("Pipe1"),
					"valve": NodePath("Valve1"),
					"leak": NodePath(""),
					"flow_dir": Vector3(0, 0, 1)
				},
				{
					"pipe_run": NodePath("Pipe2"),
					"valve": NodePath(""),
					"leak": NodePath("Fissure1"),
					"flow_dir": Vector3(0, 0, 1)
				},
				{
					"pipe_run": NodePath("Pipe3"),
					"valve": NodePath(""),
					"leak": NodePath(""),
					"flow_dir": Vector3(1, 0, 0)
				},
				{
					"pipe_run": NodePath("Pipe4"),
					"valve": NodePath(""),
					"leak": NodePath(""),
					"flow_dir": Vector3(1, 0, 0)
				}
			]
		}
	})

	# Validation without context node
	var result_no_ctx: Dictionary = res.call("validate")
	assert_bool(bool(result_no_ctx.get("ok", false))).is_true()
	assert_array(result_no_ctx.get("errors", [])).is_empty()

	# Validation with context node
	var result_ctx: Dictionary = res.call("validate", root)
	assert_bool(bool(result_ctx.get("ok", false))).is_true()
	assert_array(result_ctx.get("errors", [])).is_empty()


func test_missing_tank_fails_validation() -> void:
	var res: Resource = auto_free(Resource.new())
	res.set_script(PipeNetworkResourceScript)
	res.set("branches", {
		"west": {
			"tank": NodePath(""),
			"segments": [
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var result: Dictionary = res.call("validate")
	assert_bool(bool(result.get("ok", true))).is_false()
	var errors: Array = result.get("errors", [])
	assert_bool(errors.size() > 0).is_true()


func test_empty_segments_fails_validation() -> void:
	var res: Resource = auto_free(Resource.new())
	res.set_script(PipeNetworkResourceScript)
	res.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": []
		}
	} )

	var result: Dictionary = res.call("validate")
	assert_bool(bool(result.get("ok", true))).is_false()
	var errors: Array = result.get("errors", [])
	assert_bool(errors.size() > 0).is_true()


func test_duplicate_pipe_run_fails_validation() -> void:
	var res: Resource = auto_free(Resource.new())
	res.set_script(PipeNetworkResourceScript)
	res.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD},
				{"pipe_run": NodePath("Pipe1"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var result: Dictionary = res.call("validate")
	assert_bool(bool(result.get("ok", true))).is_false()
	var errors: Array = result.get("errors", [])
	assert_bool(errors.size() > 0).is_true()


func test_unresolvable_nodepath_fails_validation() -> void:
	var res: Resource = auto_free(Resource.new())
	res.set_script(PipeNetworkResourceScript)
	var root: Node = auto_free(Node.new())
	root.name = "Root"

	var tank: Node = Node.new()
	tank.name = "Tank"
	root.add_child(tank)

	res.set("branches", {
		"west": {
			"tank": NodePath("Tank"),
			"segments": [
				{"pipe_run": NodePath("NonExistentPipe"), "valve": NodePath(""), "leak": NodePath(""), "flow_dir": Vector3.FORWARD}
			]
		}
	})

	var result: Dictionary = res.call("validate", root)
	assert_bool(bool(result.get("ok", true))).is_false()
	var errors: Array = result.get("errors", [])
	assert_bool(errors.size() > 0).is_true()
