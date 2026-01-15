tool
extends Area

enum Axis {LOCK_Z, LOCK_X}
export(Axis) var lock_axis = Axis.LOCK_Z
export(bool) var invert_side = false
export(float) var target_distance = 0.0 # 0.0 means use default 2.5D distance

export(float) var length := 8.0 setget set_length
export(float) var width := 2.0 setget set_width
export(float) var height := 4.0 setget set_height
export(bool) var show_debug_mesh := true setget set_show_debug_mesh

func _ready():
	if not Engine.editor_hint:
		connect("body_entered", self, "_on_body_entered")
		connect("body_exited", self, "_on_body_exited")
	
	_update_scaling()

func set_show_debug_mesh(v: bool) -> void:
	show_debug_mesh = v
	_update_scaling()

func set_length(v: float) -> void:
	length = max(v, 0.1)
	_update_scaling()

func set_width(v: float) -> void:
	width = max(v, 0.1)
	_update_scaling()

func set_height(v: float) -> void:
	height = max(v, 0.1)
	_update_scaling()

func _update_scaling() -> void:
	if not is_inside_tree():
		# Wait for tree entry to find children reliably
		return
		
	var col: CollisionShape = null
	var mesh: MeshInstance = null
	
	for child in get_children():
		if child is CollisionShape:
			col = child
		elif child is MeshInstance:
			mesh = child
			
	# 1. Update Collision
	if col and col.shape is BoxShape:
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
		
		col.shape.extents = Vector3(length / 2.0, height / 2.0, width / 2.0)
		# Centrar para que "apoye" en el suelo del nodo (Y=0)
		col.transform.origin = Vector3(0, height / 2.0, 0)
		
		if Engine.editor_hint:
			print("[SideScrollZone] ", name, " collision updated: ", Vector3(length, height, width))
	
	# 2. Update/Create Debug Mesh
	if show_debug_mesh:
		if not mesh:
			mesh = MeshInstance.new()
			mesh.name = "DebugMesh"
			mesh.mesh = CubeMesh.new()
			var mat = SpatialMaterial.new()
			mat.flags_transparent = true
			mat.albedo_color = Color(0.2, 0.5, 0.8, 0.3)
			mesh.material_override = mat
			mesh.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)
		
		mesh.scale = Vector3(length / 2.0, height / 2.0, width / 2.0)
		mesh.transform.origin = Vector3(0, height / 2.0, 0)
		mesh.visible = true
	elif mesh:
		mesh.visible = false

func _on_body_entered(body: Node):
	if Engine.editor_hint: return
	if body.has_method("enter_25d_mode"):
		var coord = global_transform.origin.z if lock_axis == Axis.LOCK_Z else global_transform.origin.x
		# 1 for X, 2 for Z
		var axis_int = 2 if lock_axis == Axis.LOCK_Z else 1
		body.enter_25d_mode(axis_int, coord, invert_side, target_distance)

func _on_body_exited(body: Node):
	if Engine.editor_hint: return
	if body.has_method("exit_25d_mode"):
		body.exit_25d_mode()
