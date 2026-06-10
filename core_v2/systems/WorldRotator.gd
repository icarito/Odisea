extends Spatial
tool
class_name WorldRotator

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

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
# Factor de velocidad de rotación cuando el jugador está en el aire (0.0 a 1.0).
export(float, 0.0, 1.0) var airborne_rotation_factor := 0.3
export(int, "STANDARD_1G", "SPIN_WALKABLE", "ZERO_G", "SPIN_DYNAMIC") var gravity_mode := GravityModes.Mode.SPIN_WALKABLE
export(bool) var rotation_frozen := false
export(bool) var debug_draw_target_basis := false

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
export(bool) var select_nearest_plate_on_ready := false
export(bool) var snap_initial_selection := true

# Colisiones físicas generadas para probar/usar terrazas sin authoring manual.
export(NodePath) var physical_terrace_path := NodePath("")
export(Vector3) var fallback_collision_extents := Vector3(100.0, 1.0, 100.0)
export(bool) var auto_track_target_plate := false
export(NodePath) var tracking_target_path := NodePath("")
export(float) var auto_track_min_switch_distance := 20.0
export(bool) var auto_track_requires_floor_contact := true
export(int, 1, 30) var target_plate_query_interval := 3
# Cooldown (physics frames) after an active-plate switch during which no further
# switch is allowed. Breaks the feedback loop where, standing on the overlap of
# two plates from different spirals, each switch reorients the world and makes
# the other plate look closer next frame — plates flip every few frames and the
# full-detail dome flickers (Full-Detail↔LOD snap loop) on the grounded player.
export(int, 0, 120) var auto_track_switch_cooldown_frames := 20
export(bool) var continuous_tracking := true
# Eje del cilindro para el fallback radial (cuando no hay GravityWorld).
# 0 = Y (por defecto, OdiseaExterior: ring cierra en XZ)
# 1 = X (SGC: ring cierra en YZ)
# 2 = Z (ring cierra en XY)
export(int, "Y_AXIS", "X_AXIS", "Z_AXIS") var cylinder_axis := 0
# Origen canónico del cilindro usado por el fallback radial.
# Permite cilindros cuyo centro no está en (0,0,0), como ScaffoldOrbit
# donde el anillo queda centrado en Y = base_radius.
export(Vector3) var cylinder_radial_origin := Vector3.ZERO
export(NodePath) var scene_anchor_content_path := NodePath("") setget _set_scene_anchor_content_path
export(NodePath) var scene_anchor_reference_path := NodePath("") setget _set_scene_anchor_reference_path

export(bool) var enable_faux_skydome := false setget _set_enable_faux_skydome
export(bool) var enable_segment_lod := false
export(bool) var enable_terrace_distance_culling := OS.has_feature("HTML5")
export(float) var terrace_culling_max_distance := 800.0
export(float) var terrace_culling_safe_radius := 60.0
export(int) var terrace_culling_update_interval := 50
export(int) var scene_anchor_spiral_index := -1 setget _set_scene_anchor_spiral_index
export(int) var scene_anchor_plate_index := -1 setget _set_scene_anchor_plate_index
export(bool) var scene_anchor_use_selected_plate_on_ready := false
export(Vector3) var scene_anchor_offset := Vector3.ZERO setget _set_scene_anchor_offset
export(bool) var scene_anchor_restore_in_flat_mode := true

# Pool fijo de StaticBodies reutilizables para colisiones de terrazas.
# En lugar de crear/destruir objetos al cambiar de plate, se reasignan los
# transforms del pool a las N plates más cercanas al jugador cada frame.
# Un tamaño de 32 cubre ~8 plates por espiral en el entorno inmediato.
export(int, 4, 128) var collision_pool_size := 32
# Cada cuántos physics frames se recalcula la asignación del pool.
# 1 = cada frame (máxima precisión), 6 = cada 6 frames (~10 Hz a 60 Hz).
export(int, 1, 30) var collision_update_interval := 3
# Factor de escala en XZ para los BoxShape del pool.
# El mesh de las plates es 200x2x200 -> extents = (100,1,100).
# En modo centrífugo las plates vecinas están a ~249 unidades de distancia XZ,
# dejando un hueco de 49u entre boxes. Escalar a 1.3 da extents=130 -> solape.
export(float, 1.0, 3.0) var collision_pool_xz_scale := 1.3
export(bool) var warn_on_physics_children := true
# En centrifugo, solo el PhysicalTerrace/ActiveTerraceCollision representa el
# plate actual. El pool queda como mecanismo legacy para modos no centrifugos.
export(bool) var centrifugal_current_plate_only_physics := true

# ── Estado interno ──────────────────────────────────────────────────────────

var _platform_node: Spatial = null
var _target_quat := Quat()
var _has_transform_target := false
var _target_global_transform := Transform.IDENTITY
var _is_transitioning := false
var _registered_platforms: Array = []  # Array[Spatial]
var _selected_spiral_index := -1
var _selected_plate_index := -1
var _selected_plate_canonical := Transform.IDENTITY
var _active_collision_body: StaticBody = null
var _active_collision_shape: CollisionShape = null
var _generated_collision_root: Spatial = null
var _scene_anchor_content_node: Spatial = null
var _scene_anchor_reference_node: Spatial = null
var _scene_anchor_content_canonical := Transform.IDENTITY
var _scene_anchor_reference_canonical := Transform.IDENTITY
var _scene_anchor_cached := false
var _scene_anchor_resolved_spiral_index := -1
var _scene_anchor_resolved_plate_index := -1
# Pool fijo: cada slot es un StaticBody pre-creado con BoxShape.
# _pool_assignments[i] = {"spiral": int, "plate": int} o {} si el slot está libre.
var _collision_pool: Array = []        # Array[StaticBody]
var _pool_assignments: Array = []      # Array[Dictionary]
var _pool_update_counter: int = 0
var _spiral_extents_cache: Dictionary = {}  # spiral_index (int) -> Vector3
var _target_plate_query_counter: int = 0
var _switch_cooldown_left: int = 0  # frames remaining before another plate switch is allowed
var _cached_tracking_target: Spatial = null  # cache por frame: evita get_nodes_in_group repetido
var _world_environment_sky_entries: Array = []
var _sky_frame_sync_counter: int = 0
var _sky_frame_sync_interval: int = 6
var _last_sky_basis := Basis.IDENTITY
var _startup_snap_done := false  # snap to target on first physics frame, then slerp
# Airlock transitions: while the player sits in the airlock chamber the world
# tracking is paused so it does not accumulate rotation that would snap in. When
# the player finally exits the destination airlock chamber, tracking resumes and
# eases the accumulated rotation over RESUME_TRACKING_DURATION seconds.
const RESUME_TRACKING_DURATION := 0.3
# Verified via telemetry 2026-06-10:
# S0(TerraceSpiral, 15deg) -> S1(195deg) offset=9, S2(105deg) offset=4, S3(285deg) offset=13
const INTERLOCK_OFFSETS := [0, 9, 4, 13]
var _tracking_paused := false
var _resume_ramp_left := 0.0  # >0 while easing back into tracking after a resume
var _terrace_culling_counter: int = 0
var _culling_target: Spatial = null
# Retrocompatibilidad: alias del pool para tests que lean _generated_collision_bodies
var _generated_collision_bodies: Array setget ,_get_generated_collision_bodies
func _get_generated_collision_bodies() -> Array:
	return _collision_pool

