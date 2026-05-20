extends Spatial
tool
class_name WorldRotator

# WorldRotator — rota el entorno visual para alinear la plataforma activa con la gravedad estándar.
#
# Arquitectura (FD-036):
#   - El PlayerControllerV2 vive FUERA de este nodo. No hay cambios en física del jugador.
#   - Este nodo contiene todo lo visual del entorno (TerraceSpirals, skybox, props).
#   - Cuando cambia la plataforma activa, este nodo slerp su propia rotación para que
#     el eje "up" de esa plataforma quede alineado con +Y global.
#
# Primera pasada — modo axial:
#   - Plataformas horizontales → sin rotación (identity).
#   - spiral_blend sincroniza visualmente todos los TerraceSpiral hijos en el mismo estado.

signal platform_changed(platform_node)

# Velocidad de interpolación de la rotación del mundo (rad/s).
export(float) var rotation_speed := 2.0

# Nodo que define la plataforma activa.
# Su eje local +Y debe ser la dirección "arriba" para el jugador sobre esa plataforma.
# Puede ser un hijo (TerraceSpiral) o un nodo externo (CSGBox, KinematicBody, etc.)
export(NodePath) var current_platform := NodePath("") setget _set_current_platform_path

# Blend 0->1 compartido por todos los TerraceSpiral hijos.
# 0 = configuración axial (espiras verticales), 1 = centrifugo (espiras planas).
# Sincroniza visualmente el estado de transición de las espiras.
export(float, 0.0, 1.0) var spiral_blend := 0.0 setget _set_spiral_blend

# Si no hay current_platform explícito, usa la primera TerraceSpiral registrada.
export(bool) var auto_select_first_platform := true

# Selección explícita de una plate de TerraceSpiral. Esto permite asignar desde
# el Inspector una plataforma física a un id estable: espiral N, piso/plate M.
export(int, 0, 1024) var selected_spiral := 0 setget _set_selected_spiral
export(int, 0, 10000) var selected_plate := 0 setget _set_selected_plate
export(bool) var apply_selection_on_ready := false
export(bool) var snap_on_selection := true
export(bool) var configure_gravity_from_selection := true

# Colisiones físicas generadas para probar/usar terrazas sin authoring manual.
export(NodePath) var physical_terrace_path := NodePath("")
export(Vector3) var fallback_collision_extents := Vector3(100.0, 1.0, 100.0)
export(bool) var auto_track_target_plate := false
export(NodePath) var tracking_target_path := NodePath("")
export(float) var auto_track_min_switch_distance := 20.0
export(bool) var auto_track_requires_floor_contact := true
export(bool) var continuous_tracking := true

# Pool fijo de StaticBodies reutilizables para colisiones de terrazas.
# En lugar de crear/destruir objetos al cambiar de plate, se reasignan los
# slots del pool a las N plates más cercanas solo cuando el jugador cambia de zona.
# Un tamaño de 32 cubre ~8 plates por espiral en el entorno inmediato.
export(int, 4, 128) var collision_pool_size := 12

# Cada cuántos physics frames se recalcula la asignación del pool.
# Esto solo controla la búsqueda/ordenamiento de placas cercanas; los transforms
# de los colliders ya asignados se sincronizan cada frame para seguir el tilt.
export(int, 1, 60) var collision_update_interval := 12
# Distancia mínima en espacio canónico para volver a buscar las placas cercanas.
# Con 0 se recupera el comportamiento anterior: reordenar en cada intervalo.
export(float, 0.0, 200.0) var collision_reassign_min_distance := 30.0
# Factor de escala en XZ para los BoxShape del pool.
# 1.0 = límites exactos del mesh visible. Mantenerlo exacto evita que el
# jugador pueda caminar sobre colisión invisible fuera de la placa.
export(float, 0.5, 3.0) var collision_pool_xz_scale := 1.0

# ── Estado interno ──────────────────────────────────────────────────────────

var _platform_node: Spatial = null
var _target_quat := Quat()
var _has_transform_target := false
var _target_global_transform := Transform.IDENTITY
var _registered_platforms: Array = []  # Array[Spatial]
var _selected_spiral_index := -1
var _selected_plate_index := -1
var _selected_plate_canonical := Transform.IDENTITY
var _active_collision_body: StaticBody = null
var _active_collision_shape: CollisionShape = null
var _generated_collision_root: Spatial = null
# Pool fijo: cada slot es un StaticBody pre-creado con BoxShape.
# _pool_assignments[i] = {"spiral": int, "plate": int} o {} si el slot está libre.
var _collision_pool: Array = []        # Array[StaticBody]
var _pool_assignments: Array = []      # Array[Dictionary]
var _pool_update_counter: int = 0
var _pool_force_reassign := true
var _pool_has_assignment_center := false
var _pool_assignment_center_canonical := Vector3.ZERO
var _pool_assignment_selected_spiral := -1
var _pool_assignment_selected_plate := -1
var _pool_assignment_xz_scale := -1.0
# Retrocompatibilidad: alias del pool para tests que lean _generated_collision_bodies
var _generated_collision_bodies: Array setget ,_get_generated_collision_bodies
func _get_generated_collision_bodies() -> Array:
	return _collision_pool

