tool
extends PropBaseV2
class_name SciFiLightPathV2

# SciFiLightPathV2.gd - Generates OmniLights along a Path child node.
# If no Curve3D is assigned, creates a default arc.

export(int, 2, 50) var light_count := 8 setget set_light_count
export(Color) var light_color := Color(0.2, 0.5, 1.0) setget set_light_color
export(float, 0.5, 5.0) var light_range := 1.5 setget set_light_range
export(float, 0.0, 5.0) var light_energy_max := 1.5
export(bool) var show_bulbs := true
export(float, 0.5, 20.0) var path_length := 4.0 # Length of the default arc
export(float, 0.0, 2.0) var path_height := 0.8 # Height of the default arc

var _path_node: Path = null
var _lights: Array = []
var _bulbs: Array = []
var _lights_container: Spatial = null

func _ready():
	._ready()
	# Find Path child
	for child in get_children():
		if child is Path:
			_path_node = child
			break
	
	# If no path, create one
	if not _path_node:
		_path_node = Path.new()
		_path_node.name = "Path"
		add_child(_path_node)
	
	# If no curve assigned, create a default arc
	if not _path_node.curve or _path_node.curve.get_point_count() < 2:
		var c = Curve3D.new()
		var half = path_length * 0.5
		c.add_point(Vector3(-half, 0, 0), Vector3.ZERO, Vector3(half * 0.3, path_height, 0))
		c.add_point(Vector3(0, path_height, 0), Vector3(-half * 0.3, 0, 0), Vector3(half * 0.3, 0, 0))
		c.add_point(Vector3(half, 0, 0), Vector3(-half * 0.3, path_height * 0.5, 0), Vector3.ZERO)
		_path_node.curve = c
	
	_lights_container = get_node_or_null("LightsContainer")
	if not _lights_container:
		_lights_container = Spatial.new()
		_lights_container.name = "LightsContainer"
		add_child(_lights_container)
	
	_generate_lights()
	_update_visuals()

func set_light_count(v: int) -> void:
	light_count = v
	if is_inside_tree():
		_generate_lights()

func set_light_color(v: Color) -> void:
	light_color = v
	_apply_color_to_all()

func set_light_range(v: float) -> void:
	light_range = v
	for light in _lights:
		if is_instance_valid(light):
			light.omni_range = v

func _apply_color_to_all():
	for light in _lights:
		if is_instance_valid(light):
			light.light_color = light_color
	for bulb in _bulbs:
		if is_instance_valid(bulb) and bulb.material_override is SpatialMaterial:
			bulb.material_override.emission = light_color

func _generate_lights():
	if not _lights_container:
		return
	
	# Clear existing
	for child in _lights_container.get_children():
		child.queue_free()
	_lights.clear()
	_bulbs.clear()
	
	if not _path_node or not _path_node.curve:
		return
	
	var curve = _path_node.curve
	if curve.get_point_count() < 2:
		return
	
	var total_length = curve.get_baked_length()
	if total_length < 0.01:
		return
	
	for i in range(light_count):
		var offset = (float(i) / float(light_count - 1)) * total_length if light_count > 1 else 0.0
		var pos = curve.interpolate_baked(offset)
		
		# Create light
		var omni = OmniLight.new()
		omni.name = "PathLight_%d" % i
		omni.translation = pos
		omni.light_color = light_color
		omni.omni_range = light_range
		omni.light_energy = light_energy_max
		omni.shadow_enabled = false
		_lights_container.add_child(omni)
		_lights.append(omni)
		
		# Create bulb mesh
		if show_bulbs:
			var bulb = MeshInstance.new()
			bulb.name = "Bulb_%d" % i
			var sphere = SphereMesh.new()
			sphere.radius = 0.05
			sphere.height = 0.1
			sphere.radial_segments = 8
			sphere.rings = 4
			bulb.mesh = sphere
			bulb.translation = pos
			
			var mat = SpatialMaterial.new()
			mat.emission_enabled = true
			mat.emission = light_color
			mat.emission_energy = 3.0
			mat.albedo_color = Color(0.05, 0.05, 0.05)
			bulb.material_override = mat
			_lights_container.add_child(bulb)
			_bulbs.append(bulb)

func _update_visuals() -> void:
	._update_visuals()
	var t = anim_progress
	for light in _lights:
		if is_instance_valid(light):
			light.light_energy = t * light_energy_max
	for bulb in _bulbs:
		if is_instance_valid(bulb) and bulb.material_override is SpatialMaterial:
			bulb.material_override.emission_energy = t * 3.0
