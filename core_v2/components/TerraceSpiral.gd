extends MultiMeshInstance
tool
class_name TerraceSpiral

# SpiralGeneratorV2.gd
# Replica la lógica de OpenSCAD usando MultiMesh para alto rendimiento.

export(Mesh) var plate_mesh setget set_plate_mesh # Asigna aquí un CubeMesh de 80x80x2
export var total_height: float = 8000.0 setget set_total_height
export var plate_step: float = 40.0 setget set_plate_step
export var turns: float = 8.0 setget set_turns
export var r_min: float = 220.0 setget set_r_min
export var r_max: float = 260.0 setget set_r_max
export var interlock_angle: float = 45.0 setget set_interlock_angle
export var max_tilt_angle: float = -90.0 setget set_max_tilt_angle
export var use_smoothstep: bool = true setget set_use_smoothstep

# Controles de Animación
export var animate: bool = true # true = usar animación, false = usar manual_blend
export(float, 0.0, 1.0) var manual_blend: float = 0.0 setget set_manual_blend # 0 = Axial, 1 = Centrífugo
export var cycle_duration: float = 10.0 setget set_cycle_duration
# Cuántos physics frames saltar entre updates de animación (1=cada frame, 2=cada 2, etc.).
# Aumentar en HTML5 o plataformas lentas para reducir carga de GDScript.
export(int, 1, 8) var animation_update_interval: int = 1
var time_accumulator: float = 0.0
var _needs_rebuild: bool = true
var _last_applied_blend: float = -1.0
var _last_visual_blend: float = -2.0  # blend que ya está subido a la GPU
var _animation_tick_counter: int = 0
var _cached_transforms: Array = [] # Array of Transform
# Pre-cached por _setup_multimesh; no cambian con blend:
var _cached_thetas: Array = []   # Array of float
var _cached_origins: Array = []  # Array of Vector3
var _dome_lod_root: Spatial = null
var _dome_lod_overlay_entries: Array = []
var _dome_lod_overlay_signature := ""
var _dome_lod_structural_signature := ""
var _dome_lod_hidden_plates: Dictionary = {}  # plate_index -> bool
var _distance_culled_plates: Dictionary = {}  # plate_index -> bool, managed by WorldRotator

func _init():
	add_to_group("replay_sync")

func _ready():
	_rebuild_multimesh_if_needed()
	_update_spiral_animation()
	_ensure_dome_lod_root()

func _setup_multimesh():
	if plate_mesh == null:
		return

	var safe_step = max(plate_step, 0.001)
	var plate_count = max(2, int(round(total_height / safe_step)))

	if multimesh == null:
		multimesh = MultiMesh.new()
	else:
		# Godot 3 no permite cambiar format si ya tiene instancias activas.
		multimesh.instance_count = 0
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = plate_count
	multimesh.mesh = plate_mesh

	_ensure_transform_cache_size(plate_count)
	_precache_plate_geometry(plate_count)
	_last_applied_blend = -1.0 # Force update

func _ensure_transform_cache_size(plate_count: int):
	if _cached_transforms.size() == plate_count:
		return

	var previous_size = _cached_transforms.size()
	_cached_transforms.resize(plate_count)
	for i in range(previous_size, plate_count):
		_cached_transforms[i] = Transform.IDENTITY

# Pre-computa thetas y origins (no dependen del blend) para reusar cada frame.
func _precache_plate_geometry(plate_count: int) -> void:
	if plate_count <= 1:
		_cached_thetas.resize(0)
		_cached_origins.resize(0)
		return
	var safe_r_min: float = r_min if r_min != null else 0.0
	var safe_r_max: float = r_max if r_max != null else 0.0
	var safe_step: float = plate_step if plate_step != null else 40.0
	var safe_turns: float = turns if turns != null else 0.0
	var angle_per_plate: float = (360.0 * safe_turns) / float(plate_count)
	_cached_thetas.resize(plate_count)
	_cached_origins.resize(plate_count)
	for i in range(plate_count):
		var u: float = float(i) / float(plate_count - 1)
		var r: float = lerp(safe_r_min, safe_r_max, u)
		var z: float = float(i) * safe_step
		var theta: float = deg2rad(float(i) * angle_per_plate)
		_cached_thetas[i] = theta
		_cached_origins[i] = Vector3(cos(theta) * r, z, sin(theta) * r)

func _physics_process(delta: float):
	_rebuild_multimesh_if_needed()
	if animate:
		time_accumulator += delta
	_animation_tick_counter += 1
	if _animation_tick_counter >= animation_update_interval:
		_animation_tick_counter = 0
		_compute_spiral_transforms()