# ── Ciclo de vida ────────────────────────────────────────────────────────────

func _ready() -> void:
	_auto_register_platforms()
	if not current_platform.is_empty():
		_platform_node = get_node_or_null(current_platform) as Spatial
	elif auto_select_first_platform and not _registered_platforms.empty():
		_platform_node = _registered_platforms[0]
		current_platform = _path_to(_platform_node)
	_recompute_target()
	_sync_spirals()
	call_deferred("_build_collision_pool")
	call_deferred("_apply_configured_selection_if_needed")
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").register_rotator(self)

func _exit_tree() -> void:
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").unregister_rotator(self)
	_destroy_collision_pool()

func _physics_process(delta: float) -> void:
	if continuous_tracking:
		_update_continuous_tracking(delta)
	# El tracking por plates corre siempre: detecta cambio de plate activa
	# independientemente de si continuous_tracking está activo o no.
	_update_tracked_target_plate()

	if _has_transform_target:
		_slerp_to_global_transform(delta)
	else:
		_slerp_to_target(delta)

	_update_active_collision_layer_for_mode()

	var pool_update_due: bool = _pool_force_reassign
	if not pool_update_due:
		_pool_update_counter += 1
		pool_update_due = _pool_update_counter >= collision_update_interval
	if pool_update_due:
		_pool_update_counter = 0
		if _should_reassign_collision_pool():
			_assign_pool_to_nearest_plates()
		else:
			_sync_assigned_pool_transforms()
	else:
		_sync_assigned_pool_transforms()

# ── API pública ──────────────────────────────────────────────────────────────

# Cambia la plataforma activa. WorldRotator comenzará a rotar hacia el gravity frame del nodo.
# 'node' puede ser cualquier Spatial — su eje local +Y define la dirección "arriba".
func set_active_platform(node: Spatial) -> void:
	_has_transform_target = false
	if node == null:
		_platform_node = null
		current_platform = NodePath("")
		_recompute_target()
		emit_signal("platform_changed", null)
		return
	_platform_node = node
	current_platform = _path_to(node)
	_recompute_target()
	emit_signal("platform_changed", node)

# Alias conveniente de set_active_platform.
func navigate_to(platform_node: Spatial) -> void:
	set_active_platform(platform_node)

# Cicla al siguiente platform registrado.
func navigate_next() -> void:
	if _registered_platforms.empty():
		return
	var idx: int = _registered_platforms.find(_platform_node)
	idx = (idx + 1) % _registered_platforms.size()
	set_active_platform(_registered_platforms[idx])

# Cicla al platform anterior.
func navigate_prev() -> void:
	if _registered_platforms.empty():
		return
	var idx: int = _registered_platforms.find(_platform_node)
	idx = (idx - 1 + _registered_platforms.size()) % _registered_platforms.size()
	set_active_platform(_registered_platforms[idx])

# Registra un nodo como plataforma navegable. Se llama automáticamente para hijos TerraceSpiral.
func register_platform(node: Spatial) -> void:
	if not _registered_platforms.has(node):
		_registered_platforms.append(node)

# Devuelve la lista de plataformas registradas (solo lectura).
func get_platforms() -> Array:
	return _registered_platforms

# Convierte una posición global al espacio canónico estable del WorldRotator.
func to_canonical(global_position: Vector3) -> Vector3:
	return global_transform.affine_inverse().xform(global_position)

# Convierte una posición del espacio canónico del WorldRotator a global.
func from_canonical(canonical_position: Vector3) -> Vector3:
	return global_transform.xform(canonical_position)

# Transform global->canónico completo para sistemas de streaming/LOD.
func get_canonical_transform() -> Transform:
	return global_transform.affine_inverse()

# Reencuadra el mundo visual para que un transform canónico interno quede
# exactamente sobre un transform físico estable fuera del WorldRotator.
func align_canonical_transform_to_global(canonical_transform: Transform, target_global_transform: Transform, snap_immediately: bool = false) -> void:
	_has_transform_target = true
	_platform_node = null
	current_platform = NodePath("")
	_target_global_transform = target_global_transform * canonical_transform.affine_inverse()
	if snap_immediately:
		global_transform = _target_global_transform

# Selecciona una plate de TerraceSpiral, reencuadra el mundo para que coincida
# con una terraza física estable y genera colisiones equivalentes para plates vecinas.
func select_terrace_plate(spiral_index: int, plate_index: int, target_body: Spatial = null, snap_immediately: bool = false) -> bool:
	_auto_register_platforms()
	_sync_spirals()
	if _registered_platforms.empty():
		return false
	_selected_spiral_index = _wrap_index(spiral_index, _registered_platforms.size())
	selected_spiral = _selected_spiral_index
	var spiral: Spatial = _registered_platforms[_selected_spiral_index]
	_force_spiral_update(spiral)
	var plate_count: int = get_plate_count(spiral)
	if plate_count <= 0:
		return false
	_selected_plate_index = clamp(plate_index, 0, plate_count - 1)
	selected_plate = _selected_plate_index
	_selected_plate_canonical = get_plate_canonical_transform(spiral, _selected_plate_index)

	if target_body == null:
		target_body = _ensure_active_collision_body()
	else:
		_active_collision_body = target_body as StaticBody
		if _active_collision_body:
			_active_collision_shape = _find_collision_shape(_active_collision_body)
			if _active_collision_shape == null:
				_active_collision_shape = _create_collision_shape(_active_collision_body)

	_set_collision_plate_meta(_active_collision_body, _selected_spiral_index, _selected_plate_index)
	_sync_active_collision_shape(spiral)
	align_canonical_transform_to_global(_selected_plate_canonical, target_body.global_transform, snap_immediately)
	_configure_gravity_for_selected_plate(_selected_plate_canonical)
	# Forzar reasignación inmediata del pool al nuevo centro.
	_force_collision_pool_reassign()
	return true

