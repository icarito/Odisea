extends InteractableBaseV2
class_name IrisDoorV2
tool

# IrisDoorV2.gd - Mathematically Perfect Iris Door Mechanism (v6.1 GAP FIX VERSION)
# Automates pivot positioning and ensures hermetic closure by overlapping tips.

export(float) var rotation_angle := -95.0 setget set_rotation_angle
export(Vector3) var rotation_axis := Vector3(0, 0, 1) setget set_rotation_axis
export(float) var offset_per_blade := 0.005 setget set_offset_per_blade
export(float) var iris_radius := 0.5 setget set_iris_radius
export(bool) var rebuild_now := false setget set_rebuild_now # Manual trigger
export(bool) var rebuild_at_runtime := true
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1
export(NodePath) var blades_container_path := NodePath(".")

func set_rotation_angle(v: float) -> void:
	rotation_angle = v
	_update_visuals()

func set_rotation_axis(v: Vector3) -> void:
	rotation_axis = v
	_update_visuals()

func set_offset_per_blade(v: float) -> void:
	offset_per_blade = v
	_initialize()
	_setup_mathematical_positions()
	_update_visuals()

func set_iris_radius(v: float) -> void:
	iris_radius = v
	_setup_mathematical_positions()
	_update_visuals()

func set_rebuild_now(_v: bool) -> void:
	_initialize()
	_setup_mathematical_positions()
	_update_visuals()

var _blades: Array = []
var _start_rotations: Array = []
var _initialized := false
var _door_blocker: CollisionShape = null

# --- Merge de aspas en reposo (optimización de draw calls) ---
# Cada puerta tiene 8 BladeGeo idénticos: 64 MeshInstances por airlock de 4 puertas,
# ~48% de los meshes de un domo o de una fachada. En reposo (cerrada del todo) las
# aspas nunca se mueven, así que se hornean en un único MeshInstance y se ocultan las
# individuales. Al animar se vuelve a los nodos reales, que siguen siendo la fuente
# de verdad: la matemática de _setup_mathematical_positions no cambia.
var _merged_blades: MeshInstance = null
var _blades_merged := false

func _ready():
	_initialize()
	_door_blocker = get_node_or_null("DoorBlocker/CollisionShape") as CollisionShape
	if rebuild_at_runtime or Engine.editor_hint:
		_setup_mathematical_positions()
	._ready()
	# En el editor conviene ver las aspas reales para poder editarlas.
	if not Engine.editor_hint:
		call_deferred("_merge_blades_if_idle")

func _initialize():
	_blades.clear()
	_start_rotations.clear()

	var container = get_node_or_null(blades_container_path)
	if not container:
		return

	var children = container.get_children()
	for child in children:
		if child is Spatial and child.name.begins_with("BladePivot"):
			_blades.append(child)
	
	# Sort blades by name for consistent Z-stacking
	_blades.sort_custom(self, "_sort_blades")
	
	for i in range(_blades.size()):
		_start_rotations.append(_blades[i].rotation_degrees)

	_initialized = true

func _sort_blades(a, b):
	return a.name < b.name

func _setup_mathematical_positions():
	if not _initialized:
		_initialize()
	
	var count = _blades.size()
	if count == 0:
		return
	
	for i in range(count):
		var blade = _blades[i]
		var angle = (PI * 2.0 / count) * i
		var x = cos(angle) * iris_radius
		var y = sin(angle) * iris_radius
		
		# Position in circle with Z offset for stacking
		blade.transform.origin = Vector3(x, y, i * offset_per_blade)
		
		# Base Orientation: Pointing towards the center (CLOSED state)
		# We add PI (180 degrees) to the positional angle to look at (0,0)
		blade.rotation = Vector3(0, 0, angle + PI)
		
		# Update the start rotation buffer
		if _start_rotations.size() <= i:
			_start_rotations.append(blade.rotation_degrees)
		else:
			_start_rotations[i] = blade.rotation_degrees