# ── Ciclo de vida ────────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.editor_hint:
		set_physics_process(false)
		set_process(false)
		return
	# Reset to identity so editor-saved runtime transforms don't corrupt canonical calculations.
	global_transform = Transform.IDENTITY
	_cache_world_environment_sky_frames()
	_sync_world_environment_sky_frames()
	_sync_faux_skydome_visibility()
	_configure_terrace_culling_for_platform()
	# Also reset PhysicalTerrace if configured — it may have been dirtied by the editor too.
	var pt: Spatial = _resolve_physical_terrace_target()
	if pt:
		pt.global_transform = Transform.IDENTITY
		if pt is StaticBody:
			_active_collision_body = pt as StaticBody
			_active_collision_shape = _find_collision_shape(_active_collision_body)
			if _active_collision_shape == null:
				_active_collision_shape = _create_collision_shape(_active_collision_body)
	_cache_scene_anchor_transforms()
	_auto_register_platforms()
	if not current_platform.is_empty():
		_platform_node = get_node_or_null(current_platform) as Spatial
	elif auto_select_first_platform and not _registered_platforms.empty():
		_platform_node = _registered_platforms[0]
		current_platform = _path_to(_platform_node)
	_recompute_target()
	_sync_spirals()
	_warn_about_physics_children()
	call_deferred("_build_collision_pool")
	call_deferred("_select_nearest_plate_on_ready_if_enabled")
	call_deferred("_apply_scene_anchor_after_ready")
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").register_rotator(self)

func _exit_tree() -> void:
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").unregister_rotator(self)
	_destroy_collision_pool()


func _set_enable_faux_skydome(value: bool) -> void:
	enable_faux_skydome = value
	if is_inside_tree():
		_sync_faux_skydome_visibility()


func _sync_faux_skydome_visibility() -> void:
	for child in get_children():
		if child.name == "FauxSkydome" or child is FauxSkydomeParallaxShell:
			child.visible = enable_faux_skydome

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	# While the player is inside the airlock chamber, stop following the player and
	# lock the world flat relative to the active terrace (the selected plate's up
	# aligned with +Y) over RESUME_TRACKING_DURATION. This keeps the centrifugal
	# alignment intact but stops chasing the player's radial position, so there is
	# no accumulated rotation to snap in when transitioning or walking back out.
	if _tracking_paused:
		_slerp_to_flat_while_paused(delta)
		return
	# Resolver tracking target una sola vez por frame para evitar get_nodes_in_group repetido.
	_cached_tracking_target = _get_tracking_target()
	var continuous_tracking_applied: bool = false
	if continuous_tracking:
		continuous_tracking_applied = _update_continuous_tracking(delta)
	# El tracking por plates corre siempre: detecta cambio de plate activa
	# independientemente de si continuous_tracking está activo o no.
	_update_tracked_target_plate()

	if continuous_tracking_applied:
		_is_transitioning = false
	elif _has_transform_target:
		_slerp_to_global_transform(delta)
	else:
		_slerp_to_target(delta)

	# En modo continuous_tracking el active_collision_body sigue al visual rotado.
	# En modo plate-tracking es ancla fija — NO se mueve aquí.
	if continuous_tracking and _active_collision_body and is_instance_valid(_active_collision_body) \
			and _selected_spiral_index >= 0 and _selected_plate_index >= 0:
		_active_collision_body.global_transform = global_transform * _selected_plate_canonical

	var pool_update_due: bool = false if continuous_tracking_applied else _is_pool_update_due()
	if not pool_update_due:
		_pool_update_counter += 1
		pool_update_due = _pool_update_counter >= collision_update_interval
	if pool_update_due:
		_pool_update_counter = 0
		_assign_pool_to_nearest_plates()
	_sky_frame_sync_counter += 1
	if _sky_frame_sync_counter >= _sky_frame_sync_interval:
		_sky_frame_sync_counter = 0
		_sync_world_environment_sky_frames()
	if enable_terrace_distance_culling and not _registered_platforms.empty():
		_terrace_culling_counter += 1
		if _terrace_culling_counter >= terrace_culling_update_interval:
			_terrace_culling_counter = 0
			_apply_terrace_distance_culling()

# ── API pública ──────────────────────────────────────────────────────────────

# Cambia la plataforma activa. WorldRotator comenzará a rotar hacia el gravity frame del nodo.
# 'node' puede ser cualquier Spatial — su eje local +Y define la dirección "arriba".
func set_active_platform(node: Spatial, snap_immediately: bool = false) -> void:
	_has_transform_target = false
	if node == null:
		_platform_node = null
		current_platform = NodePath("")
		_recompute_target()
		emit_signal("platform_changed", null)
		return
	_platform_node = node
	current_platform = _path_to(node)
	if not Engine.editor_hint:
		_recompute_target()
		if snap_immediately:
			transform.basis = Basis(_target_quat).orthonormalized()
			_is_transitioning = false
			_sync_world_environment_sky_frames()
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

# Registra el canonical transform de la plataforma activa desde un sistema externo
# (p.ej. SGCPlatformBridge). Permite que continuous_tracking mueva el collision body
# sin necesitar un TerraceSpiral registrado.
func set_active_canonical(canonical: Transform) -> void:
	_selected_plate_canonical = canonical
	_selected_spiral_index = 0   # dummy value ≥ 0 to enable collision body sync
	_selected_plate_index  = 0

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
	if Engine.editor_hint:
		return
	_has_transform_target = true
	_platform_node = null
	current_platform = NodePath("")
	_target_global_transform = target_global_transform * canonical_transform.affine_inverse()
	if snap_immediately:
		global_transform = _target_global_transform
		_sync_world_environment_sky_frames()

# Selecciona una plate de TerraceSpiral, reencuadra el mundo para que coincida
# con una terraza física estable y genera colisiones equivalentes para plates vecinas.
func select_terrace_plate(spiral_index: int, plate_index: int, target_body: Spatial = null, snap_immediately: bool = false) -> bool:
	if Engine.editor_hint:
		return false
	_auto_register_platforms()
	_sync_spirals()
	if _registered_platforms.empty():
		return false
	_selected_spiral_index = _wrap_index(spiral_index, _registered_platforms.size())
	var spiral: Spatial = _registered_platforms[_selected_spiral_index]
	_force_spiral_update(spiral)
	var plate_count: int = get_plate_count(spiral)
	if plate_count <= 0:
		return false
	_selected_plate_index = clamp(plate_index, 0, plate_count - 1)
	_selected_plate_canonical = get_plate_canonical_transform(spiral, _selected_plate_index)

	if target_body == null:
		target_body = _ensure_active_collision_body()
	else:
		_active_collision_body = target_body as StaticBody
		if _active_collision_body:
			_active_collision_shape = _find_collision_shape(_active_collision_body)
			if _active_collision_shape == null:
				_active_collision_shape = _create_collision_shape(_active_collision_body)

	_sync_active_collision_shape(spiral)
	align_canonical_transform_to_global(_selected_plate_canonical, target_body.global_transform, snap_immediately)
	# Forzar reasignación inmediata del pool al nuevo centro.
	_pool_update_counter = collision_update_interval
	return true

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