# Aplica la selección exportada actual. Es la entrada pensada para escenas de
# prueba, OYS y tooling: configurar id + physical_terrace_path y dejar que este
# nodo encuadre el mundo.
func apply_selection() -> bool:
	return select_terrace_plate(selected_spiral, selected_plate, null, snap_on_selection)

func set_selected_terrace_plate(spiral_index: int, plate_index: int, snap_immediately: bool = true) -> bool:
	selected_spiral = spiral_index
	selected_plate = plate_index
	return select_terrace_plate(selected_spiral, selected_plate, null, snap_immediately)

func get_selected_plate_canonical_transform() -> Transform:
	return _selected_plate_canonical

func get_selected_plate_global_transform() -> Transform:
	if _selected_spiral_index < 0 or _selected_spiral_index >= _registered_platforms.size():
		return Transform.IDENTITY
	return global_transform * _selected_plate_canonical

func get_active_collision_body() -> StaticBody:
	return _active_collision_body

func get_active_collision_transform() -> Transform:
	if _active_collision_body:
		return _active_collision_body.global_transform
	return Transform.IDENTITY

func get_generated_collision_count() -> int:
	# Devuelve cuántos slots del pool están asignados a una plate.
	var count: int = 0
	for assignment in _pool_assignments:
		if not assignment.empty():
			count += 1
	return count

func get_selected_spiral_index() -> int:
	return _selected_spiral_index

func get_selected_plate_index() -> int:
	return _selected_plate_index

func get_plate_count(spiral: Spatial) -> int:
	if spiral == null:
		return 0
	var multimesh: MultiMesh = spiral.get("multimesh")
	if multimesh == null:
		return 0
	return multimesh.instance_count

func get_plate_canonical_transform(spiral: Spatial, plate_index: int) -> Transform:
	var multimesh: MultiMesh = spiral.get("multimesh")
	if multimesh == null or multimesh.instance_count <= 0:
		return Transform.IDENTITY
	var clamped_index: int = clamp(plate_index, 0, multimesh.instance_count - 1)
	var spiral_canonical: Transform = global_transform.affine_inverse() * spiral.global_transform
	return spiral_canonical * multimesh.get_instance_transform(clamped_index)

func find_nearest_terrace_plate(global_position: Vector3) -> Dictionary:
	_auto_register_platforms()
	if _registered_platforms.empty():
		return {}
	var canonical_position: Vector3 = to_canonical(global_position)
	var best: Dictionary = {}
	var best_dist_sq: float = INF
	for spiral_index in range(_registered_platforms.size()):
		var spiral: Spatial = _registered_platforms[spiral_index]
		_force_spiral_update(spiral)
		var plate_count: int = get_plate_count(spiral)
		for plate_index in range(plate_count):
			var plate_tx: Transform = get_plate_canonical_transform(spiral, plate_index)
			var dist_sq: float = _get_plate_contact_distance_squared(spiral, plate_tx, canonical_position)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best = {
					"spiral_index": spiral_index,
					"plate_index": plate_index,
					"distance": sqrt(dist_sq),
					"canonical_transform": plate_tx
				}
	return best

func _get_plate_contact_distance_squared(spiral: Spatial, plate_canonical: Transform, canonical_position: Vector3) -> float:
	# Distancia 3D simple entre el jugador y el centro de la plate.
	# Las plates inclinadas tienen su espacio local torcido respecto al movimiento
	# horizontal del jugador — calcular en espacio local producía rankings incorrectos.
	return plate_canonical.origin.distance_squared_to(canonical_position)

func _get_plate_distance_for_indices(spiral_index: int, plate_index: int, global_position: Vector3) -> float:
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return INF
	var spiral: Spatial = _registered_platforms[spiral_index]
	var plate_count: int = get_plate_count(spiral)
	if plate_index < 0 or plate_index >= plate_count:
		return INF
	var canonical_position: Vector3 = to_canonical(global_position)
	var plate_tx: Transform = get_plate_canonical_transform(spiral, plate_index)
	return sqrt(_get_plate_contact_distance_squared(spiral, plate_tx, canonical_position))

# Fuerza la recomputación del target (útil si la plataforma cambió su orientación).
func invalidate_target() -> void:
	_recompute_target()

# ── Setters de propiedades exportadas ────────────────────────────────────────

func _set_current_platform_path(path: NodePath) -> void:
	current_platform = path
	if is_inside_tree():
		if path.is_empty():
			_platform_node = null
			_recompute_target()
			return
		var node = get_node_or_null(path) as Spatial
		if node:
			_platform_node = node
			_recompute_target()

