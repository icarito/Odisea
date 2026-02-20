extends AudioStreamPlayer3D
class_name FootstepDetector

export(Resource) var generic_fallback_profile setget set_generic_profile
export(Resource) var footstep_material_library
export(float) var stride_length_walk: float = 0.9
export(float) var stride_length_run: float = 2.0
export(float) var walk_speed_threshold: float = 3.0

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
	var result = space_state.intersect_ray(from, to, exclude)
	
	if result and not result.empty():
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
	if collider.get("footstep_profile"):
		_play_from_profile(collider.footstep_profile)
		return true
	
	# Check children recursively for FootstepSurface node
	var surface = _find_first_node_by_type(collider, "Node") # "FootstepSurface" might not be a class?
	# Assuming FootstepSurface is a script with class_name
	surface = _find_first_child_with_property(collider, "footstep_profile")
	if surface and surface.footstep_profile:
		_play_from_profile(surface.footstep_profile)
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
		if property in child:
			return child
		var res = _find_first_child_with_property(child, property)
		if res: return res
	return null
