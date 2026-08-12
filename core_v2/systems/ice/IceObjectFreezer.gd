extends Node
class_name IceObjectFreezer

# FD-051: reemplaza el sistema anterior de "frost decals" (quads spawneados por raycast,
# ver git history de IceVisualBand.gd) por un overlay real sobre la geometría de los props.
#
# En vez de dispararle rayos al mundo para adivinar dónde pegar un parche, esto envuelve
# UNA vez los materiales de los props marcados (grupo ICE_FREEZABLE_GROUP) con un next_pass
# compartido (object_freeze_overlay.shader). Ese shader decide por-pixel si está congelado
# comparando su propia posición mundial contra un uniform compartido (`ice_height_world`):
# no hace falta re-escanear el mundo ni distinguir qué objeto está "tocando" el hielo, así
# que no hay costo de física corriendo todo el tiempo — solo una escritura de uniform por
# cambio de altura.
#
# Los MultiMeshInstance (criopods ya batcheados por RadialScatter, ver
# core_v2/tools/RadialScatter.gd) funcionan igual: cada instancia calcula su propio
# WORLD_MATRIX en el shader, así que el congelamiento por altura es correcto por-instancia
# sin necesitar INSTANCE_CUSTOM ni curar el batching.

const ICE_FREEZABLE_GROUP := "ice_freezable"
const FREEZE_SHADER := preload("res://core_v2/systems/ice/shaders/object_freeze_overlay.shader")
const MOBILE_MAX_WRAPPED_HEIGHT := 8.0

export(float) var freeze_band_height := 3.0
export(float) var rim_strength := 0.85
export(float) var self_illum := 0.6
# next_pass doubles the draw calls of anything it's chained to. Skipping geometry whose
# lowest point sits above this height keeps that cost off upper scaffold floors, ceilings,
# etc. that the rising ice will realistically never reach before the level resolves.
export(float) var max_wrap_height := 14.0
# Los grupos horneados de RadialScatter ya baked (get_child_count()!=0) solo agregan sus
# hijos Batched_* via call_deferred en su propio _ready(); un frame alcanza, pero se
# reintenta un par de veces más por si algún grupo todavía no resolvió el deferred.
export(int) var scan_attempts := 4
export(float) var scan_interval := 0.35

var _ice_level: Node = null
var _shared_material: ShaderMaterial = null
var _wrapped_meshes := {}
# Material base -> copia con el overlay de hielo encadenado. Ver _wrapped_copy_of.
var _wrapped_material_cache := {}
var _scans_done := 0

func _ready() -> void:
	if Engine.editor_hint:
		return
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = FREEZE_SHADER
	_shared_material.set_shader_param("freeze_band_height", freeze_band_height)
	_shared_material.set_shader_param("rim_strength", rim_strength)
	_shared_material.set_shader_param("self_illum", self_illum)
	# Most of the structural geometry this wraps (SpiralStairs, SpiralWalkways, HubSpokes,
	# most of Terrace) already carries PropDitherManager's cone-occlusion shader, which
	# discards fragments between the camera and the player. Registering the shared overlay
	# material there too feeds it the same player_pos/camera_pos/etc. every frame, so
	# object_freeze_overlay.shader's own copy of that cone discard (see the shader) stays
	# in lockstep with the base pass instead of leaving a solid sheet of ice floating where
	# the wall just dithered away.
	var dither_manager := get_node_or_null("/root/PropDitherManager")
	if dither_manager != null:
		dither_manager.register_material(_shared_material)
	call_deferred("_connect_ice_level")
	_schedule_scan()

func _schedule_scan() -> void:
	if _scans_done >= scan_attempts:
		return
	_scans_done += 1
	var timer := get_tree().create_timer(scan_interval)
	timer.connect("timeout", self, "_run_scan")

func _run_scan() -> void:
	if not is_instance_valid(self):
		return
	var roots := get_tree().get_nodes_in_group(ICE_FREEZABLE_GROUP)
	for root in roots:
		if is_instance_valid(root):
			_wrap_recursive(root)
	_schedule_scan()

func _connect_ice_level() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("ice_level")
	if systems.empty():
		return
	_ice_level = systems[0]
	if not is_instance_valid(_ice_level):
		return
	if not _ice_level.is_connected("ice_height_changed", self, "_on_ice_height_changed"):
		var _err = _ice_level.connect("ice_height_changed", self, "_on_ice_height_changed")
	_on_ice_height_changed(float(_ice_level.ice_height))

func _on_ice_height_changed(height: float) -> void:
	if is_instance_valid(_shared_material):
		_shared_material.set_shader_param("ice_height_world", height)
	for overlay in _cutout_materials:
		if is_instance_valid(overlay):
			overlay.set_shader_param("ice_height_world", height)