func _process(_delta: float):
	if Engine.editor_hint:
		return
	_apply_multimesh_visual()

# Actualiza _cached_transforms (estado de simulación). Se llama desde _physics_process.
# No toca la GPU — solo GDScript puro para mantener el presupuesto de física bajo.
func _compute_spiral_transforms() -> void:
	if not multimesh:
		return

	var blend: float = 0.0
	if animate:
		var safe_cycle: float = max(cycle_duration, 0.001)
		var half_cycle: float = safe_cycle / 2.0
		var t_in_cycle: float = fmod(time_accumulator, safe_cycle)
		var raw_t: float = 0.0
		if half_cycle > 0.0 and t_in_cycle < half_cycle:
			raw_t = t_in_cycle / half_cycle
		else:
			raw_t = 2.0 - (t_in_cycle / max(half_cycle, 0.001))
		blend = _apply_blend_easing(raw_t)
	else:
		blend = manual_blend if manual_blend != null else 0.0

	blend = clamp(blend, 0.0, 1.0)
	if abs(blend - _last_applied_blend) < 0.0001:
		return
	_last_applied_blend = blend

	var plate_count: int = multimesh.instance_count
	if plate_count <= 1:
		return
	_ensure_transform_cache_size(plate_count)

	var safe_tilt: float = max_tilt_angle if max_tilt_angle != null else -90.0
	var safe_interlock: float = interlock_angle if interlock_angle != null else 45.0
	var y_ang: float = deg2rad(safe_tilt * blend)
	var interlock_rad: float = deg2rad(safe_interlock * blend)
	var use_cache: bool = _cached_origins.size() == plate_count and _cached_thetas.size() == plate_count

	if use_cache:
		for i in range(plate_count):
			var theta: float = _cached_thetas[i]
			_cached_transforms[i] = Transform(_build_plate_basis(theta, y_ang, interlock_rad), _cached_origins[i])
	else:
		var safe_r_min: float = r_min if r_min != null else 0.0
		var safe_r_max: float = r_max if r_max != null else 0.0
		var safe_step: float = plate_step if plate_step != null else 40.0
		var safe_turns: float = turns if turns != null else 0.0
		var angle_per_plate: float = (360.0 * safe_turns) / float(plate_count)
		for i in range(plate_count):
			var u: float = float(i) / float(plate_count - 1)
			var r: float = lerp(safe_r_min, safe_r_max, u)
			var z: float = float(i) * safe_step
			var theta: float = deg2rad(float(i) * angle_per_plate)
			_cached_transforms[i] = Transform(_build_plate_basis(theta, y_ang, interlock_rad), Vector3(cos(theta) * r, z, sin(theta) * r))

# Sube _cached_transforms a la GPU (multimesh + overlays). Solo desde _process.
func _apply_multimesh_visual() -> void:
	if not multimesh:
		return
	if abs(_last_applied_blend - _last_visual_blend) < 0.0001:
		return
	_last_visual_blend = _last_applied_blend
	var plate_count: int = _cached_transforms.size()
	if plate_count == 0 or multimesh.instance_count != plate_count:
		return
	var hidden: Dictionary = _dome_lod_hidden_plates.duplicate()
	for k in _distance_culled_plates:
		hidden[k] = true
	var hidden_xform: Transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for i in range(plate_count):
		multimesh.set_instance_transform(i, hidden_xform if hidden.has(i) else _cached_transforms[i])
	_update_dome_lod_overlay_transforms()

# Compatibilidad: fuerza update completo (physics + visual) de forma sincrónica.
# Usado por editor (tool), restore_snapshot y _mark_dirty.
func _update_spiral_animation() -> void:
	_compute_spiral_transforms()
	if not Engine.editor_hint:
		# En runtime el visual se aplica en el siguiente _process; forzar para
		# casos de uso explícito (restore_snapshot, set_dome_lod_plate_hidden).
		_last_visual_blend = -2.0
	_apply_multimesh_visual()

func _ensure_dome_lod_root() -> void:
	if is_instance_valid(_dome_lod_root):
		return
	_dome_lod_root = Spatial.new()
	_dome_lod_root.name = "DomeLOD"
	add_child(_dome_lod_root)

func clear_dome_lod_overlays() -> void:
	_ensure_dome_lod_root()
	for child in _dome_lod_root.get_children():
		child.queue_free()
	_dome_lod_overlay_entries.clear()
	_dome_lod_structural_signature = ""
	_dome_lod_overlay_signature = ""
	_dome_lod_root.visible = false