func get_physics_child_violations() -> Array:
	var violations: Array = []
	_collect_physics_child_violations(self, violations)
	return violations

func get_selected_spiral_index() -> int:
	return _selected_spiral_index

func get_selected_plate_index() -> int:
	return _selected_plate_index

func is_transitioning() -> bool:
	return _is_transitioning

func get_target_basis() -> Basis:
	if _has_transform_target:
		return _target_global_transform.basis
	return Basis(_target_quat).orthonormalized()

func set_rotation_frozen(frozen: bool) -> void:
	rotation_frozen = frozen

# Airlock support: stop following the player and lock the world flat relative to
# the active terrace. Called when the player enters an airlock chamber from the
# exterior (and while held across the scene swap). The world eases to the active
# plate's gravity frame over RESUME_TRACKING_DURATION and then holds, so no
# accumulated radial rotation snaps in later.
func pause_tracking() -> void:
	if _tracking_paused:
		return
	_tracking_paused = true
	_resume_ramp_left = RESUME_TRACKING_DURATION
	_is_transitioning = false

# Airlock support: resume tracking once the player exits the airlock chamber.
# Eases the rotation accumulated during the pause over RESUME_TRACKING_DURATION
# seconds (slerp, not snap) so there is no visible yank on the first frame.
func resume_tracking() -> void:
	if not _tracking_paused and _resume_ramp_left <= 0.0:
		return
	_tracking_paused = false
	_resume_ramp_left = RESUME_TRACKING_DURATION

func is_tracking_paused() -> bool:
	return _tracking_paused

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

	# Optimización: usar transform cacheado si está disponible
	var local_xform: Transform
	var cached_list = spiral.get("_cached_transforms")
	if cached_list != null and cached_list is Array and clamped_index < cached_list.size():
		local_xform = cached_list[clamped_index]
	else:
		local_xform = multimesh.get_instance_transform(clamped_index)

	var spiral_canonical: Transform = global_transform.affine_inverse() * spiral.global_transform
	return spiral_canonical * local_xform

func find_nearest_terrace_plate(global_position: Vector3) -> Dictionary:
	_ensure_registered_platforms()
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

func _get_plate_dist_sq_for_indices(spiral_index: int, plate_index: int, canonical_position: Vector3) -> float:
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return INF
	var spiral: Spatial = _registered_platforms[spiral_index]
	var plate_count: int = get_plate_count(spiral)
	if plate_index < 0 or plate_index >= plate_count:
		return INF
	var plate_tx: Transform = get_plate_canonical_transform(spiral, plate_index)
	return plate_tx.origin.distance_squared_to(canonical_position)

# Busca la plate más cercana dentro de la franja _selected_plate_index ± strip_radius
# en todas las espirales. No usa sqrt ni itera plates lejanas.
func _find_nearest_plate_in_strip(canonical_position: Vector3, strip_radius: int) -> Dictionary:
	if _registered_platforms.empty() or _selected_plate_index < 0:
		return {}
	var rotator_inv := global_transform.affine_inverse()
	var best := {}
	var best_dist_sq := INF
	for spiral_index in range(_registered_platforms.size()):
		var spiral: Spatial = _registered_platforms[spiral_index]
		var plate_count: int = get_plate_count(spiral)
		if plate_count <= 0:
			continue
		var spiral_canonical_base: Transform = rotator_inv * spiral.global_transform
		var cached_list = spiral.get("_cached_transforms")
		var has_cache: bool = cached_list != null and cached_list is Array
		var multimesh: MultiMesh = null if has_cache else spiral.get("multimesh")
		for offset in range(-strip_radius, strip_radius + 1):
			var plate_index: int = _wrap_index(_selected_plate_index + offset, plate_count)
			var local_xform: Transform
			if has_cache and plate_index < cached_list.size():
				local_xform = cached_list[plate_index]
			elif multimesh != null and multimesh.instance_count > 0:
				local_xform = multimesh.get_instance_transform(plate_index)
			else:
				continue
			var plate_origin: Vector3 = (spiral_canonical_base * local_xform).origin
			var dist_sq: float = plate_origin.distance_squared_to(canonical_position)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best = {"spiral_index": spiral_index, "plate_index": plate_index, "dist_sq": dist_sq}
	return best

# Fuerza la recomputación del target (útil si la plataforma cambió su orientación).
func invalidate_target() -> void:
	_recompute_target()

# ── Setters de propiedades exportadas ────────────────────────────────────────

func _set_current_platform_path(path: NodePath) -> void:
	current_platform = path
	if is_inside_tree():
		if path.is_empty():
			_platform_node = null
			if not Engine.editor_hint:
				_recompute_target()
			return
		var node = get_node_or_null(path) as Spatial
		if node:
			_platform_node = node
			if not Engine.editor_hint:
				_recompute_target()

func _set_spiral_blend(value: float) -> void:
	var was_centrifugal: bool = spiral_blend > 0.001
	spiral_blend = clamp(value, 0.0, 1.0)
	if is_inside_tree():
		_sync_spirals()
		if Engine.editor_hint:
			return
		_apply_scene_anchor()
		var is_centrifugal: bool = spiral_blend > 0.001
		if not is_centrifugal:
			_clear_selected_plate_for_flat_mode()
		elif not was_centrifugal or _selected_spiral_index < 0 or _selected_plate_index < 0:
			call_deferred("_select_nearest_tracking_plate", snap_initial_selection)

func _set_scene_anchor_content_path(path: NodePath) -> void:
	scene_anchor_content_path = path
	_reset_scene_anchor_cache()
	if is_inside_tree() and not Engine.editor_hint:
		_apply_scene_anchor_after_ready()

func _set_scene_anchor_reference_path(path: NodePath) -> void:
	scene_anchor_reference_path = path
	_reset_scene_anchor_cache()
	if is_inside_tree() and not Engine.editor_hint:
		_apply_scene_anchor_after_ready()

func _set_scene_anchor_spiral_index(value: int) -> void:
	scene_anchor_spiral_index = value
	_reset_scene_anchor_resolution()
	if is_inside_tree() and not Engine.editor_hint:
		_apply_scene_anchor()

func _set_scene_anchor_plate_index(value: int) -> void:
	scene_anchor_plate_index = value
	_reset_scene_anchor_resolution()
	if is_inside_tree() and not Engine.editor_hint:
		_apply_scene_anchor()

func _set_scene_anchor_offset(value: Vector3) -> void:
	scene_anchor_offset = value
	if is_inside_tree() and not Engine.editor_hint:
		_apply_scene_anchor()

# ── Implementación ───────────────────────────────────────────────────────────

func _auto_register_platforms() -> void:
	_registered_platforms.clear()
	_register_platforms_recursive(self)

func _ensure_registered_platforms() -> void:
	if _registered_platforms.empty():
		_auto_register_platforms()

func _warn_about_physics_children() -> void:
	if not warn_on_physics_children:
		return
	var violations: Array = get_physics_child_violations()
	if violations.empty():
		return
	var max_reported: int = min(violations.size(), 12)
	var shown: Array = violations.slice(0, max_reported - 1)
	push_warning("[WorldRotator] Physics gameplay nodes found under WorldRotator. Move them to PlateContentStream slots: %s%s" % [
		str(shown),
		" ..." if violations.size() > max_reported else ""
	])

