tool
extends Spatial
class_name LightPathV2

# A run of floor markers that lights up behind and just ahead of the player as they
# climb, to show the way out of a level that is mostly dark scaffolding.
#
# Deliberately not made of lights. On GLES2 a dozen OmniLights along a walkway costs
# far more than the effect is worth, so every marker is one instance in a single
# MultiMesh — one draw call for the whole path — drawn unshaded and additively so it
# reads as a glow strip without lighting anything. Switching a marker on is a colour
# write on an instance, and those only happen when the lit count actually changes,
# not every frame.
#
# Waypoints come either from this node's own Position3D children or from the
# children of `waypoint_source` (point it at a generated walkway and the path
# follows the walkway when it rebuilds).

const PLAYER_GROUP := "player"
const MARKERS_NAME := "Markers"

export(NodePath) var waypoint_source
# Some waypoint nodes sit at their own base with the walkable surface declared as a
# property (SteelGratePlatform keeps its deck at `platform_height`), so taking the
# node origin would run the path along the floor of the level instead of along the
# walkway. Name that property and it gets added to each waypoint's height.
export(String) var waypoint_height_property := ""
# A waypoint that is a whole walkway rather than a point: name the property holding
# its length along local Z and the path runs end to end through it instead of
# centre to centre, which otherwise leaves the first and last half-segment of a run
# unmarked and cuts the corner at every join.
export(String) var waypoint_span_property := ""
# True when the waypoints form one continuous run (a spiral of joined walkways).
# False treats each waypoint as its own stretch, so a set of separate catwalks does
# not get markers strung through the air between them.
export(bool) var connect_segments := true

# platform_height is only the nominal deck height: SteelGratePlatform warps its deck
# with per-corner height offsets (that is how a walkway climbs), so a marker placed
# at the declared height floats over the middle of a ramp and sinks at its ends.
# Dropping each marker onto whatever it is standing on fixes that for warped decks,
# ring floors and spokes alike, without reaching into anyone's internals.
export(bool) var snap_to_surface := true
export(int, LAYERS_3D_PHYSICS) var snap_mask := 64
export(float, 0.1, 20.0, 0.1) var snap_probe := 2.5

# A handful of real lights that ride the markers nearest the player. The markers
# themselves are unlit geometry; this is the only part that costs lighting, and it
# is capped, so the cost does not grow with the length of the path.
export(int, 0, 12) var light_pool_size := 0
export(float, 0.5, 40.0, 0.1) var light_range := 6.0
export(float, 0.0, 8.0, 0.05) var light_energy := 1.1
export(float, 1.0, 80.0, 0.5) var light_follow_radius := 16.0
export(int, LAYERS_3D_RENDER) var light_cull_mask := 1048575
# Distance between markers along the path. 0 places exactly one marker per
# waypoint, which is what an "exit here" cluster wants.
export(float, 0.0, 40.0, 0.1) var spacing := 2.0
export(float, 0.05, 4.0, 0.01) var marker_size := 0.35
# Floor markers lie flat; a fixture up on a wall has to face the camera or it is
# invisible edge-on. Billboarding happens in the vertex shader, so the whole set is
# still one draw call.
export(bool) var marker_billboard := false
# Lifted clear of the deck so it does not z-fight with the grate.
export(float, -2.0, 4.0, 0.01) var height_offset := 0.06