func _wrap_recursive(node: Node) -> void:
	if node is MeshInstance and node.mesh != null:
		if _min_world_y(node) <= max_wrap_height and not _is_oversized_mobile_mesh(node):
			_wrap_mesh_instance(node)
	elif node is MultiMeshInstance and node.multimesh != null:
		if _min_world_y(node) <= max_wrap_height:
			_wrap_multimesh_instance(node)
	for child in node.get_children():
		_wrap_recursive(child)

# La cascara del domo estaba EXENTA de la guarda de tamano en movil. La exencion se
# justificaba por seguridad (dome_wall_cylindrical.shader es opaco simple, sin discard, asi
# que encadenarle un next_pass no rompe nada), pero la guarda no existe por seguridad sino
# por COSTO: el next_pass duplica los draw calls de lo que envuelve, y el domo es la malla
# mas grande de la escena. En un telefono, sobre una escena que ademas multiplica ~15x por
# luces, eso se paga entero. La telemetria da 9-39 fps en Dome_Intro contra 55-60 en Menu.
#
# Sin la exencion, el domo (AABB de ~31 m de alto, muy por encima de MOBILE_MAX_WRAPPED_HEIGHT)
# queda fuera del envoltorio en movil: pierde la escarcha en sus paredes, conserva la del
# resto de los props, y deja de costar un segundo pase sobre toda su superficie.
func _is_oversized_mobile_mesh(instance: MeshInstance) -> bool:
	if not _is_mobile_profile():
		return false
	# La cascara del domo vuelve a estar exenta de la guarda de tamano. Se la habia sacado
	# para ahorrar el segundo pase del next_pass sobre la superficie mas grande de la escena,
	# pero no rindio: en desktop la diferencia fue 0.1 ms (ruido, y los cambios de material
	# subieron porque la copia cacheada del freezer batchea mejor que los materiales
	# originales), y en el dispositivo el build 353 dio 15.84 fps contra 15.90 del 352.
	# Como el corte si le quitaba la escarcha a las paredes del domo en movil, el saldo era
	# perder efecto visual a cambio de nada medible.
	if _uses_dome_wall_shader(instance):
		return false
	return instance.get_transformed_aabb().size.y > MOBILE_MAX_WRAPPED_HEIGHT


func _uses_dome_wall_shader(instance: MeshInstance) -> bool:
	for surface_index in range(instance.mesh.get_surface_count()):
		var material: Material = instance.get_surface_material(surface_index)
		if material == null:
			material = instance.mesh.surface_get_material(surface_index)
		if material is ShaderMaterial and material.shader != null \
			and material.shader.resource_path == "res://core_v2/levels/interiors/shaders/dome_wall_cylindrical.shader":
			return true
	return false


# ODISEA_FORCE_MOBILE_PROFILE=1 permite ejercitar la ruta movil desde desktop, para poder
# verificar estos cortes sin reexportar a un telefono.
func _is_mobile_profile() -> bool:
	if OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


func _min_world_y(instance: VisualInstance) -> float:
	return instance.get_transformed_aabb().position.y

func _wrap_mesh_instance(instance: MeshInstance) -> void:
	var key = instance.get_instance_id()
	if _wrapped_meshes.has(key):
		return
	_wrapped_meshes[key] = true
	var surface_count: int = instance.mesh.get_surface_count()
	for i in range(surface_count):
		# get_surface_material() only returns a per-instance override; baked static
		# meshes (SpiralStairs, SpiralWalkways, Terrace, HubSpokes) carry their material
		# straight on the Mesh resource instead, so that call comes back null for them
		# and this has to fall back to the mesh's own surface material.
		var base_material: Material = instance.get_surface_material(i)
		if base_material == null:
			base_material = instance.mesh.surface_get_material(i)
		if base_material == null:
			continue
		if not _can_wrap_material(base_material):
			continue
		instance.set_surface_material(i, _wrapped_copy_of(base_material))

func _wrap_multimesh_instance(instance: MultiMeshInstance) -> void:
	var key = instance.get_instance_id()
	if _wrapped_meshes.has(key):
		return
	_wrapped_meshes[key] = true
	if instance.material_override != null:
		if not _can_wrap_material(instance.material_override):
			return
		instance.material_override = _wrapped_copy_of(instance.material_override)
		return
	var mesh: Mesh = instance.multimesh.mesh
	if mesh == null:
		return
	for i in range(mesh.get_surface_count()):
		var base_material: Material = mesh.surface_get_material(i)
		if base_material == null:
			continue
		if not _can_wrap_material(base_material):
			continue
		mesh.surface_set_material(i, _wrapped_copy_of(base_material))