func _collect_physics_child_violations(root: Node, out: Array) -> void:
	for child in root.get_children():
		if _is_forbidden_physics_child(child):
			out.append(str(get_path_to(child)) if child.is_inside_tree() and is_inside_tree() else child.name)
		_collect_physics_child_violations(child, out)

func _is_forbidden_physics_child(node: Node) -> bool:
	if node == self:
		return false
	if node is PhysicsBody:
		return true
	if node is Area:
		return true
	if node is CollisionShape:
		return true
	return false

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
	if Engine.editor_hint:
		_is_transitioning = false
		return
	if rotation_frozen:
		_is_transitioning = false
		return
	if not _startup_snap_done:
		_startup_snap_done = true
		transform.basis = Basis(_target_quat).orthonormalized()
		_is_transitioning = false
		return
	var q_cur: Quat = transform.basis.get_rotation_quat()
	var t: float = min(1.0, _get_effective_rotation_speed() * delta)
	# Aplicar smoothstep para una aceleración/deceleración más natural en micro-movimientos.
	var eased_t: float = t * t * (3.0 - 2.0 * t)
	var q_new: Quat = q_cur.slerp(_target_quat, eased_t)
	transform.basis = Basis(q_new).orthonormalized()
	_is_transitioning = abs(q_new.dot(_target_quat)) < 0.9999

func _slerp_to_global_transform(delta: float) -> void:
	if Engine.editor_hint:
		_is_transitioning = false
		return
	if rotation_frozen:
		_is_transitioning = false
		return
	if not _startup_snap_done:
		_startup_snap_done = true
		global_transform = _target_global_transform
		_is_transitioning = false
		return
	var t: float = min(1.0, _get_effective_rotation_speed() * delta)
	var eased_t: float = t * t * (3.0 - 2.0 * t)
	var current: Transform = global_transform
	var q_cur: Quat = current.basis.get_rotation_quat()
	var q_target: Quat = _target_global_transform.basis.get_rotation_quat()
	var q_new: Quat = q_cur.slerp(q_target, eased_t)
	var origin_new: Vector3 = current.origin.linear_interpolate(_target_global_transform.origin, eased_t)
	global_transform = Transform(Basis(q_new).orthonormalized(), origin_new)
	_is_transitioning = abs(q_new.dot(q_target)) < 0.9999 or origin_new.distance_to(_target_global_transform.origin) > 0.01

# While the player is in the airlock chamber, stop following the player and ease
# the world to "flat relative to the active terrace": the orientation where the
# selected plate's up axis is aligned with +Y. This is NOT global identity — in
# the centrifugal exterior that would flatten the whole scene out of alignment.
# It simply locks the world to the current plate's gravity frame and stops
# chasing the player's radial position while they move inside the chamber.
# Pivots around the player so they are not displaced as the rotation settles.
func _slerp_to_flat_while_paused(delta: float) -> void:
	_is_transitioning = false
	if Engine.editor_hint or rotation_frozen:
		return
	var target_basis: Basis = _compute_active_plate_flat_basis()
	var current: Transform = global_transform
	var q_cur: Quat = current.basis.get_rotation_quat()
	var q_target: Quat = target_basis.get_rotation_quat()
	if abs(q_cur.dot(q_target)) >= 0.99999:
		return  # already aligned to the active plate's gravity frame
	var slerp_rate: float = 1.0 / RESUME_TRACKING_DURATION
	if _resume_ramp_left > 0.0:
		_resume_ramp_left = max(0.0, _resume_ramp_left - delta)
	var t: float = min(1.0, slerp_rate * delta)
	var eased_t: float = t * t * (3.0 - 2.0 * t)
	var q_new: Quat = q_cur.slerp(q_target, eased_t)
	var new_basis := Basis(q_new).orthonormalized()
	# Pivot around the player (if resolvable) so the settle doesn't displace them.
	var player: Spatial = _get_tracking_target_ignoring_suspension()
	var new_origin: Vector3
	if player and is_instance_valid(player):
		var pivot_global: Vector3 = player.global_transform.origin
		var pivot_can: Vector3 = current.affine_inverse().xform(pivot_global)
		new_origin = pivot_global - new_basis.xform(pivot_can)
	else:
		new_origin = current.origin
	global_transform = Transform(new_basis, new_origin)
	_sync_world_environment_sky_frames()

# Returns the global basis that aligns the active plate's canonical up with +Y,
# leaving the world "flat" relative to the terrace the player is standing on.
# Falls back to the current basis when there is no selected plate.
func _compute_active_plate_flat_basis() -> Basis:
	if _selected_spiral_index < 0 or _selected_plate_index < 0:
		return global_transform.basis
	# Canonical up of the active plate, expressed in global space at the current
	# rotation, then realigned so it points straight up.
	var up_can: Vector3 = _selected_plate_canonical.basis.y.normalized()
	if up_can.length_squared() < 0.0001:
		return global_transform.basis
	var up_global: Vector3 = global_transform.basis.xform(up_can).normalized()
	var q_align: Quat = _quat_align(up_global, Vector3.UP)
	return (Basis(q_align) * global_transform.basis).orthonormalized()

func _get_effective_rotation_speed(target: Spatial = null) -> float:
	var speed = rotation_speed
	if target == null:
		target = _cached_tracking_target if _cached_tracking_target != null else _get_tracking_target()
	if target and target.has_method("is_on_floor") and not target.is_on_floor():
		speed *= airborne_rotation_factor
	return speed

func _cache_world_environment_sky_frames() -> void:
	_world_environment_sky_entries.clear()
	_collect_world_environment_sky_frames(self)

func _collect_world_environment_sky_frames(root: Node) -> void:
	for child in root.get_children():
		if child is WorldEnvironment:
			var world_environment := child as WorldEnvironment
			if world_environment.environment != null:
				var runtime_environment: Environment = world_environment.environment.duplicate(true)
				world_environment.environment = runtime_environment
				_world_environment_sky_entries.append({
					"world_environment": world_environment,
					"environment": runtime_environment,
					"authored_orientation": runtime_environment.background_sky_orientation
				})
		_collect_world_environment_sky_frames(child)

func _sync_world_environment_sky_frames() -> void:
	for entry in _world_environment_sky_entries:
		var world_environment: WorldEnvironment = entry.get("world_environment", null)
		var environment: Environment = entry.get("environment", null)
		if not is_instance_valid(world_environment) or environment == null:
			continue
		environment.background_sky_orientation = global_transform.basis * entry.get("authored_orientation", Basis.IDENTITY)

func _sync_spirals() -> void:
	_sync_spirals_recursive(self)

func _sync_spirals_recursive(root: Node) -> void:
	for child in root.get_children():
		if child.get_script() != null and child.get_script().resource_path.get_file() == "TerraceSpiral.gd":
			child.animate = false
			child.manual_blend = spiral_blend
		_sync_spirals_recursive(child)