export(Color) var lit_color := Color(0.35, 0.85, 1.0, 1.0)
export(Color) var dim_color := Color(0.02, 0.06, 0.09, 1.0)
# Markers up to the player's height plus this stay lit, so the path reads as
# leading somewhere instead of stopping at their feet.
export(float, 0.0, 40.0, 0.1) var lead_height := 2.5
# Fixtures that are simply on, rather than a trail that reveals itself as you
# climb. The light pool still follows the player, so only the nearest few are real.
export(bool) var always_lit := false
# Once lit, a marker stays lit: the path is a breadcrumb trail, not a torch.
export(bool) var latch_lit := true
export(float, 0.05, 2.0, 0.05) var refresh_interval := 0.25
export(AudioStream) var activation_sound
export(float, -80.0, 24.0, 0.5) var activation_sound_volume_db := 18.0
export(float, 0.0, 5.0, 0.05) var activation_sound_debounce := 2.0
export(float, 0.0, 40.0, 0.5) var activation_sound_trigger_distance := 25.0
export(float, 0.0, 2.0, 0.05) var activation_sound_delay := 0.5
# Optional baked fixture MultiMesh used to place pooled lights at the actual bulb.
export(NodePath) var fixture_light_source
export(Vector3) var fixture_light_local_offset := Vector3.ZERO
export(Mesh) var fixture_high_mesh
export(Mesh) var fixture_lod_mesh
export(float, 1.0, 80.0, 0.5) var fixture_lod_distance := 14.0
export(String) var fixture_batch_prefix := "FixtureBatch_"
export(bool) var fixture_adaptive_mobile_lod := true
# En movil, no permitir NUNCA la malla alta de los fixtures. La ruta adaptativa podia
# subir a fixture_high_mesh si el FPS se sostenia alto unos segundos, pero en telefono ese
# ascenso es justo lo que reintroduce el costo que el LOD venia a evitar, y ademas oscila.
# La malla alta cuesta 3078 vertices por instancia contra 1109 de la LOD, sobre 88 lamparas.
export(bool) var fixture_force_lod_on_mobile := true
# Oculta por completo los batches de fixtures cuya lampara mas cercana esta mas alla de
# esta distancia. Los 8 batches estan repartidos alrededor del anillo del domo y el jugador
# solo ve dos o tres; los demas aportan vertices que se reenvian por cada luz que los
# alcanza. 0 = sin culling (comportamiento previo).
export(float, 0.0, 120.0, 1.0) var fixture_cull_distance := 0.0
export(float, 1.0, 120.0, 1.0) var fixture_full_detail_fps := 50.0
export(float, 1.0, 30.0, 0.5) var fixture_full_detail_hold_seconds := 5.0
export(float, 1.0, 120.0, 1.0) var fixture_lod_fallback_fps := 42.0
export(float, 0.5, 10.0, 0.5) var fixture_lod_fallback_seconds := 2.0

export(bool) var auto_build := true
export(bool) var rebuild_baked_items := false

var _marker_heights := []
var _lit_count := -1
var _elapsed := 0.0
var _player: Spatial = null
var _build_queued := false
var _snap_pending := false
var _lights := []
var _activation_sound_player: AudioStreamPlayer3D = null
var _activation_sound_cooldown := 1.0
var _activation_sound_pending_delay := -1.0
var _activation_sound_pending_position := Vector3.ZERO
var _fixture_full_detail_enabled := false
var _fixture_high_fps_seconds := 0.0
var _fixture_low_fps_seconds := 0.0
var _fixture_quality_reported := false

func _ready() -> void:
	if Engine.editor_hint:
		# Mismo criterio que en runtime: si la escena ya trae los hijos horneados y
		# nadie pidio rebuild, NO reconstruir. Sin esto cualquier apertura de la
		# escena en el editor —o el pase `--editor --quit` del import de CI—
		# regeneraba la geometria y la volvia a incrustar en el .tscn al guardar,
		# deshaciendo el horneado (Dome_Intro paso de 0.30 MB a 1.94 MB asi) y
		# pisando datos ya horneados.
		if get_child_count() == 0 or rebuild_baked_items:
			_queue_build()
		return
	if get_child_count() == 0 or rebuild_baked_items:
		build()
	if activation_sound:
		_activation_sound_player = AudioStreamPlayer3D.new()
		_activation_sound_player.name = "ActivationSound"
		_activation_sound_player.stream = activation_sound
		_activation_sound_player.unit_db = activation_sound_volume_db
		_activation_sound_player.unit_size = 10.0
		_activation_sound_player.max_db = 16.0
		_activation_sound_player.max_distance = max(light_follow_radius * 2.0, activation_sound_trigger_distance) 
		add_child(_activation_sound_player)
	_cache_marker_heights()
	_snap_pending = snap_to_surface
	set_process(not _marker_heights.empty())

func set_waypoint_source(value: NodePath) -> void:
	waypoint_source = value
	_queue_build()

func _queue_build() -> void:
	if not auto_build or not is_inside_tree() or _build_queued:
		return
	_build_queued = true
	call_deferred("build")

func _process(delta: float) -> void:
	if Engine.editor_hint:
		return
	_activation_sound_cooldown = max(_activation_sound_cooldown - delta, 0.0)
	_step_pending_activation_sound(delta)
	_elapsed += delta
	if _elapsed < refresh_interval:
		return
	_elapsed = 0.0
	if not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	# Colliders are not all registered on the frame the level is built, so the drop
	# onto the deck waits for the first tick instead of running inside build().
	if _snap_pending:
		_snap_pending = false
		_snap_markers_to_surface()
	_apply_lit_limit(INF if always_lit else _player.global_transform.origin.y + lead_height)
	_drive_lights()
	_drive_fixture_lod()

