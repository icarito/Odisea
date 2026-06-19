extends SceneTree

# verify_airlock_baked.gd — Structural validation of the baked AirlockChamber.
#
# Confirms the baked scene: (1) loads without errors, (2) has no CSG nodes left,
# (3) every MeshInstance references a non-null mesh, (4) the ShellMesh uses the
# baked hull mesh with its ShaderMaterial, (5) collision shapes are present.
# Headless-safe (no GPU render needed).
#
# Run: godot3-bin --no-window -s tools/verify_airlock_baked.gd

const SCENE_PATH := "res://core_v2/props/doors/AirlockChamber.tscn"

var _csg_nodes: Array = []
var _mesh_insts: Array = []
var _null_meshes: Array = []
var _mats_ok: int = 0

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
	yield(self, "idle_frame")

	_walk(root)

	var result := {
		"scene": "AirlockChamber",
		"csg_nodes_remaining": _csg_nodes.size(),
		"csg_node_names": _csg_nodes,
		"mesh_instances": _mesh_insts.size(),
		"null_mesh_refs": _null_meshes.size(),
		"null_mesh_names": _null_meshes,
		"materials_valid": _mats_ok,
	}
	print("VERIFY:" + to_json(result))

	# Asserts
	var ok := true
	var errs: Array = []
	if _csg_nodes.size() != 0:
		errs.append("CSG nodes still present: %s" % _csg_nodes)
		ok = false
	# _ZoneDebugMesh is a runtime debug node added by AirlockZoneV2, not part of
	# the chamber geometry; ignore it (it legitimately has no mesh until debug-rendered).
	var real_null := []
	for nm in _null_meshes:
		if nm != "_ZoneDebugMesh":
			real_null.append(nm)
	if real_null.size() != 0:
		errs.append("MeshInstances with null mesh: %s" % real_null)
		ok = false
	# ShellMesh must have the hull shader material
	var shell := root.get_node_or_null("CylindricalShell/ShellMesh")
	if shell == null:
		errs.append("CylindricalShell/ShellMesh not found")
		ok = false
	else:
		var mi: MeshInstance = shell
		if mi.mesh == null:
			errs.append("ShellMesh mesh is null")
			ok = false
		var mat: Material = mi.get_surface_material(0)
		if mat == null and mi.mesh != null:
			mat = mi.mesh.surface_get_material(0)
		if mat != null and (mat is ShaderMaterial):
			result["shell_uses_shader"] = true
		else:
			errs.append("ShellMesh material is not a ShaderMaterial")
			ok = false
	# Collision shape for shell
	var col := root.get_node_or_null("CylindricalShell/CollisionShape")
	if col == null:
		errs.append("CylindricalShell/CollisionShape not found")
		ok = false
	elif not (col is CollisionShape):
		errs.append("CylindricalShell/CollisionShape is not a CollisionShape")
		ok = false
	else:
		var cs: CollisionShape = col
		if cs.shape == null:
			errs.append("CylindricalShell collision shape is null")
			ok = false

	if ok:
		print("VERIFY_RESULT: PASS")
	else:
		print("VERIFY_RESULT: FAIL")
		for e in errs:
			push_error(e)
	root.free()
	quit(0 if ok else 1)

func _walk(node: Node) -> void:
	if node is CSGShape:
		_csg_nodes.append(node.name)
	if node is MeshInstance:
		_mesh_insts.append(node.name)
		var m: MeshInstance = node
		if m.mesh == null:
			_null_meshes.append(node.name)
		else:
			var mat: Material = m.get_surface_material(0)
			if mat == null:
				mat = m.mesh.surface_get_material(0)
			if mat != null:
				_mats_ok += 1
	for c in node.get_children():
		_walk(c)