func _update_tracked_target_plate() -> void:
	if not auto_track_target_plate:
		return
	if spiral_blend <= 0.001 and centrifugal_current_plate_only_physics:
		return
	var target: Spatial = _cached_tracking_target
	if target == null:
		return
	# Cooldown: after a switch, hold the current plate for a few frames so the
	# world has time to settle before reconsidering — breaks the flip-flop between
	# two equidistant plates from different spirals.
	if _switch_cooldown_left > 0:
		_switch_cooldown_left -= 1
		if _selected_spiral_index >= 0 and _selected_plate_index >= 0:
			return
	var target_plate: Dictionary = _find_floor_contact_plate(target)
	var candidate_dist_sq := INF
	if target_plate.empty():
		if auto_track_requires_floor_contact \
				and target.has_method("is_on_floor") \
				and not _should_track_without_floor_contact_for_current_plate_only_physics():
			return
		if _selected_spiral_index >= 0 and _selected_plate_index >= 0 and target_plate_query_interval > 1:
			_target_plate_query_counter += 1
			if _target_plate_query_counter < target_plate_query_interval:
				return
		_target_plate_query_counter = 0
		# Búsqueda rápida por franja cuando ya hay plate seleccionada: ±5 por espiral, sin sqrt.
		# Fallback a búsqueda completa solo al inicio o si la franja no cubre la posición.
		if _selected_spiral_index >= 0 and _selected_plate_index >= 0:
			var cp: Vector3 = to_canonical(target.global_transform.origin)
			target_plate = _find_nearest_plate_in_strip(cp, 5)
			if not target_plate.empty():
				candidate_dist_sq = float(target_plate.get("dist_sq", INF))
		if target_plate.empty():
			target_plate = find_nearest_terrace_plate(target.global_transform.origin)
	else:
		_target_plate_query_counter = 0
	if target_plate.empty():
		return
	var spiral_index: int = int(target_plate["spiral_index"])
	var plate_index: int = int(target_plate["plate_index"])
	if spiral_index == _selected_spiral_index and plate_index == _selected_plate_index:
		return
	if continuous_tracking and _selected_spiral_index >= 0 and _selected_plate_index >= 0 \
			and auto_track_min_switch_distance > 0.0:
		var cp: Vector3 = to_canonical(target.global_transform.origin)
		var current_dist_sq: float = _get_plate_dist_sq_for_indices(
				_selected_spiral_index, _selected_plate_index, cp)
		if candidate_dist_sq >= INF:
			candidate_dist_sq = _get_plate_dist_sq_for_indices(spiral_index, plate_index, cp)
		# Comparación en dist_sq: candidate + margin² ≥ current evita sqrt y es approx equivalente.
		var margin_sq: float = auto_track_min_switch_distance * auto_track_min_switch_distance
		if candidate_dist_sq + margin_sq >= current_dist_sq:
			return
	if continuous_tracking:
		# En modo continuous el mundo ya rota via _update_continuous_tracking.
		# Solo actualizamos los índices y el pool, sin mover el active_collision_body.
		_selected_spiral_index = spiral_index
		_selected_plate_index = plate_index
		if spiral_index >= 0 and spiral_index < _registered_platforms.size():
			_selected_plate_canonical = get_plate_canonical_transform(
					_registered_platforms[spiral_index], plate_index)
	else:
		if _selected_spiral_index < 0 or _selected_plate_index < 0 or _active_collision_body == null:
			return
		_activate_nearest_plate_at_current_global_transform(spiral_index, plate_index)
	# A switch just happened — start the cooldown so the world can settle before
	# the next switch is allowed, breaking the inter-spiral plate flip-flop.
	_switch_cooldown_left = auto_track_switch_cooldown_frames
	_target_plate_query_counter = 0
	_pool_update_counter = collision_update_interval

func _should_track_without_floor_contact_for_current_plate_only_physics() -> bool:
	return centrifugal_current_plate_only_physics and spiral_blend > 0.001

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

func _update_continuous_tracking(_delta: float) -> bool:
	if Engine.editor_hint:
		return false
	if spiral_blend <= 0.001:
		return false
	var target: Spatial = _cached_tracking_target
	if target == null:
		return false

	# Ahora permitimos rotación moderada en el aire para un look más natural,
	# pero mantenemos la lógica de pivotar sobre el jugador.
	# El factor de velocidad se aplica en _get_effective_rotation_speed().

	var p_global: Vector3 = target.global_transform.origin
	var p_can: Vector3 = to_canonical(p_global)

	var up_can: Vector3
	if has_node("/root/GravityWorld"):
		up_can = get_node("/root/GravityWorld").get_canonical_up_direction(p_can)
	else:
		# Fallback radial — plane depends on cylinder_axis and may use a shifted
		# cylinder center when visuals are authored away from the origin.
		var radial_to_center: Vector3 = cylinder_radial_origin - p_can
		if cylinder_axis == 1:  # X_AXIS: ring closes in YZ
			up_can = Vector3(0.0, radial_to_center.y, radial_to_center.z).normalized()
		elif cylinder_axis == 2:  # Z_AXIS: ring closes in XY
			up_can = Vector3(radial_to_center.x, radial_to_center.y, 0.0).normalized()
		else:  # Y_AXIS (default): ring closes in XZ
			up_can = Vector3(radial_to_center.x, 0.0, radial_to_center.z).normalized()
		if up_can.length_squared() < 0.001:
			up_can = Vector3.UP

	var up_global: Vector3 = global_transform.basis.xform(up_can).normalized()
	var q_align: Quat = _quat_align(up_global, Vector3.UP)

	# Evitar vibraciones por coma flotante
	if q_align.w >= 0.99999:
		_target_global_transform = global_transform
		_has_transform_target = true
		return true

	var new_basis: Basis = Basis(q_align) * global_transform.basis
	# Pivotamos alrededor del jugador para que no sea desplazado bruscamente
	var new_origin: Vector3 = p_global - new_basis.xform(p_can)

	_target_global_transform = Transform(new_basis, new_origin)
	_has_transform_target = true
	# On the very first physics frame snap directly to target so there is no
	# visible rotation jump when entering a scene with continuous_tracking active.
	if not _startup_snap_done:
		_startup_snap_done = true
		global_transform = _target_global_transform
		return true
	# While easing back in after an airlock resume, slerp the accumulated rotation
	# over RESUME_TRACKING_DURATION seconds instead of the snappy default rate.
	var slerp_rate: float = _get_effective_rotation_speed(target) * 6.0
	if _resume_ramp_left > 0.0:
		_resume_ramp_left = max(0.0, _resume_ramp_left - _delta)
		slerp_rate = 1.0 / RESUME_TRACKING_DURATION
	# Interpolar suavemente hacia el target para evitar saltos de cámara.
	var t: float = min(1.0, slerp_rate * _delta)
	var eased_t: float = t * t * (3.0 - 2.0 * t)
	var current: Transform = global_transform
	var q_cur: Quat = current.basis.get_rotation_quat()
	var q_target: Quat = _target_global_transform.basis.get_rotation_quat()
	var q_new: Quat = q_cur.slerp(q_target, eased_t)
	var origin_new: Vector3 = current.origin.linear_interpolate(_target_global_transform.origin, eased_t)
	global_transform = Transform(Basis(q_new).orthonormalized(), origin_new)
	return true