# --- build -------------------------------------------------------------------

func build() -> void:
	_build_queued = false
	# Muestrear ANTES de borrar. Al reves, un source que dejo de dar waypoints
	# (por ejemplo un grupo que se horneo a un solo CombinedMesh) borraba los
	# marcadores ya horneados y no los reemplazaba por nada.
	var points: Array = _sample_points()
	if points.size() == 0:
		return
	_clear_markers()

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.color_format = MultiMesh.COLOR_8BIT
	multimesh.mesh = _marker_mesh()
	multimesh.instance_count = points.size()

	var inverse: Transform = global_transform.affine_inverse()
	for index in range(points.size()):
		var local: Vector3 = inverse.xform(points[index]) + Vector3.UP * height_offset
		multimesh.set_instance_transform(index, Transform(Basis(), local))
		multimesh.set_instance_color(index, dim_color)

	var instance := MultiMeshInstance.new()
	instance.name = MARKERS_NAME
	instance.multimesh = multimesh
	instance.material_override = _marker_material()
	# Same visual layer the rest of the scaffolding uses.
	instance.layers = 64
	instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var scene_owner := _scene_owner()
	if scene_owner:
		instance.owner = scene_owner
	_cache_marker_heights()

# Waypoints in world space: this node's Position3D children, or the children of
# waypoint_source when one is given.
func _waypoints() -> Array:
	var source: Node = self
	if waypoint_source != NodePath() and has_node(waypoint_source):
		source = get_node(waypoint_source)
	var points := []
	for child in source.get_children():
		# Our own output is not a waypoint.
		if child is MultiMeshInstance or child is Light:
			continue
		if not (child is Spatial):
			continue
		var spatial := child as Spatial
		var lift := 0.0
		if not waypoint_height_property.empty():
			var declared = child.get(waypoint_height_property)
			if typeof(declared) != TYPE_REAL and typeof(declared) != TYPE_INT:
				# Si se pidio una propiedad de altura y este hijo no la declara,
				# no es un waypoint: es otra cosa que cuelga del source. Sin este
				# corte, un grupo ya horneado (CombinedMesh + StaticBody, ninguno
				# con la propiedad) devolvia dos "waypoints" en el origen del
				# grupo y colapsaba el camino entero a un solo marcador.
				continue
			lift = float(declared)
		var span := 0.0
		if not waypoint_span_property.empty():
			var declared_span = child.get(waypoint_span_property)
			if typeof(declared_span) == TYPE_REAL or typeof(declared_span) == TYPE_INT:
				span = float(declared_span)
		if span > 0.01:
			# Both ends of the walkway, in its own frame, so the run stays on the
			# deck through the turn instead of chording between centres.
			points.append([
				spatial.global_transform.xform(Vector3(0.0, lift, -span * 0.5)),
				spatial.global_transform.xform(Vector3(0.0, lift, span * 0.5)),
			])
		else:
			points.append([spatial.global_transform.xform(Vector3(0.0, lift, 0.0))])
	if connect_segments:
		var joined := []
		for run in points:
			for point in run:
				joined.append(point)
		return [joined]
	return points

# Walks the polyline and drops a marker every `spacing` metres. spacing <= 0 keeps
# the waypoints themselves.
func _sample_points() -> Array:
	var points := []
	for run in _waypoints():
		for point in _sample_run(run):
			points.append(point)
	return points

func _sample_run(waypoints: Array) -> Array:
	if spacing <= 0.01 or waypoints.size() < 2:
		return waypoints
	var points := [waypoints[0]]
	var carry := 0.0
	for i in range(waypoints.size() - 1):
		var from: Vector3 = waypoints[i]
		var to: Vector3 = waypoints[i + 1]
		var length: float = from.distance_to(to)
		if length <= 0.0001:
			continue
		var travelled: float = spacing - carry
		while travelled <= length:
			points.append(from.linear_interpolate(to, travelled / length))
			travelled += spacing
		carry = length - (travelled - spacing)
	return points