func _set_spiral_blend(value: float) -> void:
	spiral_blend = clamp(value, 0.0, 1.0)
	if is_inside_tree():
		_sync_spirals()
		if apply_selection_on_ready and _selected_spiral_index >= 0:
			apply_selection()

func _set_selected_spiral(value: int) -> void:
	selected_spiral = max(value, 0)
	if is_inside_tree() and apply_selection_on_ready:
		apply_selection()

func _set_selected_plate(value: int) -> void:
	selected_plate = max(value, 0)
	if is_inside_tree() and apply_selection_on_ready:
		apply_selection()

# ── Implementación ───────────────────────────────────────────────────────────

func _apply_configured_selection_if_needed() -> void:
	if apply_selection_on_ready:
		apply_selection()

func _auto_register_platforms() -> void:
	_registered_platforms.clear()
	_register_platforms_recursive(self)

func _register_platforms_recursive(root: Node) -> void:
	for child in root.get_children():
		if child is Spatial and child.get_script() != null:
			var path: String = child.get_script().resource_path
			if path.get_file() == "TerraceSpiral.gd":
				register_platform(child)
		_register_platforms_recursive(child)

func _recompute_target() -> void:
	if _platform_node == null:
		_target_quat = Quat()
		return

	# Dirección "arriba" de la plataforma en el espacio CANÓNICO del WorldRotator.
	# "Canónico" significa: independiente de la rotación actual del WorldRotator,
	# para evitar dependencias circulares donde el target se mueve junto con self.
	var up: Vector3
	if _is_child_of_self(_platform_node):
		# El nodo puede estar anidado bajo el WorldRotator. Convertimos su global
		# al espacio local de self para obtener el "up canónico".
		var local_xform: Transform = global_transform.affine_inverse() * _platform_node.global_transform
		up = local_xform.basis.y.normalized()
	else:
		# Nodo externo: su orientación no depende de WorldRotator.
		var global_up: Vector3 = _platform_node.global_transform.basis.y.normalized()
		if get_parent() is Spatial:
			up = (get_parent() as Spatial).global_transform.basis.xform_inv(global_up).normalized()
		else:
			up = global_up

	_target_quat = _quat_align(up, Vector3.UP)

func _slerp_to_target(delta: float) -> void:
	var q_cur: Quat = transform.basis.get_rotation_quat()
	var q_new: Quat = q_cur.slerp(_target_quat, min(1.0, rotation_speed * delta))
	transform.basis = Basis(q_new).orthonormalized()

func _slerp_to_global_transform(delta: float) -> void:
	var t: float = min(1.0, rotation_speed * delta)
	var current: Transform = global_transform
	var q_cur: Quat = current.basis.get_rotation_quat()
	var q_target: Quat = _target_global_transform.basis.get_rotation_quat()
	var q_new: Quat = q_cur.slerp(q_target, t)
	var origin_new: Vector3 = current.origin.linear_interpolate(_target_global_transform.origin, t)
	global_transform = Transform(Basis(q_new).orthonormalized(), origin_new)

func _sync_spirals() -> void:
	_sync_spirals_recursive(self)

func _sync_spirals_recursive(root: Node) -> void:
	for child in root.get_children():
		if child.get_script() != null and child.get_script().resource_path.get_file() == "TerraceSpiral.gd":
			child.animate = false
			child.manual_blend = spiral_blend
		_sync_spirals_recursive(child)

func _update_tracked_target_plate() -> void:
	if not auto_track_target_plate or spiral_blend <= 0.001:
		return
	var target: Spatial = _get_tracking_target()
	if target == null:
		return
	var target_plate: Dictionary = _find_floor_contact_plate(target)
	if target_plate.empty():
		if auto_track_requires_floor_contact and target.has_method("is_on_floor"):
			return
		target_plate = find_nearest_terrace_plate(target.global_transform.origin)
	if target_plate.empty():
		return
	var spiral_index: int = int(target_plate["spiral_index"])
	var plate_index: int = int(target_plate["plate_index"])
	if spiral_index == _selected_spiral_index and plate_index == _selected_plate_index:
		return
	if continuous_tracking and _selected_spiral_index >= 0 and _selected_plate_index >= 0 \
			and auto_track_min_switch_distance > 0.0:
		var target_global_position: Vector3 = target.global_transform.origin
		var current_distance: float = _get_plate_distance_for_indices(
				_selected_spiral_index, _selected_plate_index, target_global_position)
		var candidate_distance: float = _get_plate_distance_for_indices(
				spiral_index, plate_index, target_global_position)
		# No cambiar de plate hasta que la nueva gane por un margen claro.
		# Esto evita flips bruscos al cruzar bordes y reduce la sensación de salto.
		if candidate_distance + auto_track_min_switch_distance >= current_distance:
			return
	if continuous_tracking:
		# En modo continuous el mundo ya rota via _update_continuous_tracking.
		# Solo actualizamos los índices y el pool, sin mover el active_collision_body.
		_selected_spiral_index = spiral_index
		_selected_plate_index = plate_index
		if spiral_index >= 0 and spiral_index < _registered_platforms.size():
			_selected_plate_canonical = get_plate_canonical_transform(
					_registered_platforms[spiral_index], plate_index)
		_set_collision_plate_meta(_active_collision_body, _selected_spiral_index, _selected_plate_index)
	else:
		if _selected_spiral_index < 0 or _selected_plate_index < 0 or _active_collision_body == null:
			return
		_activate_nearest_plate_at_current_global_transform(spiral_index, plate_index)
	_force_collision_pool_reassign()