func set_dome_lod_plate_hidden(plate_index: int, hidden: bool) -> void:
	var was_hidden: bool = _dome_lod_hidden_plates.has(plate_index)
	if hidden == was_hidden:
		return
	if hidden:
		_dome_lod_hidden_plates[plate_index] = true
	else:
		_dome_lod_hidden_plates.erase(plate_index)
	# Solo actualiza los items de este plate — no todos los 64 del overlay.
	_update_dome_lod_overlay_transforms_for_plate(plate_index)

func set_distance_culled_plates(culled_indices: Array) -> void:
	_distance_culled_plates.clear()
	for ci in culled_indices:
		_distance_culled_plates[int(ci)] = true
	_last_visual_blend = -2.0

func _update_dome_lod_overlay_transforms_for_plate(plate_index: int) -> void:
	if not is_instance_valid(_dome_lod_root):
		return
	var is_hidden: bool = _dome_lod_hidden_plates.has(plate_index)
	var hidden_xform := Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for entry in _dome_lod_overlay_entries:
		var instance: MultiMeshInstance = entry.get("instance", null)
		if not is_instance_valid(instance) or instance.multimesh == null:
			continue
		var items: Array = entry["items"]
		for item_index in range(items.size()):
			var item: Dictionary = items[item_index]
			if int(item["plate_index"]) != plate_index:
				continue
			if is_hidden:
				instance.multimesh.set_instance_transform(item_index, hidden_xform)
			elif plate_index < _cached_transforms.size():
				var overlay_transform: Transform = _cached_transforms[plate_index] * item["local_transform"]
				overlay_transform.origin += item["origin_offset"]
				instance.multimesh.set_instance_transform(item_index, overlay_transform)

func set_dome_lod_overlays(groups: Array) -> void:
	_ensure_dome_lod_root()
	if groups.empty():
		clear_dome_lod_overlays()
		return
	var signature := _build_dome_lod_overlay_signature(groups)
	if signature == _dome_lod_overlay_signature:
		_dome_lod_root.visible = true
		return
	# Structural signature: solo meshes y counts, sin posiciones de plates.
	# Si coincide, actualizamos items y transforms in-place sin destruir MultiMeshes.
	var structural_sig := _build_dome_lod_structural_signature(groups)
	if structural_sig == _dome_lod_structural_signature and not _dome_lod_overlay_entries.empty():
		_update_dome_lod_overlay_items(groups)
		_dome_lod_overlay_signature = signature
		_update_dome_lod_overlay_transforms()
		_dome_lod_root.visible = true
		return
	_rebuild_dome_lod_overlays(groups)
	_dome_lod_structural_signature = structural_sig
	_dome_lod_overlay_signature = signature
	_update_dome_lod_overlay_transforms()
	_dome_lod_root.visible = true

func _rebuild_dome_lod_overlays(groups: Array) -> void:
	for child in _dome_lod_root.get_children():
		child.queue_free()
	_dome_lod_overlay_entries.clear()
	var group_index := 0
	for group in groups:
		var parts: Array = group.get("parts", [])
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var mesh: Mesh = part.get("mesh", null)
			var items: Array = part.get("items", [])
			if mesh == null or items.empty():
				continue
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.color_format = MultiMesh.COLOR_NONE
			multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_NONE
			multimesh.mesh = mesh
			multimesh.instance_count = items.size()
			var instance := MultiMeshInstance.new()
			instance.name = "DomeLOD_%d_%d" % [group_index, part_index]
			instance.multimesh = multimesh
			instance.material_override = part.get("material_override", null)
			_dome_lod_root.add_child(instance)
			_dome_lod_overlay_entries.append({
				"instance": instance,
				"items": items
			})
		group_index += 1
	_dome_lod_overlay_signature = _build_dome_lod_overlay_signature(groups)

# Actualiza items y transforms in-place sin destruir/recrear MultiMeshes.
# Solo se llama cuando la structural signature coincide (mismos meshes, mismos counts).
func _update_dome_lod_overlay_items(groups: Array) -> void:
	var entry_index := 0
	for group in groups:
		var parts: Array = group.get("parts", [])
		for part_index in range(parts.size()):
			if entry_index >= _dome_lod_overlay_entries.size():
				break
			var part: Dictionary = parts[part_index]
			var entry: Dictionary = _dome_lod_overlay_entries[entry_index]
			entry["items"] = part.get("items", [])
			entry_index += 1