func _marker_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(marker_size, marker_size)
	if marker_billboard:
		# A billboard has to keep facing +Z for the shader to turn it toward the
		# camera; laying it flat first would defeat that.
		return quad
	var tool_mesh := SurfaceTool.new()
	tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool_mesh.append_from(quad, 0, Transform(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	return tool_mesh.commit()

func _marker_material() -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.vertex_color_use_as_albedo = true
	material.flags_transparent = true
	# Additive keeps the quad's edges from reading as a card and makes an unlit
	# marker (near-black) disappear on its own.
	material.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.flags_do_not_receive_shadows = true
	material.params_depth_draw_mode = SpatialMaterial.DEPTH_DRAW_OPAQUE_ONLY
	if marker_billboard:
		material.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
		material.params_billboard_keep_scale = true
		# Without a falloff a billboard reads as a hard square rather than a glow.
		# Generated rather than shipped as an asset: it is 64x64 and built once.
		material.albedo_texture = _glow_texture()
	return material

const GLOW_TEXTURE_SIZE := 64

func _glow_texture() -> ImageTexture:
	var image := Image.new()
	image.create(GLOW_TEXTURE_SIZE, GLOW_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.lock()
	var centre: float = float(GLOW_TEXTURE_SIZE - 1) * 0.5
	for y in range(GLOW_TEXTURE_SIZE):
		for x in range(GLOW_TEXTURE_SIZE):
			var distance: float = Vector2(float(x) - centre, float(y) - centre).length() / centre
			# Squared falloff, so the core stays bright and the rim fades out.
			var level: float = pow(clamp(1.0 - distance, 0.0, 1.0), 2.0)
			image.set_pixel(x, y, Color(level, level, level, level))
	image.unlock()
	var texture := ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_FILTER)
	return texture

# --- lighting ----------------------------------------------------------------

func _cache_marker_heights() -> void:
	_marker_heights = []
	_lit_count = -1
	var markers: MultiMeshInstance = get_node_or_null(MARKERS_NAME) as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		return
	for index in range(markers.multimesh.instance_count):
		var local: Vector3 = markers.multimesh.get_instance_transform(index).origin
		_marker_heights.append(markers.global_transform.xform(local).y)

# Each marker answers for itself rather than being lit by index, so a path that
# dips or doubles back still lights the part the player has actually reached.
func _apply_lit_limit(limit: float) -> void:
	var count := 0
	for marker_height in _marker_heights:
		if float(marker_height) <= limit:
			count += 1
	if latch_lit:
		if count <= _lit_count:
			return
	elif count == _lit_count:
		return
	_lit_count = count
	var markers: MultiMeshInstance = get_node_or_null(MARKERS_NAME) as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		return
	var reached: float = limit
	if latch_lit:
		# Latched: the ceiling only ever rises, so light everything up to the
		# highest marker reached so far.
		reached = -INF
		for marker_height in _marker_heights:
			if float(marker_height) <= limit:
				reached = max(reached, float(marker_height))
	for index in range(markers.multimesh.instance_count):
		var height: float = float(_marker_heights[index]) if index < _marker_heights.size() else 0.0
		markers.multimesh.set_instance_color(index, lit_color if height <= reached else dim_color)

# Drops every marker onto the surface underneath it. One ray per marker, once.
func _snap_markers_to_surface() -> void:
	if not snap_to_surface:
		return
	var markers: MultiMeshInstance = get_node_or_null(MARKERS_NAME) as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		return
	var space := get_world().direct_space_state
	if space == null:
		return
	var to_local: Transform = markers.global_transform.affine_inverse()
	for index in range(markers.multimesh.instance_count):
		var xform: Transform = markers.multimesh.get_instance_transform(index)
		var world: Vector3 = markers.global_transform.xform(xform.origin)
		# Start above the nominal height and probe down through it.
		var from: Vector3 = world + Vector3.UP * snap_probe
		var hit: Dictionary = space.intersect_ray(from, world + Vector3.DOWN * snap_probe,
			[], snap_mask)
		if not hit.has("position"):
			continue
		xform.origin = to_local.xform(hit["position"] + Vector3.UP * height_offset)
		markers.multimesh.set_instance_transform(index, xform)
	_cache_marker_heights()

# Moves a fixed pool of lights onto the lit markers closest to the player. The pool
# never grows, so a longer path costs no more lighting than a short one.
func _drive_lights() -> void:
	if light_pool_size <= 0:
		return
	var markers: MultiMeshInstance = get_node_or_null(MARKERS_NAME) as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		return
	_ensure_light_pool()
	var origin: Vector3 = _player.global_transform.origin
	var reach_squared: float = light_follow_radius * light_follow_radius

	# Nearest lit markers, kept by insertion into a list only as long as the pool.
	var best := []
	for index in range(markers.multimesh.instance_count):
		if markers.multimesh.get_instance_color(index).v <= 0.5:
			continue
		var world: Vector3 = markers.global_transform.xform(
			markers.multimesh.get_instance_transform(index).origin)
		var distance: float = origin.distance_squared_to(world)
		if distance > reach_squared:
			continue
		var at: int = best.size()
		for i in range(best.size()):
			if distance < best[i][0]:
				at = i
				break
		if at < light_pool_size:
			best.insert(at, [distance, world, index])
			if best.size() > light_pool_size:
				best.resize(light_pool_size)

	var activation_position := Vector3.ZERO
	var activation_distance := INF
	var activation_is_visible := false
	var activation_trigger_distance_squared: float = activation_sound_trigger_distance * activation_sound_trigger_distance
	var camera: Camera = get_viewport().get_camera() if get_viewport() else null
	for i in range(_lights.size()):
		var light: OmniLight = _lights[i]
		if i >= best.size():
			light.visible = false
			continue
		var next_position: Vector3 = _fixture_light_position(best[i][2], best[i][1] + Vector3.UP * 0.35)
		var changed_fixture: bool = not light.visible or light.global_transform.origin.distance_squared_to(next_position) > 0.01
		light.visible = true
		light.global_transform = Transform(Basis(), next_position)
		if changed_fixture and best[i][0] <= activation_trigger_distance_squared:
			var is_visible: bool = _is_visible_to_camera(camera, next_position)
			if (is_visible and not activation_is_visible) or (is_visible == activation_is_visible and best[i][0] < activation_distance):
				activation_is_visible = is_visible
				activation_distance = best[i][0]
				activation_position = next_position
	if activation_is_visible and activation_distance < INF and is_instance_valid(_activation_sound_player) and _activation_sound_cooldown <= 0.0 and _activation_sound_pending_delay < 0.0:
		_activation_sound_pending_position = activation_position
		_activation_sound_pending_delay = activation_sound_delay

func _fixture_light_position(index: int, fallback: Vector3) -> Vector3:
	if fixture_light_source == NodePath() or not has_node(fixture_light_source):
		return fallback
	var fixtures: MultiMeshInstance = get_node(fixture_light_source) as MultiMeshInstance
	if fixtures == null or fixtures.multimesh == null or index >= fixtures.multimesh.instance_count:
		return fallback
	var fixture_transform: Transform = fixtures.multimesh.get_instance_transform(index)
	return fixtures.global_transform.xform(fixture_transform.xform(fixture_light_local_offset))

func _drive_fixture_lod() -> void:
	if fixture_high_mesh == null or fixture_lod_mesh == null:
		return
	var adaptive_mobile := fixture_adaptive_mobile_lod and _is_mobile_profile()
	if adaptive_mobile:
		_update_adaptive_fixture_quality()
		if not _fixture_quality_reported:
			_publish_fixture_quality("lod", float(Performance.get_monitor(Performance.TIME_FPS)))
	var camera: Camera = get_viewport().get_camera() if get_viewport() else null
	var origin: Vector3 = camera.global_transform.origin if camera else _player.global_transform.origin
	var threshold_squared: float = fixture_lod_distance * fixture_lod_distance
	for child in get_children():
		if not child is MultiMeshInstance or not child.name.begins_with(fixture_batch_prefix):
			continue
		var batch: MultiMeshInstance = child as MultiMeshInstance
		if batch.multimesh == null:
			continue
		var nearest_squared := INF
		for index in range(batch.multimesh.instance_count):
			var local_position: Vector3 = batch.multimesh.get_instance_transform(index).origin
			var world_position: Vector3 = batch.global_transform.xform(local_position)
			nearest_squared = min(nearest_squared, origin.distance_squared_to(world_position))
		# Culling por distancia antes de elegir malla: un batch oculto no cuesta nada.
		if fixture_cull_distance > 0.0:
			var cull_squared: float = fixture_cull_distance * fixture_cull_distance
			var should_show: bool = nearest_squared <= cull_squared
			if batch.visible != should_show:
				batch.visible = should_show
			if not should_show:
				continue

		var desired: Mesh
		if _is_mobile_profile() and fixture_force_lod_on_mobile:
			desired = fixture_lod_mesh
		elif adaptive_mobile:
			desired = fixture_high_mesh if _fixture_full_detail_enabled else fixture_lod_mesh
		else:
			desired = fixture_lod_mesh if nearest_squared > threshold_squared else fixture_high_mesh
		if batch.multimesh.mesh != desired:
			batch.multimesh.mesh = desired

# ODISEA_FORCE_MOBILE_PROFILE=1 permite ejercitar la ruta movil desde desktop.
func _is_mobile_profile() -> bool:
	if OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


func _update_adaptive_fixture_quality() -> void:
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	if _fixture_full_detail_enabled:
		_fixture_high_fps_seconds = 0.0
		_fixture_low_fps_seconds = _fixture_low_fps_seconds + refresh_interval if fps < fixture_lod_fallback_fps else 0.0
		if _fixture_low_fps_seconds >= fixture_lod_fallback_seconds:
			_fixture_full_detail_enabled = false
			_fixture_low_fps_seconds = 0.0
			_publish_fixture_quality("lod", fps)
	else:
		_fixture_low_fps_seconds = 0.0
		_fixture_high_fps_seconds = _fixture_high_fps_seconds + refresh_interval if fps > fixture_full_detail_fps else 0.0
		if _fixture_high_fps_seconds >= fixture_full_detail_hold_seconds:
			_fixture_full_detail_enabled = true
			_fixture_high_fps_seconds = 0.0
			_publish_fixture_quality("full", fps)

func _publish_fixture_quality(mode: String, fps: float) -> void:
	_fixture_quality_reported = true
	var telemetry := get_node_or_null("/root/ANNAV2")
	if telemetry and telemetry.has_method("register_telemetry_point"):
		telemetry.register_telemetry_point("fixture_quality", {
			"mode": mode,
			"fps": fps,
			"source": String(get_path())
		})

func _step_pending_activation_sound(delta: float) -> void:
	if _activation_sound_pending_delay < 0.0:
		return
	_activation_sound_pending_delay -= delta
	if _activation_sound_pending_delay > 0.0:
		return
	_activation_sound_pending_delay = -1.0
	if not is_instance_valid(_activation_sound_player):
		return
	var camera: Camera = get_viewport().get_camera() if get_viewport() else null
	if not _is_visible_to_camera(camera, _activation_sound_pending_position):
		return
	_activation_sound_player.global_transform.origin = _activation_sound_pending_position
	_activation_sound_player.play()
	_activation_sound_cooldown = activation_sound_debounce

func _is_visible_to_camera(camera: Camera, world_position: Vector3) -> bool:
	if camera == null or camera.is_position_behind(world_position):
		return false
	var viewport: Viewport = camera.get_viewport()
	if viewport == null:
		return true
	if not viewport.get_visible_rect().has_point(camera.unproject_position(world_position)):
		return false
	var space: PhysicsDirectSpaceState = get_world().direct_space_state
	if space == null:
		return true
	var hit: Dictionary = space.intersect_ray(camera.global_transform.origin, world_position)
	if hit.empty():
		return true
	if not hit.has("position"):
		return false
	var hit_position: Vector3 = hit["position"]
	return hit_position.distance_to(world_position) < 0.75

func _ensure_light_pool() -> void:
	while _lights.size() > light_pool_size:
		var extra: Node = _lights.pop_back()
		remove_child(extra)
		extra.free()
	while _lights.size() < light_pool_size:
		var light := OmniLight.new()
		light.name = "PathLight_%d" % _lights.size()
		light.omni_range = light_range
		light.light_energy = light_energy
		light.light_color = lit_color
		light.light_cull_mask = light_cull_mask
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)

func _find_player() -> Spatial:
	var players: Array = get_tree().get_nodes_in_group(PLAYER_GROUP)
	for candidate in players:
		if candidate is Spatial:
			return candidate as Spatial
	return null

func _clear_markers() -> void:
	var markers: Node = get_node_or_null(MARKERS_NAME)
	if markers:
		remove_child(markers)
		markers.free()
	for light in _lights:
		if is_instance_valid(light):
			remove_child(light)
			light.free()
	_lights = []

func _scene_owner() -> Node:
	if owner:
		return owner
	if Engine.editor_hint and get_tree():
		return get_tree().edited_scene_root
	return null