func _find_floor_contact_plate(target: Spatial) -> Dictionary:
	if not target.has_method("is_on_floor") or not target.has_method("get_slide_count") or not target.has_method("get_slide_collision"):
		return {}
	if not target.is_on_floor():
		return {}
	for i in range(target.get_slide_count()):
		var collision: KinematicCollision = target.get_slide_collision(i)
		if collision == null:
			continue
		# No filtramos por normal.dot(UP): las plates inclinadas tienen normales
		# que no apuntan a +Y global — solo verificamos que el collider sea del pool.
		var collider: Object = collision.collider
		if collider == _active_collision_body:
			return {
				"spiral_index": _selected_spiral_index,
				"plate_index": _selected_plate_index,
				"distance": 0.0
			}
		if collider is StaticBody and collider.has_meta("spiral_index") and collider.has_meta("plate_index"):
			return {
				"spiral_index": int(collider.get_meta("spiral_index")),
				"plate_index": int(collider.get_meta("plate_index")),
				"distance": 0.0
			}
	return {}

func _update_continuous_tracking(delta: float) -> void:
	var blend: float = _get_active_gravity_blend()
	if blend <= 0.001:
		return

	var target: Spatial = _get_tracking_target()
	if target == null:
		return

	# No rotar mientras el jugador está en el aire.
	# Durante el salto el mundo debe permanecer estático para que los slots del
	# pool de colisiones queden en la posición correcta de aterrizaje.
	# La rotación se retoma cuando el jugador vuelve a tocar el suelo.
	if target.has_method("is_on_floor") and not target.is_on_floor():
		_target_global_transform = global_transform
		return

	var p_global: Vector3 = target.global_transform.origin
	var p_can: Vector3 = to_canonical(p_global)

	var up_can: Vector3
	if has_node("/root/GravityWorld"):
		up_can = get_node("/root/GravityWorld").get_canonical_up_direction(p_can)
	else:
		# Fallback radial
		var radial_up := -Vector3(p_can.x, 0.0, p_can.z).normalized()
		if radial_up.length_squared() < 0.001:
			radial_up = Vector3.UP
		up_can = Vector3.UP.linear_interpolate(radial_up, blend).normalized()

	var up_global: Vector3 = global_transform.basis.xform(up_can).normalized()
	var q_align: Quat = _quat_align(up_global, Vector3.UP)

	# Evitar vibraciones por coma flotante
	if q_align.w >= 0.99999:
		return

	var new_basis: Basis = (Basis(q_align) * global_transform.basis).orthonormalized()
	# Pivotamos alrededor del jugador para que no sea desplazado bruscamente
	var new_origin: Vector3 = p_global - new_basis.xform(p_can)

	_target_global_transform = Transform(new_basis, new_origin)
	_has_transform_target = true
	# Hacemos que la interpolación no dependa solo de rotation_speed sino que fluya
	# El slerp se encargará de suavizarlo

func _get_tracking_target() -> Spatial:
	if not tracking_target_path.is_empty():
		var node: Node = get_node_or_null(tracking_target_path)
		if node == null and get_parent():
			node = get_parent().get_node_or_null(tracking_target_path)
		if node is Spatial:
			return node as Spatial
	var players: Array = get_tree().get_nodes_in_group("player") if is_inside_tree() else []
	for player in players:
		if player is Spatial and is_instance_valid(player):
			return player as Spatial
	return null

func _activate_nearest_plate_at_current_global_transform(spiral_index: int, plate_index: int) -> void:
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return
	var spiral: Spatial = _registered_platforms[spiral_index]
	var plate_count: int = get_plate_count(spiral)
	if plate_index < 0 or plate_index >= plate_count:
		return
	var plate_canonical: Transform = get_plate_canonical_transform(spiral, plate_index)
	var plate_global: Transform = global_transform * plate_canonical
	var active_body: StaticBody = _ensure_active_collision_body()
	_sync_active_collision_shape(spiral)
	active_body.global_transform = _make_horizontal_target_transform(plate_global)
	select_terrace_plate(spiral_index, plate_index, active_body, false)

func _make_horizontal_target_transform(source_global: Transform) -> Transform:
	var x_axis: Vector3 = source_global.basis.x
	x_axis.y = 0.0
	if x_axis.length_squared() <= 0.001:
		x_axis = source_global.basis.z.cross(Vector3.UP)
		x_axis.y = 0.0
	if x_axis.length_squared() <= 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = Vector3.UP
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	return Transform(Basis(x_axis, y_axis, z_axis).orthonormalized(), source_global.origin)

func _force_spiral_update(spiral: Spatial) -> void:
	if spiral == null:
		return
	if spiral.has_method("_rebuild_multimesh_if_needed"):
		spiral.call("_rebuild_multimesh_if_needed")
	if spiral.has_method("_update_spiral_animation"):
		spiral.call("_update_spiral_animation")