func _get_tracking_target() -> Spatial:
	if not tracking_target_path.is_empty():
		var node: Node = get_node_or_null(tracking_target_path)
		if node == null and get_parent():
			node = get_parent().get_node_or_null(tracking_target_path)
		if node is Spatial:
			return node as Spatial
	var players: Array = get_tree().get_nodes_in_group("player") if is_inside_tree() else []
	for player in players:
		if player.has_meta("airlock_tracking_suspended") and bool(player.get_meta("airlock_tracking_suspended")):
			continue
		if player is Spatial and is_instance_valid(player):
			return player as Spatial
	return null

# Like _get_tracking_target() but ignores the airlock suspension meta. Used while
# easing to flat in the chamber, where we still want to pivot around the player
# even though normal tracking is suspended.
func _get_tracking_target_ignoring_suspension() -> Spatial:
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

func _resolve_physical_terrace_target() -> Spatial:
	if physical_terrace_path.is_empty():
		return null
	var configured: Node = get_node_or_null(physical_terrace_path)
	if configured == null and get_parent():
		configured = get_parent().get_node_or_null(physical_terrace_path)
	if configured is Spatial:
		return configured as Spatial
	return null

func _resolve_scene_anchor_content_node() -> Spatial:
	if scene_anchor_content_path.is_empty():
		return null
	var configured: Node = get_node_or_null(scene_anchor_content_path)
	if configured == null and get_parent():
		configured = get_parent().get_node_or_null(scene_anchor_content_path)
	if configured is Spatial:
		return configured as Spatial
	return null

func _resolve_scene_anchor_reference_node(content_node: Spatial) -> Spatial:
	if content_node == null:
		return null
	if scene_anchor_reference_path.is_empty():
		return content_node
	var configured: Node = get_node_or_null(scene_anchor_reference_path)
	if configured == null and get_parent():
		configured = get_parent().get_node_or_null(scene_anchor_reference_path)
	if configured is Spatial:
		return configured as Spatial
	return content_node

func _cache_scene_anchor_transforms() -> bool:
	var content_node: Spatial = _resolve_scene_anchor_content_node()
	if content_node == null:
		return false
	var reference_node: Spatial = _resolve_scene_anchor_reference_node(content_node)
	if reference_node == null:
		return false
	if not _scene_anchor_cached or _scene_anchor_content_node != content_node or _scene_anchor_reference_node != reference_node:
		_scene_anchor_content_node = content_node
		_scene_anchor_reference_node = reference_node
		_scene_anchor_content_canonical = global_transform.affine_inverse() * content_node.global_transform
		_scene_anchor_reference_canonical = global_transform.affine_inverse() * reference_node.global_transform
		_scene_anchor_cached = true
	return true

func _reset_scene_anchor_cache() -> void:
	_scene_anchor_content_node = null
	_scene_anchor_reference_node = null
	_scene_anchor_content_canonical = Transform.IDENTITY
	_scene_anchor_reference_canonical = Transform.IDENTITY
	_scene_anchor_cached = false
	_reset_scene_anchor_resolution()

func _reset_scene_anchor_resolution() -> void:
	_scene_anchor_resolved_spiral_index = -1
	_scene_anchor_resolved_plate_index = -1

func _apply_scene_anchor_after_ready() -> void:
	if Engine.editor_hint:
		return
	_cache_scene_anchor_transforms()
	_apply_scene_anchor()

func _apply_scene_anchor() -> bool:
	if Engine.editor_hint:
		return false
	if not _cache_scene_anchor_transforms():
		return false
	if spiral_blend <= 0.001:
		if scene_anchor_restore_in_flat_mode:
			_restore_scene_anchor_transform()
		return false
	_auto_register_platforms()
	var anchor_indices: Dictionary = _resolve_scene_anchor_indices()
	if anchor_indices.empty():
		return false
	var spiral_index: int = int(anchor_indices.get("spiral_index", -1))
	var plate_index: int = int(anchor_indices.get("plate_index", -1))
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return false
	var spiral: Spatial = _registered_platforms[spiral_index]
	_force_spiral_update(spiral)
	var plate_count: int = get_plate_count(spiral)
	if plate_count <= 0:
		return false
	plate_index = clamp(plate_index, 0, plate_count - 1)
	var plate_canonical: Transform = get_plate_canonical_transform(spiral, plate_index)
	var reference_from_content: Transform = _scene_anchor_content_canonical.affine_inverse() * _scene_anchor_reference_canonical
	var target_reference_canonical: Transform = plate_canonical * Transform(Basis.IDENTITY, scene_anchor_offset)
	var target_content_canonical: Transform = target_reference_canonical * reference_from_content.affine_inverse()
	if _scene_anchor_content_node and is_instance_valid(_scene_anchor_content_node):
		_scene_anchor_content_node.global_transform = global_transform * target_content_canonical
		return true
	return false

func _restore_scene_anchor_transform() -> void:
	if Engine.editor_hint:
		return
	if _scene_anchor_cached and _scene_anchor_content_node and is_instance_valid(_scene_anchor_content_node):
		_scene_anchor_content_node.global_transform = global_transform * _scene_anchor_content_canonical

func _resolve_scene_anchor_indices() -> Dictionary:
	if scene_anchor_spiral_index >= 0 and scene_anchor_plate_index >= 0:
		if _registered_platforms.empty():
			return {}
		var explicit_spiral: int = _wrap_index(scene_anchor_spiral_index, _registered_platforms.size())
		var explicit_plate: int = scene_anchor_plate_index
		if explicit_spiral < 0 or explicit_spiral >= _registered_platforms.size():
			return {}
		var explicit_count: int = get_plate_count(_registered_platforms[explicit_spiral])
		if explicit_count <= 0:
			return {}
		return {
			"spiral_index": explicit_spiral,
			"plate_index": clamp(explicit_plate, 0, explicit_count - 1)
		}
	if _scene_anchor_resolved_spiral_index >= 0 and _scene_anchor_resolved_plate_index >= 0:
		return {
			"spiral_index": _scene_anchor_resolved_spiral_index,
			"plate_index": _scene_anchor_resolved_plate_index
		}
	if not scene_anchor_use_selected_plate_on_ready:
		return {}
	var resolved_spiral: int = _selected_spiral_index
	var resolved_plate: int = _selected_plate_index
	if resolved_spiral < 0 or resolved_plate < 0:
		var target: Spatial = _get_tracking_target()
		if target:
			var nearest: Dictionary = find_nearest_terrace_plate(target.global_transform.origin)
			if not nearest.empty():
				resolved_spiral = int(nearest.get("spiral_index", -1))
				resolved_plate = int(nearest.get("plate_index", -1))
	if resolved_spiral < 0 or resolved_plate < 0:
		return {}
	_scene_anchor_resolved_spiral_index = resolved_spiral
	_scene_anchor_resolved_plate_index = resolved_plate
	return {
		"spiral_index": resolved_spiral,
		"plate_index": resolved_plate
	}

func _select_nearest_plate_on_ready_if_enabled() -> void:
	if Engine.editor_hint:
		return
	if not select_nearest_plate_on_ready:
		return
	_select_nearest_tracking_plate(snap_initial_selection)

func _select_nearest_tracking_plate(snap_immediately: bool = false) -> bool:
	if Engine.editor_hint:
		return false
	if spiral_blend <= 0.001 and centrifugal_current_plate_only_physics:
		return false
	_auto_register_platforms()
	_sync_spirals()
	var target: Spatial = _get_tracking_target()
	if target == null:
		return false
	var nearest: Dictionary = find_nearest_terrace_plate(target.global_transform.origin)
	if nearest.empty():
		return false
	var target_body: Spatial = _resolve_physical_terrace_target()
	return select_terrace_plate(
			int(nearest["spiral_index"]),
			int(nearest["plate_index"]),
			target_body,
			snap_immediately)

