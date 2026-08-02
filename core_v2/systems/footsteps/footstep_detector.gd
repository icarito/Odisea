extends AudioStreamPlayer3D
class_name FootstepDetector

export(Resource) var generic_fallback_profile setget set_generic_profile
export(Resource) var footstep_material_library
export(float) var stride_length_walk: float = 0.9
export(float) var stride_length_run: float = 2.0
export(float) var walk_speed_threshold: float = 3.0
# Que capas cuentan como suelo pisable: Entorno (capa 1, bit 1) + Prop
# (capa 7, bit 64), que es donde viven los andamios de SteelGratePlatform.
# La mascara existe para que un agente que pase por debajo del pie (p.ej. el
# dron DDC) no se robe el rayo; si se deja solo en 1 el rayo ATRAVIESA el
# andamio y se oye el suelo de abajo.
export(int, LAYERS_3D_PHYSICS) var floor_collision_mask: int = 65

var last_result: Dictionary = {}
var parent_rid: RID

func _ready():
	yield (get_tree(), "idle_frame")
	var parent = get_parent()
	# Walk up until we find a CollisionObject (PhysicsBody/Area)
	while parent:
		if parent is CollisionObject:
			parent_rid = parent.get_rid()
			break
		parent = parent.get_parent()
	
	if not generic_fallback_profile:
		push_warning("FootstepDetector - No generic fallback footstep profile assigned")

func set_generic_profile(value: Resource):
	generic_fallback_profile = value

func play_footstep():
	_play_interaction("footstep")

func play_landing():
	_play_interaction("landing")

func _play_interaction(_interaction_type: String):
	var from = global_transform.origin
	var to = from + Vector3(0, -0.6, 0) # Increased length slightly
	var exclude = []
	if parent_rid:
		exclude = [parent_rid]
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(from, to, exclude, floor_collision_mask)
	
	if not result or result.empty():
		# Sin suelo bajo el pie no hay pisada: pasando por un hueco entre
		# andamios (o por el borde de un deck) el rayo no pega en nada, y
		# sonar el fallback aqui metia un paso "default" en el aire.
		last_result = {}
		return

	last_result = result
	var collider = result.collider

	if _play_by_footstep_surface(collider):
		return
	elif _play_by_material(collider):
		return

	if generic_fallback_profile:
		_play_from_profile(generic_fallback_profile)

func _play_by_footstep_surface(collider) -> bool:
	# Check if collider IS a FootstepSurface (requires class_name FootstepSurface)
	var direct_profile = collider.get("footstep_profile")
	if direct_profile:
		_play_from_profile(direct_profile)
		return true
	
	var surface = _find_footstep_surface(collider)
	if surface:
		var profile = surface.get("footstep_profile")
		if profile:
			_play_from_profile(profile)
			return true

	# Algunos props dejan el collider bajo una raiz visual y el marcador de
	# footstep como HERMANO. Solo se miran los hermanos directos: antes esto
	# recorria el subarbol entero del padre y, si el collider colgaba de la raiz
	# de la escena, terminaba adoptando el perfil de cualquier prop del nivel
	# (p.ej. el suelo liso de Dome_Intro sonaba a scaffold, o a dirt en la
	# escena de prueba) en vez de caer al generic_fallback_profile.
	var parent = collider.get_parent()
	if parent:
		var sibling_profile = _find_sibling_footstep_profile(parent, collider)
		if sibling_profile:
			_play_from_profile(sibling_profile)
			return true
	
	return false

func _play_by_material(collider) -> bool:
	if not footstep_material_library:
		return false
	
	var material = _get_surface_material(collider)
	if material and footstep_material_library.has_method("get_footstep_stream_by_material"):
		var profile = footstep_material_library.get_footstep_stream_by_material(material)
		if profile:
			_play_from_profile(profile)
			return true
	
	return false

func _get_surface_material(collider) -> Material:
	var mesh_instance = null
	
	if collider is CSGShape:
		if collider.material_override:
			return collider.material_override
		if collider.material:
			return collider.material
	elif collider is StaticBody or collider is RigidBody:
		if collider.get_parent() is MeshInstance:
			mesh_instance = collider.get_parent()
		else:
			# Find MeshInstance child
			mesh_instance = _find_first_node_by_type(collider, "MeshInstance")
	
	if mesh_instance and mesh_instance.mesh:
		var mesh = mesh_instance.mesh
		if mesh.get_surface_count() > 0:
			return mesh.surface_get_material(0)
	
	return null

func _play_from_profile(profile: Resource):
	if profile.has_method("get_random_stream"): # Check strict type or just logic
		var audio_stream = profile.get_random_stream()
		if audio_stream:
			pitch_scale = profile.get_random_pitch()
			unit_db = profile.get_random_volume_db()
			stream = audio_stream
			play()
	elif profile is AudioStream:
		_play_from_stream(profile)

func _play_from_stream(audio_stream: AudioStream):
	pitch_scale = rand_range(0.9, 1.1)
	unit_db = rand_range(-6.0, -2.0)
	stream = audio_stream
	play()

# Helper for Godot 3 (replacing find_children)
func _find_first_node_by_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name or (child.get_script() and child.get_script().resource_path.get_file().begins_with(type_name)):
			return child
		var res = _find_first_node_by_type(child, type_name)
		if res: return res
	return null

func _find_first_child_with_property(root: Node, property: String) -> Node:
	for child in root.get_children():
		if child.get(property) != null:
			return child
		var res = _find_first_child_with_property(child, property)
		if res: return res
	return null

# Busca un perfil SOLO entre los hermanos directos del collider (sin recursion).
# Una busqueda recursiva aqui se lleva puesto el nivel entero cuando el collider
# cuelga de la raiz de la escena.
func _find_sibling_footstep_profile(parent: Node, collider: Node) -> Resource:
	for child in parent.get_children():
		if child == collider:
			continue
		var profile = child.get("footstep_profile")
		if profile:
			return profile
	return null

func _find_footstep_surface(root: Node) -> Node:
	if not root:
		return null

	var named_surface = root.get_node_or_null("FootstepSurface")
	if named_surface:
		return named_surface

	return _find_first_child_with_property(root, "footstep_profile")