# Duplicate before chaining next_pass: many props share one base material across every
# instance (that sharing is what keeps them cheap to draw), and writing next_pass on the
# shared resource would freeze every instance of that material everywhere, not just the
# ones actually wrapped here.
#
# Pero la copia si se comparte entre todo lo que SI se envuelve: la copia es funcion pura
# del material base (duplicate + el mismo next_pass), asi que una copia por superficie solo
# multiplicaba materiales. Las 7 rebanadas de SpiralWalkways, que salen del horneado
# compartiendo 3 materiales, terminaban con 19 distintos: 19 cambios de material por frame
# en vez de 3, cero batching, y 19 materiales que PropDitherManager reescribe cada frame.
func _wrapped_copy_of(base_material: Material) -> Material:
	var cached = _wrapped_material_cache.get(base_material)
	if cached is Material:
		return cached
	var unique_material: Material = base_material.duplicate()
	unique_material.next_pass = _overlay_for(base_material)
	_wrapped_material_cache[base_material] = unique_material
	# Una copia envuelta que vuelve a entrar (dos MultiMeshInstance sobre la misma Mesh)
	# se reconoce a si misma y no encadena un segundo overlay.
	_wrapped_material_cache[unique_material] = unique_material
	_register_occlusion_copy(unique_material)
	return unique_material

func _register_occlusion_copy(material: Material) -> void:
	if not (material is ShaderMaterial):
		return
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material.shader == null:
		return
	var code: String = shader_material.shader.code
	if code.find("uniform vec3 player_pos") < 0 or code.find("uniform vec3 camera_pos") < 0 \
		or code.find("uniform float is_active") < 0:
		return
	var dither_manager := get_node_or_null("/root/PropDitherManager")
	if dither_manager != null:
		dither_manager.register_material(shader_material)

# Most of Dome_Intro's structural geometry (SpiralStairs, SpiralWalkways, HubSpokes, most
# of Terrace) uses PropDitherManager's cone-occlusion shader — safe to wrap now that the
# overlay replicates its discard (see object_freeze_overlay.shader) and is registered with
# PropDitherManager so it gets the same per-frame uniforms. dome_wall_cylindrical.shader is
# a plain opaque shader (no discard/blend at all) — trivially safe. Anything else is an
# unknown quantity: a generic next_pass can't reproduce an arbitrary shader's own discard
# or cutout rules, so it stays off the allowlist rather than risk drawing solid ice over
# hidden triangles or a mismatched coplanar pass.
const SAFE_SHADER_PATHS := [
	"res://shaders/prop_dither_occlusion.gdshader",
	"res://shaders/prop_dither_occlusion_double_sided.gdshader",
	"res://core_v2/levels/interiors/shaders/dome_wall_cylindrical.shader",
	"res://core_v2/props/scifi_lights/shaders/airlock_hull.shader",
	"res://core_v2/props/scifi_lights/shaders/airlock_floor.shader",
]
# Dither-shaded surfaces (SAFE_SHADER_PATHS entries only) that cut a grate/rail pattern out
# of a flat quad via their own texture alpha. A plain next_pass would draw solid ice across
# the whole quad, filling the gaps that texture normally hides — instead these get their
# own overlay instance below (_wrap_cutout_material) that samples the same texture.
var _cutout_materials: Array = []

func _can_wrap_material(material: Material) -> bool:
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		return shader_material.shader != null and shader_material.shader.resource_path in SAFE_SHADER_PATHS
	if material is SpatialMaterial:
		var spatial: SpatialMaterial = material as SpatialMaterial
		return not spatial.flags_transparent and not spatial.params_use_alpha_scissor
	return false

# Returns a fresh overlay instance configured to sample base_material's own cutout texture,
# or null if base_material isn't using a cutout (the caller should chain _shared_material
# instead in that case).
func _make_overlay_for(base_material: ShaderMaterial) -> ShaderMaterial:
	var use_scissor = base_material.get_shader_param("use_alpha_scissor")
	if use_scissor == null or not bool(use_scissor):
		return null
	var overlay := ShaderMaterial.new()
	overlay.shader = FREEZE_SHADER
	overlay.set_shader_param("freeze_band_height", freeze_band_height)
	overlay.set_shader_param("rim_strength", rim_strength)
	overlay.set_shader_param("self_illum", self_illum)
	overlay.set_shader_param("use_cutout", true)
	overlay.set_shader_param("cutout_texture", base_material.get_shader_param("texture_albedo"))
	var threshold = base_material.get_shader_param("alpha_scissor_threshold")
	overlay.set_shader_param("cutout_threshold", threshold if threshold != null else 0.0)
	var dither_manager := get_node_or_null("/root/PropDitherManager")
	if dither_manager != null:
		dither_manager.register_material(overlay)
	if is_instance_valid(_ice_level):
		overlay.set_shader_param("ice_height_world", float(_ice_level.ice_height))
	_cutout_materials.append(overlay)
	return overlay

# Chains the right overlay onto base_material (cutout-aware copy for grate/rail textures,
# the one shared instance for everything else) and returns it for the caller to assign.
func _overlay_for(base_material: Material) -> ShaderMaterial:
	if base_material is ShaderMaterial:
		var cutout_overlay := _make_overlay_for(base_material as ShaderMaterial)
		if cutout_overlay != null:
			return cutout_overlay
	return _shared_material