func _ensure_active_collision_body() -> StaticBody:
	if _active_collision_body and is_instance_valid(_active_collision_body):
		return _active_collision_body
	var configured: Node = null
	if not physical_terrace_path.is_empty():
		configured = get_node_or_null(physical_terrace_path)
		if configured == null and get_parent():
			configured = get_parent().get_node_or_null(physical_terrace_path)
	if configured is StaticBody:
		_active_collision_body = configured
		if not _active_collision_body.has_meta("world_rotator_original_collision_layer"):
			_active_collision_body.set_meta("world_rotator_original_collision_layer", _active_collision_body.collision_layer)
		_active_collision_body.set_meta("world_rotator_collision", true)
		_active_collision_body.set_meta("world_rotator_active_collision", true)
		_active_collision_shape = _find_collision_shape(_active_collision_body)
		if _active_collision_shape == null:
			_active_collision_shape = _create_collision_shape(_active_collision_body)
		return _active_collision_body

	_ensure_generated_collision_root()
	_active_collision_body = StaticBody.new()
	_active_collision_body.name = "ActiveTerraceCollision"
	_active_collision_body.collision_layer = 1
	_active_collision_body.collision_mask = 1
	_active_collision_body.set_meta("world_rotator_original_collision_layer", _active_collision_body.collision_layer)
	_active_collision_body.set_meta("world_rotator_collision", true)
	_active_collision_body.set_meta("world_rotator_active_collision", true)
	# Crear la shape ANTES de insertar en el árbol.
	_active_collision_shape = CollisionShape.new()
	_active_collision_shape.name = "CollisionShape"
	var _init_box: BoxShape = BoxShape.new()
	_init_box.extents = fallback_collision_extents
	_active_collision_shape.shape = _init_box
	_active_collision_body.add_child(_active_collision_shape)
	_get_collision_parent().add_child(_active_collision_body)
	return _active_collision_body

func _ensure_generated_collision_root() -> void:
	if _generated_collision_root and is_instance_valid(_generated_collision_root):
		return
	_generated_collision_root = Spatial.new()
	_generated_collision_root.name = "GeneratedTerraceCollisions"
	_get_collision_parent().add_child(_generated_collision_root)

# ── Pool de colisiones ───────────────────────────────────────────────────────

# Crea los StaticBodies del pool una sola vez al inicio. Sin allocs en runtime.
func _build_collision_pool() -> void:
	_ensure_generated_collision_root()
	# Limpiar pool anterior si lo hubiera (ej. cambio de collision_pool_size en editor).
	_destroy_collision_pool()
	var default_extents: Vector3 = fallback_collision_extents
	for i in range(collision_pool_size):
		var body: StaticBody = StaticBody.new()
		body.name = "PoolTerraceCollision_%d" % i
		body.collision_layer = 1
		body.collision_mask = 1
		# Metadata inicialmente vacío; se asigna en _assign_pool_to_nearest_plates.
		body.set_meta("world_rotator_collision", true)
		body.set_meta("spiral_index", -1)
		body.set_meta("plate_index", -1)
		# Añadir CollisionShape ANTES de insertar el body en el árbol.
		# Si se añade después, Godot 3 puede no registrar la shape en el physics server.
		var shape: CollisionShape = CollisionShape.new()
		shape.name = "CollisionShape"
		var box: BoxShape = BoxShape.new()
		box.extents = default_extents
		shape.shape = box
		body.add_child(shape)
		_generated_collision_root.add_child(body)
		_collision_pool.append(body)
		_pool_assignments.append({})

func _destroy_collision_pool() -> void:
	for body in _collision_pool:
		if is_instance_valid(body):
			body.queue_free()
	_collision_pool.clear()
	_pool_assignments.clear()
	_pool_force_reassign = true
	_pool_has_assignment_center = false
	_pool_assignment_selected_spiral = -1
	_pool_assignment_selected_plate = -1
	_pool_assignment_xz_scale = -1.0