func _build_dome_lod_structural_signature(groups: Array) -> String:
	# Solo incluye identidad de meshes y counts, NO posiciones de plates.
	# Si dos grupos tienen los mismos meshes con los mismos counts, son estructuralmente iguales.
	var parts := PoolStringArray()
	for group in groups:
		parts.append(String(group.get("key", "group")))
		for part in group.get("parts", []):
			var mesh_path := ""
			var mesh: Mesh = part.get("mesh", null)
			if mesh != null and mesh.resource_path != "":
				mesh_path = mesh.resource_path
			var count: int = (part.get("items", []) as Array).size()
			parts.append("%s:%d" % [mesh_path, count])
	return parts.join("|")

func _update_dome_lod_overlay_transforms() -> void:
	if not is_instance_valid(_dome_lod_root):
		return
	var cache_size := _cached_transforms.size()
	var hidden := _dome_lod_hidden_plates
	var hidden_xform := Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for entry in _dome_lod_overlay_entries:
		var instance: MultiMeshInstance = entry.get("instance", null)
		if not is_instance_valid(instance) or instance.multimesh == null:
			continue
		var items: Array = entry["items"]
		var item_count := items.size()
		for item_index in range(item_count):
			var item: Dictionary = items[item_index]
			var plate_index: int = item["plate_index"]
			if plate_index < 0 or plate_index >= cache_size:
				instance.multimesh.set_instance_transform(item_index, Transform.IDENTITY)
				continue
			if hidden.has(plate_index):
				instance.multimesh.set_instance_transform(item_index, hidden_xform)
				continue
			var overlay_transform: Transform = _cached_transforms[plate_index] * item["local_transform"]
			overlay_transform.origin += item["origin_offset"]
			instance.multimesh.set_instance_transform(item_index, overlay_transform)

func _build_dome_lod_overlay_signature(groups: Array) -> String:
	var parts := PoolStringArray()
	for group in groups:
		parts.append(String(group.get("key", "group")))
		for part in group.get("parts", []):
			parts.append(String(part.get("signature", "part")))
	return parts.join("|")

func _build_plate_basis(theta: float, tilt_angle: float, interlock: float) -> Basis:
	var outward = Vector3(cos(theta), 0.0, sin(theta)).normalized()
	var tangent = outward.cross(Vector3.UP).normalized()
	var normal = Vector3.UP.rotated(tangent, -tilt_angle).normalized()

	var z_axis = tangent.rotated(normal, interlock).normalized()
	var x_axis = normal.cross(z_axis).normalized()
	z_axis = x_axis.cross(normal).normalized()
	return Basis(x_axis, normal, z_axis).orthonormalized()

func _apply_blend_easing(raw_t: float) -> float:
	var clamped_t = clamp(raw_t, 0.0, 1.0)
	if use_smoothstep:
		return _ease_smoothstep(clamped_t)
	return clamped_t

func _ease_smoothstep(x: float) -> float:
	return x * x * (3 - 2 * x)

func _rebuild_multimesh_if_needed():
	if _needs_rebuild:
		_setup_multimesh()
		_needs_rebuild = false

func _mark_dirty(rebuild: bool = false):
	if rebuild:
		_needs_rebuild = true
	_update_spiral_animation()

func set_plate_mesh(value: Mesh):
	plate_mesh = value
	_mark_dirty(true)

func set_total_height(value: float):
	total_height = max(value, 0.0)
	_mark_dirty(true)

func set_plate_step(value: float):
	plate_step = max(value, 0.001)
	_mark_dirty(true)

func set_turns(value: float):
	turns = value
	_mark_dirty()

func set_r_min(value: float):
	r_min = value
	_mark_dirty()

func set_r_max(value: float):
	r_max = value
	_mark_dirty()

func set_interlock_angle(value: float):
	interlock_angle = value
	_mark_dirty()

func set_max_tilt_angle(value: float):
	max_tilt_angle = value
	_mark_dirty()

func set_use_smoothstep(value: bool):
	use_smoothstep = value
	_mark_dirty()

func set_manual_blend(value: float):
	manual_blend = clamp(value, 0.0, 1.0)
	_mark_dirty()

func set_cycle_duration(value: float):
	cycle_duration = max(value, 0.001)
	_mark_dirty()

# --- Integración con Replay ---
func get_snapshot() -> Dictionary:
	return {"t": time_accumulator}

func restore_snapshot(data: Dictionary):
	time_accumulator = data.t
	_update_spiral_animation()
