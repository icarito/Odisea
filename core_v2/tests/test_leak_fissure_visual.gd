extends GdUnitTestSuite

# test_leak_fissure_visual.gd - Unit tests for LeakFissureVisual component (FD-268)

const LEAK_SCENE := "res://core_v2/systems/cryo/CoolantLeak.gd"
const PATCH_SCENE := "res://core_v2/systems/cryo/LeakPatchPoint.gd"
const PIPE_RUN_SCENE := "res://core_v2/props/pipe/PipeCoolantRun.gd"
const VISUAL_SCENE := "res://core_v2/systems/cryo/LeakFissureVisual.tscn"

var _runner: GdUnitSceneRunner
var _root: Spatial
var _leak: Node
var _patch_point: Node
var _pipe_run: Node
var _visual: Spatial


func before_test() -> void:
	_root = Spatial.new()

	var leak_script = load(LEAK_SCENE)
	_leak = leak_script.new()
	_leak.name = "CoolantLeak"
	_root.add_child(_leak)

	var patch_script = load(PATCH_SCENE)
	_patch_point = patch_script.new()
	_patch_point.name = "LeakPatchPoint"
	_root.add_child(_patch_point)

	var pipe_run_script = load(PIPE_RUN_SCENE)
	_pipe_run = pipe_run_script.new()
	_pipe_run.name = "PipeCoolantRun"
	_root.add_child(_pipe_run)

	var visual_tscn = load(VISUAL_SCENE)
	_visual = visual_tscn.instance()
	_visual.name = "LeakFissureVisual"
	_root.add_child(_visual)

	_visual.set("leak_path", _visual.get_path_to(_leak))
	_visual.set("patch_point_path", _visual.get_path_to(_patch_point))
	_visual.set("pipe_run_path", _visual.get_path_to(_pipe_run))

	_runner = scene_runner(_root)


func after_test() -> void:
	if is_instance_valid(_root):
		_root.free()


func test_no_leak_fissure_inactive() -> void:
	# Healthy state: fissure intensity 0 and particles inactive
	assert_int(_leak.get("state") if "state" in _leak else _leak.call("get_state")).is_equal(0) # State.HEALTHY = 0
	assert_float(_leak.call("get_leak_intensity")).is_equal(0.0)

	yield(_runner.simulate_frames(5), "completed")

	var spray: CPUParticles = _visual.get_node("SprayParticles")
	var mist: CPUParticles = _visual.get_node("MistParticles")
	var gloo: MeshInstance = _visual.get_node("GlooMesh")

	assert_bool(spray.emitting).is_false()
	assert_bool(mist.emitting).is_false()
	assert_bool(gloo.visible).is_false()

	var mat = _pipe_run.get("_material")
	if mat != null:
		var intensity = mat.get_shader_param("fissure_intensity")
		assert_float(intensity).is_equal(0.0)


func test_active_leak_fissure_visuals() -> void:
	# Trigger leak: test WARNING vs LEAKING
	_leak.set("warning_duration", 0.1)
	_leak.set("ramp_up_duration", 0.1)
	_leak.call("trigger_leak")

	assert_int(_leak.call("get_state")).is_equal(1) # State.WARNING = 1
	yield(_runner.simulate_frames(2), "completed")

	var spray: CPUParticles = _visual.get_node("SprayParticles")
	var mist: CPUParticles = _visual.get_node("MistParticles")

	# WARNING state: mist active, spray inactive
	assert_bool(spray.emitting).is_false()
	assert_bool(mist.emitting).is_true()

	var mat = _pipe_run.get("_material")
	if mat != null:
		var warning_intensity = mat.get_shader_param("fissure_intensity")
		assert_float(warning_intensity).is_greater(0.0)

	# Transition to LEAKING state
	yield(_runner.simulate_frames(20), "completed") # > 0.1s
	assert_int(_leak.call("get_state")).is_equal(2) # State.LEAKING = 2

	yield(_runner.simulate_frames(10), "completed") # > 0.1s ramp up

	assert_bool(spray.emitting).is_true()
	assert_bool(mist.emitting).is_true()

	if mat != null:
		var leaking_intensity = mat.get_shader_param("fissure_intensity")
		assert_float(leaking_intensity).is_greater(0.2)


func test_patched_fissure_visuals() -> void:
	# Active leak patched with gloo -> fissure masked, spray cut off, gloo mesh visible
	_leak.set("warning_duration", 0.0)
	_leak.set("ramp_up_duration", 0.0)
	_leak.call("trigger_leak")

	yield(_runner.simulate_frames(5), "completed")
	assert_int(_leak.call("get_state")).is_equal(2) # State.LEAKING = 2

	_patch_point.call("patch_with_gloo")
	assert_bool(_patch_point.call("is_patched")).is_true()

	yield(_runner.simulate_frames(5), "completed")

	var spray: CPUParticles = _visual.get_node("SprayParticles")
	var mist: CPUParticles = _visual.get_node("MistParticles")
	var gloo: MeshInstance = _visual.get_node("GlooMesh")

	assert_bool(spray.emitting).is_false()
	assert_bool(mist.emitting).is_false()
	assert_bool(gloo.visible).is_true()

	var mat = _pipe_run.get("_material")
	if mat != null:
		var intensity = mat.get_shader_param("fissure_intensity")
		assert_float(intensity).is_equal(0.0)


func test_fissure_visual_snapshot_determinism() -> void:
	_visual.set("enabled", false)
	var snap = _visual.call("get_snapshot")

	assert_bool(snap.get("enabled", true)).is_false()

	_visual.set("enabled", true)
	_visual.call("restore_snapshot", snap)

	assert_bool(_visual.get("enabled")).is_false()