# Recalcula qué plates reciben un slot del pool, ordenando por distancia al jugador.
# Solo reasigna transforms — cero allocs.
func _assign_pool_to_nearest_plates() -> void:
	if _collision_pool.empty() or _registered_platforms.empty():
		return
	var center_info: Dictionary = _get_collision_pool_center_canonical()
	if center_info.empty():
		return
	var center_canonical: Vector3 = center_info["center"]

	# Recopilar todas las plates con su distancia al centro.
	# Los transforms del multimesh se leen tal como están — el spiral los actualiza
	# en su propio _physics_process; un frame de lag es aceptable.
	var candidates: Array = []  # Array of {spiral, plate, dist_sq, canonical_tx}
	for spiral_index in range(_registered_platforms.size()):
		var spiral: Spatial = _registered_platforms[spiral_index]
		var plate_count: int = get_plate_count(spiral)
		for plate_index in range(plate_count):
			# En plate-tracking no duplicamos la plate activa porque la maneja
			# _active_collision_body. En continuous_tracking sí la incluimos:
			# PhysicalTerrace queda como ancla inicial y el pool sigue el MultiMesh.
			if not continuous_tracking and spiral_index == _selected_spiral_index and plate_index == _selected_plate_index:
				continue

			var plate_tx: Transform = get_plate_canonical_transform(spiral, plate_index)
			var dist_sq: float = _get_plate_contact_distance_squared(spiral, plate_tx, center_canonical)
			candidates.append({
				"spiral_index": spiral_index,
				"plate_index": plate_index,
				"dist_sq": dist_sq,
				"canonical_tx": plate_tx
			})

	# Ordenar por distancia ascendente y tomar las primeras collision_pool_size.
	candidates.sort_custom(self, "_sort_by_dist_sq")
	var pool_size: int = _collision_pool.size()
	var assign_count: int = min(candidates.size(), pool_size)

	for i in range(assign_count):
		var c: Dictionary = candidates[i]
		var body: StaticBody = _collision_pool[i]
		var spiral: Spatial = _registered_platforms[c.spiral_index]
		_sync_pool_shape_extents(body, spiral)
		body.set_meta("spiral_index", c.spiral_index)
		body.set_meta("plate_index", c.plate_index)
		var plate_global: Transform = global_transform * c.canonical_tx
		body.global_transform = _get_neighbor_collision_transform(plate_global)
		_pool_assignments[i] = {"spiral_index": c.spiral_index, "plate_index": c.plate_index}

	# Los slots sobrantes se mandan lejos para que no interfieran.
	var far_away: Transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for i in range(assign_count, pool_size):
		_collision_pool[i].global_transform = far_away
		_pool_assignments[i] = {}

	_pool_assignment_center_canonical = center_canonical
	_pool_has_assignment_center = true
	_pool_assignment_selected_spiral = _selected_spiral_index
	_pool_assignment_selected_plate = _selected_plate_index
	_pool_assignment_xz_scale = collision_pool_xz_scale
	_pool_force_reassign = false

func _force_collision_pool_reassign() -> void:
	_pool_force_reassign = true
	_pool_update_counter = collision_update_interval

func _get_collision_pool_center_canonical() -> Dictionary:
	var tracking_target: Spatial = _get_tracking_target()
	if tracking_target != null:
		return {"center": to_canonical(tracking_target.global_transform.origin)}
	if _selected_plate_index >= 0:
		return {"center": _selected_plate_canonical.origin}
	return {}

func _should_reassign_collision_pool() -> bool:
	if _collision_pool.empty() or _registered_platforms.empty():
		return false
	var center_info: Dictionary = _get_collision_pool_center_canonical()
	if center_info.empty():
		return false
	if _pool_force_reassign or not _pool_has_assignment_center:
		return true
	if _pool_assignment_selected_spiral != _selected_spiral_index:
		return true
	if _pool_assignment_selected_plate != _selected_plate_index:
		return true
	if not is_equal_approx(_pool_assignment_xz_scale, collision_pool_xz_scale):
		return true
	if collision_reassign_min_distance <= 0.0:
		return true
	var center_canonical: Vector3 = center_info["center"]
	var min_dist_sq: float = collision_reassign_min_distance * collision_reassign_min_distance
	return center_canonical.distance_squared_to(_pool_assignment_center_canonical) >= min_dist_sq

func _sort_by_dist_sq(a: Dictionary, b: Dictionary) -> bool:
	return a.dist_sq < b.dist_sq

func _sync_assigned_pool_transforms() -> void:
	if _collision_pool.empty() or _registered_platforms.empty():
		return
	for i in range(_collision_pool.size()):
		if i >= _pool_assignments.size():
			return
		var assignment: Dictionary = _pool_assignments[i]
		if assignment.empty():
			continue
		var spiral_index: int = int(assignment.get("spiral_index", -1))
		var plate_index: int = int(assignment.get("plate_index", -1))
		if spiral_index < 0 or spiral_index >= _registered_platforms.size():
			continue
		var spiral: Spatial = _registered_platforms[spiral_index]
		var plate_count: int = get_plate_count(spiral)
		if plate_index < 0 or plate_index >= plate_count:
			continue
		var body: StaticBody = _collision_pool[i]
		if body == null or not is_instance_valid(body):
			continue
		var plate_tx: Transform = get_plate_canonical_transform(spiral, plate_index)
		body.global_transform = _get_neighbor_collision_transform(global_transform * plate_tx)
		_set_collision_plate_meta(body, spiral_index, plate_index)

func _set_collision_plate_meta(body: StaticBody, spiral_index: int, plate_index: int) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.set_meta("world_rotator_collision", true)
	body.set_meta("spiral_index", spiral_index)
	body.set_meta("plate_index", plate_index)

func _update_active_collision_layer_for_mode() -> void:
	if _active_collision_body == null or not is_instance_valid(_active_collision_body):
		return
	if not _active_collision_body.has_meta("world_rotator_original_collision_layer"):
		_active_collision_body.set_meta("world_rotator_original_collision_layer", _active_collision_body.collision_layer)
	if continuous_tracking:
		_active_collision_body.collision_layer = 0
	else:
		_active_collision_body.collision_layer = int(_active_collision_body.get_meta("world_rotator_original_collision_layer"))

func _get_neighbor_collision_transform(plate_global: Transform) -> Transform:
	# Las terrazas vecinas deben coincidir con el mesh visual real para que
	# el paso entre plates no encuentre un collider desplazado o desfasado.
	return plate_global