func _clear_selected_plate_for_flat_mode() -> void:
	if Engine.editor_hint:
		return
	_selected_spiral_index = -1
	_selected_plate_index = -1
	_selected_plate_canonical = Transform.IDENTITY
	_platform_node = null
	current_platform = NodePath("")
	_has_transform_target = true
	_target_global_transform = Transform.IDENTITY
	_target_quat = Quat()
	_is_transitioning = false
	global_transform = Transform.IDENTITY
	_sync_world_environment_sky_frames()

	var pt: Spatial = _resolve_physical_terrace_target()
	if pt:
		pt.global_transform = Transform.IDENTITY
		if pt is StaticBody:
			_active_collision_body = pt as StaticBody
			_active_collision_shape = _find_collision_shape(_active_collision_body)
			if _active_collision_shape == null:
				_active_collision_shape = _create_collision_shape(_active_collision_body)
	if scene_anchor_restore_in_flat_mode:
		_restore_scene_anchor_transform()
	_deactivate_collision_pool()

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
	# Keep the physical terrace aligned with the real spiral plate orientation.
	# Forcing a horizontal basis here causes platform/gravity mismatch in-game.
	active_body.global_transform = plate_global
	select_terrace_plate(spiral_index, plate_index, active_body, false)

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
	var configured: Spatial = _resolve_physical_terrace_target()
	if configured is StaticBody:
		_active_collision_body = configured as StaticBody
		_active_collision_shape = _find_collision_shape(_active_collision_body)
		if _active_collision_shape == null:
			_active_collision_shape = _create_collision_shape(_active_collision_body)
		return _active_collision_body

	_ensure_generated_collision_root()
	_active_collision_body = StaticBody.new()
	_active_collision_body.name = "ActiveTerraceCollision"
	_active_collision_body.collision_layer = 1
	_active_collision_body.collision_mask = 1
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
	var far_away: Transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for i in range(collision_pool_size):
		var body: StaticBody = StaticBody.new()
		body.name = "PoolTerraceCollision_%d" % i
		body.collision_layer = 1
		body.collision_mask = 1
		# Metadata inicialmente vacío; se asigna en _assign_pool_to_nearest_plates.
		body.set_meta("spiral_index", -1)
		body.set_meta("plate_index", -1)
		body.set_meta("canonical_tx", null)
		body.global_transform = far_away
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
	if spiral_blend <= 0.001 and centrifugal_current_plate_only_physics:
		_deactivate_collision_pool()

func _destroy_collision_pool() -> void:
	for body in _collision_pool:
		if is_instance_valid(body):
			body.queue_free()
	_collision_pool.clear()
	_pool_assignments.clear()

# Recalcula qué plates reciben un slot del pool, priorizando distancia al jugador.
# Solo reasigna transforms — cero allocs.
func _assign_pool_to_nearest_plates() -> void:
	if spiral_blend <= 0.001 and centrifugal_current_plate_only_physics:
		_deactivate_collision_pool()
		return
	if centrifugal_current_plate_only_physics:
		_deactivate_collision_pool()
		return
	if _collision_pool.empty() or _registered_platforms.empty():
		return
	var tracking_target: Spatial = _get_tracking_target()
	var target_global_pos: Vector3
	var center_canonical: Vector3
	if tracking_target != null:
		target_global_pos = tracking_target.global_transform.origin
		center_canonical = to_canonical(target_global_pos)
	elif _selected_plate_index >= 0:
		center_canonical = _selected_plate_canonical.origin
		target_global_pos = from_canonical(center_canonical)
	else:
		return

	# Buscar las N placas más cercanas usando offsets verificados por telemetría.
	# Encontramos la placa más cercana en espiral 0, luego muestreamos ±search_radius
	# placas alrededor del offset correspondiente en cada espiral.
	var base_idx: int = _find_nearest_plate_in_spiral(0, center_canonical)
	var search_radius: int = 4
	var candidates: Array = []
	var pool_size: int = _collision_pool.size()

	for spiral_index in range(_registered_platforms.size()):
		var spiral: Spatial = _registered_platforms[spiral_index]
		var plate_count: int = get_plate_count(spiral)
		if plate_count <= 0: continue

		var spiral_canonical_base: Transform = global_transform.affine_inverse() * spiral.global_transform
		var cached_list = spiral.get("_cached_transforms")
		if cached_list == null or not (cached_list is Array):
			continue

		var offset: int = INTERLOCK_OFFSETS[spiral_index] if spiral_index < INTERLOCK_OFFSETS.size() else 0
		var center_idx: int = posmod(base_idx + offset, plate_count)

		for d in range(-search_radius, search_radius + 1):
			var plate_index := posmod(center_idx + d, plate_count)
			if plate_index < 0 or plate_index >= cached_list.size():
				continue
			var plate_tx: Transform = spiral_canonical_base * (cached_list[plate_index] as Transform)
			var dist_sq: float = plate_tx.origin.distance_squared_to(center_canonical)
			_insert_pool_candidate_sorted(candidates, {
				"spiral_index": spiral_index,
				"plate_index": plate_index,
				"dist_sq": dist_sq,
				"canonical_tx": plate_tx
			}, pool_size)

	var active_candidates: Array = candidates
	var candidates_by_key := {}
	for candidate in active_candidates:
		candidates_by_key[_make_pool_key_id(int(candidate["spiral_index"]), int(candidate["plate_index"]))] = candidate

	var assigned_keys := {}
	for i in range(_collision_pool.size()):
		var assignment: Dictionary = _pool_assignments[i]
		if assignment.empty():
			continue
		var key: int = _make_pool_key_id(int(assignment.get("spiral_index", -1)), int(assignment.get("plate_index", -1)))
		if candidates_by_key.has(key):
			var existing_candidate: Dictionary = candidates_by_key[key]
			if continuous_tracking and _pool_assignment_matches_candidate(assignment, existing_candidate):
				_sync_collision_pool_slot_transform(i, existing_candidate)
				assigned_keys[key] = true
				continue
			_assign_collision_pool_slot(i, existing_candidate)
			assigned_keys[key] = true
		else:
			_deactivate_collision_pool_slot(i)

	for candidate in active_candidates:
		var key: int = _make_pool_key_id(int(candidate["spiral_index"]), int(candidate["plate_index"]))
		if assigned_keys.has(key):
			continue
		var free_slot: int = _find_free_collision_pool_slot()
		if free_slot == -1:
			break
		_assign_collision_pool_slot(free_slot, candidate)
		assigned_keys[key] = true

func _deactivate_collision_pool() -> void:
	var far_away: Transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
	for i in range(_collision_pool.size()):
		var body: StaticBody = _collision_pool[i]
		if not is_instance_valid(body):
			continue
		body.global_transform = far_away
		body.set_meta("spiral_index", -1)
		body.set_meta("plate_index", -1)
		body.set_meta("canonical_tx", null)
		if i < _pool_assignments.size():
			_pool_assignments[i] = {}

