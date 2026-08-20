extends SceneTree

# bake_pipe_valve.gd — Bakes PipeValve.tscn's three decorative CSG shapes
# (ValveBody, Wheel/Rim, StatusIndicator) into static ArrayMesh instances, and drops
# their use_collision=true.
#
# Same problem as tools/bake_iris_frame.gd: CSGCombiner/CSGCylinder/CSGTorus with
# use_collision=true rebuild their boolean geometry AND generate a trimesh collider
# in real time. FD-270's Dome_Intro has 13 PipeValve instances, so that's up to
# ~65 CSG collision objects registered in Bullet's broadphase just for decoration —
# the wheel's rim, the casing, the status light housing are never meant to block the
# player, PipeValve already has two real CylinderShape colliders (Wheel/StaticBody,
# BaseStaticBody) covering the actual interactive geometry.
#
# Unlike the iris frame, we do NOT bake a collision shape here: the decorative CSG
# never needs one, so this only saves meshes and clears use_collision.
#
# Run: godot3-bin --no-window -s tools/bake_pipe_valve.gd
# Output: core_v2/props/pipe/PipeValve_*.mesh, and PipeValve.tscn edited to reference
# MeshInstance nodes instead of CSG shapes.

const SCENE_PATH := "res://core_v2/props/pipe/PipeValve.tscn"
const OUT_DIR := "res://core_v2/props/pipe/"

# node path (relative to root) -> baked mesh output name
const TARGETS := {
	"ValveBody": "PipeValve_ValveBody_baked.mesh",
	"Wheel/Rim": "PipeValve_WheelRim_baked.mesh",
}
# StatusIndicator combines BezelHousing (static) with StatusLight (recolored at
# runtime by PipeValve.gd) and LabelOpen (already a plain MeshInstance, not CSG).
# get_meshes() on a CSG child inside a combiner returns empty — only the combiner
# root exposes the merged result — so StatusLight is removed from the tree BEFORE
# baking StatusIndicator, then the bake only captures BezelHousing's geometry.
const STATUS_INDICATOR_PATH := "StatusIndicator"
const STATUS_LIGHT_NAME := "StatusLight"
const STATUS_OUT := "PipeValve_BezelHousing_baked.mesh"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return

	var root: Node = scene.instance()
	get_root().add_child(root)

	# CSG only builds its mesh once inside the tree and processed for a few frames.
	for _i in range(10):
		yield(self, "idle_frame")

	for node_path in TARGETS.keys():
		var out_name: String = TARGETS[node_path]
		var csg := root.get_node_or_null(node_path)
		if csg == null or not (csg is CSGShape):
			push_error("%s: CSGShape not found" % node_path)
			quit(1)
			return
		var meshes: Array = csg.get_meshes()
		if meshes.size() < 2 or meshes[1] == null:
			push_error("%s: CSG produced no mesh — meshes=%s" % [node_path, meshes])
			quit(1)
			return
		var mesh: Mesh = meshes[1]
		var out_path := OUT_DIR + out_name
		var err := ResourceSaver.save(out_path, mesh)
		if err != OK:
			push_error("Failed saving %s: %d" % [out_path, err])
			quit(1)
			return
		print("[bake_pipe_valve] Saved %s (surfaces=%d, aabb=%s)" % [out_path, mesh.get_surface_count(), mesh.get_aabb()])

	var indicator := root.get_node_or_null(STATUS_INDICATOR_PATH)
	if indicator == null or not (indicator is CSGShape):
		push_error("%s: CSGShape not found" % STATUS_INDICATOR_PATH)
		quit(1)
		return
	var status_light := indicator.get_node_or_null(STATUS_LIGHT_NAME)
	if status_light != null:
		indicator.remove_child(status_light)
		status_light.free()
	# Let the combiner rebuild without StatusLight before reading its result.
	for _i in range(10):
		yield(self, "idle_frame")
	var indicator_meshes: Array = indicator.get_meshes()
	if indicator_meshes.size() < 2 or indicator_meshes[1] == null:
		push_error("%s: CSG produced no mesh after removing %s — meshes=%s" % [STATUS_INDICATOR_PATH, STATUS_LIGHT_NAME, indicator_meshes])
		quit(1)
		return
	var indicator_mesh: Mesh = indicator_meshes[1]
	var indicator_out_path := OUT_DIR + STATUS_OUT
	var ierr := ResourceSaver.save(indicator_out_path, indicator_mesh)
	if ierr != OK:
		push_error("Failed saving %s: %d" % [indicator_out_path, ierr])
		quit(1)
		return
	print("[bake_pipe_valve] Saved %s (surfaces=%d, aabb=%s)" % [indicator_out_path, indicator_mesh.get_surface_count(), indicator_mesh.get_aabb()])

	root.free()
	quit(0)