func _sync_pool_shape_extents(body: StaticBody, spiral: Spatial) -> void:
	var shape_node: CollisionShape = body.get_node_or_null("CollisionShape") as CollisionShape
	if shape_node == null:
		return
	var box: BoxShape = shape_node.shape as BoxShape
	if box == null:
		return
	var e: Vector3 = _get_plate_collision_extents(spiral)
	box.extents = Vector3(e.x * collision_pool_xz_scale, e.y, e.z * collision_pool_xz_scale)

func _get_collision_parent() -> Node:
	if get_parent():
		return get_parent()
	return self

func _find_collision_shape(root: Node) -> CollisionShape:
	for child in root.get_children():
		if child is CollisionShape:
			return child
	return null

func _create_collision_shape(parent: Node) -> CollisionShape:
	var collision_shape: CollisionShape = CollisionShape.new()
	collision_shape.name = "CollisionShape"
	var box: BoxShape = BoxShape.new()
	box.extents = fallback_collision_extents
	collision_shape.shape = box
	parent.add_child(collision_shape)
	return collision_shape

func _sync_active_collision_shape(spiral: Spatial) -> void:
	if _active_collision_shape == null:
		return
	var box: BoxShape = _active_collision_shape.shape as BoxShape
	if box == null:
		box = BoxShape.new()
		_active_collision_shape.shape = box
	box.extents = _get_plate_collision_extents(spiral)

func _configure_gravity_for_selected_plate(plate_canonical: Transform) -> void:
	if not configure_gravity_from_selection:
		return
	if not has_node("/root/GravityWorld"):
		return
	var gravity_world: Node = get_node("/root/GravityWorld")
	if gravity_world.has_method("get_axis_radius"):
		var radius: float = gravity_world.get_axis_radius(plate_canonical.origin)
		if gravity_world.has_method("set_centrifugal_reference_radius"):
			gravity_world.set_centrifugal_reference_radius(radius)
		if gravity_world.has_method("get_default_angular_velocity_for_one_g") and gravity_world.has_method("set_ship_angular_velocity"):
			gravity_world.set_ship_angular_velocity(gravity_world.get_default_angular_velocity_for_one_g(radius))

func _get_active_gravity_blend() -> float:
	var local_blend: float = clamp(spiral_blend, 0.0, 1.0)
	if has_node("/root/GravityWorld") and get_node("/root/GravityWorld").has_method("get_gravity_blend"):
		return max(local_blend, clamp(float(get_node("/root/GravityWorld").get_gravity_blend()), 0.0, 1.0))
	return local_blend

func _get_plate_collision_extents(spiral: Spatial) -> Vector3:
	var mesh: Mesh = spiral.get("plate_mesh")
	if mesh == null:
		var multimesh: MultiMesh = spiral.get("multimesh")
		if multimesh:
			mesh = multimesh.mesh
	if mesh is CubeMesh:
		return (mesh as CubeMesh).size * 0.5
	return fallback_collision_extents

# Eliminado: _rebuild_generated_collision_proxies, _create_generated_collision_proxy,
# _sync_generated_collision_transforms, _has_generated_proxy, _is_plate_near_selected_collision.
# Reemplazados por el pool fijo: _build_collision_pool / _assign_pool_to_nearest_plates.

func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped: int = value % size
	if wrapped < 0:
		wrapped += size
	return wrapped

func _is_pool_update_due() -> bool:
	if _has_transform_target and not continuous_tracking:
		var distance: float = global_transform.origin.distance_to(_target_global_transform.origin)
		if distance > 0.05:
			return true
		var q_cur_global: Quat = global_transform.basis.get_rotation_quat()
		var q_target_global: Quat = _target_global_transform.basis.get_rotation_quat()
		return abs(q_cur_global.dot(q_target_global)) < 0.9999
	if _platform_node == null:
		return false
	var q_cur: Quat = transform.basis.get_rotation_quat()
	var q_target: Quat = _target_quat
	return abs(q_cur.dot(q_target)) < 0.9999

# ── Utilidades de álgebra ────────────────────────────────────────────────────

# Devuelve el Quaternion mínimo que rota 'from_up' para alinearlo con 'to_up'.
func _quat_align(from_up: Vector3, to_up: Vector3) -> Quat:
	from_up = from_up.normalized()
	to_up = to_up.normalized()
	var d: float = from_up.dot(to_up)
	if d >= 1.0 - 1e-6:
		return Quat()
	if d <= -1.0 + 1e-6:
		# 180° — necesita un eje arbitrario perpendicular
		var perp: Vector3 = from_up.cross(Vector3.RIGHT)
		if perp.length_squared() < 1e-6:
			perp = from_up.cross(Vector3.BACK)
		return Quat(perp.normalized(), PI)
	var axis: Vector3 = from_up.cross(to_up).normalized()
	var angle: float = from_up.angle_to(to_up)
	return Quat(axis, angle)

func _is_child_of_self(node: Node) -> bool:
	var p: Node = node.get_parent()
	while p != null:
		if p == self:
			return true
		p = p.get_parent()
	return false

func _path_to(node: Node) -> NodePath:
	if node.is_inside_tree() and is_inside_tree():
		return get_path_to(node)
	return NodePath("")