func _update_visuals() -> void:
	if not _initialized:
		_initialize()
		if Engine.editor_hint: _setup_mathematical_positions()

	# Mientras la puerta se mueve hacen falta las aspas individuales; en reposo
	# vuelve el mesh horneado.
	if not Engine.editor_hint:
		if anim_progress > 0.001:
			_unmerge_blades()
		elif not _blades_merged:
			call_deferred("_merge_blades_if_idle")

	var eased = _apply_easing(anim_progress)
	# State Base (0.0): Offset 0
	# State Open (1.0): Offset +90 degrees (Tangential Outward)
	var open_angle_rad = deg2rad(90.0)
	var current_offset = lerp(0.0, open_angle_rad, eased)

	for i in range(_blades.size()):
		var blade = _blades[i]
		if not is_instance_valid(blade):
			continue

		var start_rot_deg = _start_rotations[i]
		# Apply base rotation + dynamic tangential offset
		blade.rotation_degrees.z = start_rot_deg.z + rad2deg(current_offset)

		if blade is CollisionObject or blade is CSGShape:
			if blade.has_method("force_update_transform"):
				blade.force_update_transform()

	if is_instance_valid(_door_blocker):
		_door_blocker.disabled = anim_progress > 0.15

# Hornea las 8 aspas en un solo MeshInstance si la puerta está completamente cerrada.
# Idempotente: si ya está horneada o la puerta no está en reposo, no hace nada.
func _merge_blades_if_idle() -> void:
	if _blades_merged or Engine.editor_hint:
		return
	if anim_progress > 0.001:
		return
	if not _initialized:
		_initialize()
	if _blades.size() < 2:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material: Material = null
	var merged_any := false

	for blade in _blades:
		if not is_instance_valid(blade):
			continue
		var geo := blade.get_node_or_null("BladeGeo") as MeshInstance
		if geo == null or geo.mesh == null:
			continue
		if material == null:
			# El material puede venir del override del nodo o del propio mesh.
			material = geo.get_surface_material(0)
			if material == null:
				material = geo.mesh.surface_get_material(0)
		# Transform de la geometría relativa al mecanismo (padre común).
		var local: Transform = blade.transform * geo.transform
		_append_mesh(st, geo.mesh, local)
		merged_any = true

	if not merged_any:
		return

	st.generate_normals()
	var merged_mesh: ArrayMesh = st.commit()
	if merged_mesh == null or merged_mesh.get_surface_count() == 0:
		return
	if material != null:
		merged_mesh.surface_set_material(0, material)

	_merged_blades = MeshInstance.new()
	_merged_blades.name = "BladesMerged"
	_merged_blades.mesh = merged_mesh
	add_child(_merged_blades)

	_set_blade_geo_visible(false)
	_blades_merged = true

# Vuelve a las aspas individuales para poder animarlas.
func _unmerge_blades() -> void:
	if not _blades_merged:
		return
	_set_blade_geo_visible(true)
	if is_instance_valid(_merged_blades):
		_merged_blades.queue_free()
	_merged_blades = null
	_blades_merged = false

func _set_blade_geo_visible(v: bool) -> void:
	for blade in _blades:
		if not is_instance_valid(blade):
			continue
		var geo := blade.get_node_or_null("BladeGeo") as MeshInstance
		if is_instance_valid(geo):
			geo.visible = v

func _append_mesh(st: SurfaceTool, mesh: Mesh, xform: Transform) -> void:
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var idx = arrays[Mesh.ARRAY_INDEX]
		# CubeMesh viene indexado; si no lo estuviera, se recorre en orden.
		var order := []
		if idx != null and idx.size() > 0:
			for i in idx:
				order.append(i)
		else:
			for i in range(verts.size()):
				order.append(i)
		for i in order:
			if normals != null and normals.size() > i:
				st.add_normal(xform.basis.xform(normals[i]).normalized())
			if uvs != null and uvs.size() > i:
				st.add_uv(uvs[i])
			st.add_vertex(xform.xform(verts[i]))

func _apply_easing(t: float) -> float:
	match easing_type:
		0: return t
		1: return _ease_in_out(t)
		2: return _ease_in(t)
		3: return _ease_out(t)
	return t

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	var rots = []
	for r in _start_rotations:
		rots.append([r.x, r.y, r.z])
	snap["start_rots"] = rots
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_rots"):
		var rots = data["start_rots"]
		_start_rotations.clear()
		for r in rots:
			_start_rotations.append(Vector3(r[0], r[1], r[2]))
	.restore_snapshot(data)

func _process(_delta):
	if Engine.editor_hint:
		if not _initialized:
			_initialize()
			_setup_mathematical_positions()