func _assign_collision_pool_slot(index: int, candidate: Dictionary) -> void:
	if index < 0 or index >= _collision_pool.size():
		return
	var body: StaticBody = _collision_pool[index]
	if not is_instance_valid(body):
		return
	var spiral_index: int = int(candidate["spiral_index"])
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return
	var spiral: Spatial = _registered_platforms[spiral_index]
	_sync_pool_shape_extents(body, spiral)
	body.set_meta("spiral_index", spiral_index)
	body.set_meta("plate_index", int(candidate["plate_index"]))
	body.set_meta("canonical_tx", candidate["canonical_tx"])
	var plate_global: Transform = global_transform * (candidate["canonical_tx"] as Transform)
	body.global_transform = _get_neighbor_collision_transform(plate_global)
	_pool_assignments[index] = {
		"spiral_index": spiral_index,
		"plate_index": int(candidate["plate_index"])
	}

func _deactivate_collision_pool_slot(index: int) -> void:
	if index < 0 or index >= _collision_pool.size():
		return
	var body: StaticBody = _collision_pool[index]
	if is_instance_valid(body):
		body.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
		body.set_meta("spiral_index", -1)
		body.set_meta("plate_index", -1)
		body.set_meta("canonical_tx", null)
	if index < _pool_assignments.size():
		_pool_assignments[index] = {}

func _find_free_collision_pool_slot() -> int:
	for i in range(_pool_assignments.size()):
		if _pool_assignments[i].empty():
			return i
	return -1

func _insert_pool_candidate_sorted(candidates: Array, candidate: Dictionary, max_count: int) -> void:
	if max_count <= 0:
		return
	var dist_sq: float = float(candidate["dist_sq"])
	var insert_at: int = candidates.size()
	while insert_at > 0 and dist_sq < float(candidates[insert_at - 1]["dist_sq"]):
		insert_at -= 1
	if insert_at >= max_count:
		return
	candidates.insert(insert_at, candidate)
	if candidates.size() > max_count:
		candidates.pop_back()

func _pool_assignment_matches_candidate(assignment: Dictionary, candidate: Dictionary) -> bool:
	return int(assignment.get("spiral_index", -1)) == int(candidate["spiral_index"]) \
			and int(assignment.get("plate_index", -1)) == int(candidate["plate_index"])

func _make_pool_key_id(spiral_index: int, plate_index: int) -> int:
	return spiral_index * 100000 + plate_index

func _make_pool_key(spiral_index: int, plate_index: int) -> String:
	return "%d:%d" % [spiral_index, plate_index]

func _sync_pool_transforms_to_world() -> void:
	for i in range(_collision_pool.size()):
		var body: StaticBody = _collision_pool[i]
		if not is_instance_valid(body): continue
		if not body.has_meta("canonical_tx"): continue
		var canonical_tx = body.get_meta("canonical_tx")
		if canonical_tx is Transform:
			body.global_transform = global_transform * (canonical_tx as Transform)

func _sync_collision_pool_slot_transform(index: int, candidate: Dictionary) -> void:
	if index < 0 or index >= _collision_pool.size():
		return
	var body: StaticBody = _collision_pool[index]
	if not is_instance_valid(body):
		return
	var canonical_tx = candidate.get("canonical_tx", null)
	if canonical_tx is Transform:
		var plate_global: Transform = global_transform * (canonical_tx as Transform)
		body.global_transform = _get_neighbor_collision_transform(plate_global)

func _sort_by_dist_sq(a: Dictionary, b: Dictionary) -> bool:
	return a.dist_sq < b.dist_sq

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
	# Cache extents per spiral index — plate_mesh never changes at runtime.
	var spiral_index: int = _registered_platforms.find(spiral)
	if spiral_index >= 0 and _spiral_extents_cache.has(spiral_index):
		var cached_e: Vector3 = _spiral_extents_cache[spiral_index]
		var want: Vector3 = Vector3(cached_e.x * collision_pool_xz_scale, cached_e.y, cached_e.z * collision_pool_xz_scale)
		if box.extents.is_equal_approx(want):
			return
		box.extents = want
		return
	var e: Vector3 = _get_plate_collision_extents(spiral)
	if spiral_index >= 0:
		_spiral_extents_cache[spiral_index] = e
	# Escalar XZ para cubrir el hueco entre plates adyacentes.
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
	# En continuous_tracking, el caller aplica collision_update_interval para no mover
	# decenas de StaticBodies cada tick físico. Solo forzar durante transiciones no continuas.
	if _is_transitioning:
		return true
	if _has_transform_target:
		return true
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

func _configure_terrace_culling_for_platform() -> void:
	if not enable_terrace_distance_culling:
		return
	if OS.has_feature("HTML5"):
		terrace_culling_max_distance = 280.0
		terrace_culling_safe_radius = 45.0
		terrace_culling_update_interval = 45
	elif OS.has_touchscreen_ui_hint():
		terrace_culling_max_distance = 500.0
		terrace_culling_safe_radius = 35.0
		terrace_culling_update_interval = 45
	else:
		terrace_culling_max_distance = 900.0
		terrace_culling_safe_radius = 0.0
		terrace_culling_update_interval = 30

func _apply_terrace_distance_culling() -> void:
	var max_dist_sq: float = terrace_culling_max_distance * terrace_culling_max_distance
	var safe_sq: float = terrace_culling_safe_radius * terrace_culling_safe_radius
	if _culling_target == null or not is_instance_valid(_culling_target):
		_culling_target = _get_tracking_target()
	if _culling_target == null:
		return
	var player_pos: Vector3 = _culling_target.global_translation
	for spiral_index in range(_registered_platforms.size()):
		var spiral: Spatial = _registered_platforms[spiral_index]
		if spiral == null or not is_instance_valid(spiral):
			continue
		if not (spiral is TerraceSpiral):
			continue
		var multimesh: MultiMesh = spiral.get("multimesh")
		if multimesh == null:
			continue
		var plate_count: int = multimesh.instance_count
		var spiral_global: Transform = spiral.global_transform
		var culled: Array = []
		for i in range(plate_count):
			var plate_transform: Transform = multimesh.get_instance_transform(i)
			var plate_world: Vector3 = spiral_global.xform(plate_transform.origin)
			var dist_sq: float = plate_world.distance_squared_to(player_pos)
			if dist_sq <= safe_sq:
				continue
			if dist_sq > max_dist_sq:
				culled.append(i)
		spiral.set_distance_culled_plates(culled)

func _find_nearest_plate_in_spiral(spiral_index: int, canonical_center: Vector3) -> int:
	if spiral_index < 0 or spiral_index >= _registered_platforms.size():
		return 0
	var spiral: Spatial = _registered_platforms[spiral_index]
	var plate_count: int = get_plate_count(spiral)
	if plate_count <= 0:
		return 0
	var cached = spiral.get("_cached_transforms")
	if cached == null or not (cached is Array) or cached.size() == 0:
		return 0
	var canon_base: Transform = global_transform.affine_inverse() * spiral.global_transform
	var best_idx := 0
	var best_d := INF
	for i in range(min(cached.size(), plate_count)):
		var d: float = (canon_base * (cached[i] as Transform)).origin.distance_squared_to(canonical_center)
		if d < best_d:
			best_d = d
			best_idx = i
	return best_idx
