tool
extends PropBaseV2
class_name HazardTape

# HazardTape - Holographic barrier that generates panels along a Path.
# When inactive: subtle cyan holographic tape (no collision).
# When active: solid red barrier with collision (blocks player).

export(int, 2, 20) var panel_count := 6 setget set_panel_count
export(Color) var color_inactive := Color(1.0, 0.9, 0.3) setget set_color_inactive
export(Color) var color_active := Color(1.0, 0.1, 0.0)
export(float, 0.3, 3.0) var panel_height := 1.5
export(float, 0.5, 20.0) var path_length := 5.0
export(float, 0.0, 2.0) var path_height := 0.0

var _path_node: Path = null
var _panels: Array = []
var _collision_bodies: Array = []
var _container: Spatial = null
var _shader: Shader = null

func _ready():
	._ready()
	
	# Find or create Path
	for child in get_children():
		if child is Path:
			_path_node = child
			break
	
	if not _path_node:
		_path_node = Path.new()
		_path_node.name = "Path"
		add_child(_path_node)
	
	# Default straight line if no curve
	if not _path_node.curve or _path_node.curve.get_point_count() < 2:
		var c = Curve3D.new()
		var half = path_length * 0.5
		c.add_point(Vector3(-half, path_height, 0))
		c.add_point(Vector3(half, path_height, 0))
		_path_node.curve = c
	
	_container = get_node_or_null("PanelsContainer")
	if not _container:
		_container = Spatial.new()
		_container.name = "PanelsContainer"
		add_child(_container)
	
	_create_shader()
	_generate_panels()
	_update_visuals()

func set_panel_count(v: int) -> void:
	panel_count = v
	if is_inside_tree():
		_generate_panels()

func set_color_inactive(v: Color) -> void:
	color_inactive = v
	_update_visuals()

func _create_shader():
	_shader = Shader.new()
	_shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 tape_color : hint_color = vec4(0.0, 0.8, 1.0, 0.5);
uniform float activation : hint_range(0.0, 1.0) = 0.0;
uniform float danger : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Diagonal hazard stripes
	float stripe = step(0.5, fract((UV.x * 3.0 + UV.y * 1.5 - TIME * 0.4) * 2.0));
	
	// Scanlines
	float scan = sin(UV.y * 80.0 + TIME * 2.0) * 0.15 + 0.85;
	
	// Edge fade for holographic look
	float edge_y = smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.9, UV.y);
	
	// Flicker when transitioning
	float flicker = mix(1.0, step(0.1, fract(sin(TIME * 30.0) * 100.0)), danger * (1.0 - danger));
	
	float alpha_base = mix(0.12, 0.6, activation);
	
	ALBEDO = tape_color.rgb * scan * (0.5 + stripe * 0.5) * flicker;
	ALPHA = alpha_base * edge_y * flicker;
}
"""

func _generate_panels():
	if not _container:
		return
	
	for child in _container.get_children():
		child.queue_free()
	_panels.clear()
	_collision_bodies.clear()
	
	if not _path_node or not _path_node.curve:
		return
	
	var curve = _path_node.curve
	if curve.get_point_count() < 2:
		return
	
	var total_length = curve.get_baked_length()
	if total_length < 0.01:
		return
	
	# Generate panels between consecutive points along the path
	for i in range(panel_count):
		var offset_start = (float(i) / float(panel_count)) * total_length
		var offset_end = (float(i + 1) / float(panel_count)) * total_length
		var pos_start = curve.interpolate_baked(offset_start)
		var pos_end = curve.interpolate_baked(offset_end)
		
		var center = (pos_start + pos_end) * 0.5
		var segment_dir = pos_end - pos_start
		var segment_len = segment_dir.length()
		
		if segment_len < 0.01:
			continue
		
		# Create panel mesh
		var panel = MeshInstance.new()
		panel.name = "Panel_%d" % i
		var quad = QuadMesh.new()
		quad.size = Vector2(segment_len * 1.05, panel_height)
		panel.mesh = quad
		
		# Panel material
		var mat = ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_param("tape_color", Color(color_inactive.r, color_inactive.g, color_inactive.b, 0.5))
		mat.set_shader_param("activation", 0.0)
		mat.set_shader_param("danger", 0.0)
		panel.material_override = mat
		
		# Position and orient panel
		center.y += panel_height * 0.5
		panel.translation = center
		
		# Look along the segment direction
		if segment_dir.normalized().abs() != Vector3.UP:
			var look_target = center + segment_dir.normalized()
			look_target.y = center.y
			# Use basis to face perpendicular to path
			var forward = segment_dir.normalized()
			var up = Vector3.UP
			var right = forward.cross(up).normalized()
			if right.length() > 0.001:
				var actual_up = right.cross(forward).normalized()
				panel.transform = Transform(Basis(right, actual_up, forward), center)
				# Rotate 90 degrees on Y to face the barrier outward
				panel.rotate_y(PI * 0.5)
		
		_container.add_child(panel)
		_panels.append(panel)
		
		# Create collision body (starts disabled)
		var body = StaticBody.new()
		body.name = "Barrier_%d" % i
		var col_shape = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = Vector3(segment_len * 0.5, panel_height * 0.5, 0.05)
		col_shape.shape = box
		body.add_child(col_shape)
		body.translation = center
		if segment_dir.normalized().abs() != Vector3.UP:
			var forward = segment_dir.normalized()
			var up = Vector3.UP
			var right = forward.cross(up).normalized()
			if right.length() > 0.001:
				var actual_up = right.cross(forward).normalized()
				body.transform = Transform(Basis(right, actual_up, forward), center)
		
		# Disabled by default
		col_shape.disabled = true
		
		_container.add_child(body)
		_collision_bodies.append({"body": body, "shape": col_shape})

func _update_visuals() -> void:
	var t = anim_progress
	var is_danger = t > 0.5
	var danger_val = clamp((t - 0.5) * 2.0, 0.0, 1.0)
	
	# Update panel materials
	for panel in _panels:
		if not is_instance_valid(panel):
			continue
		var mat = panel.material_override
		if mat and mat is ShaderMaterial:
			# Color transition: cyan -> red when danger
			var col = color_inactive.linear_interpolate(color_active, danger_val)
			mat.set_shader_param("tape_color", Color(col.r, col.g, col.b, 0.5))
			mat.set_shader_param("activation", t)
			mat.set_shader_param("danger", danger_val)
	
	# Enable/disable collision based on activation
	for data in _collision_bodies:
		var shape = data.get("shape", null)
		if shape and is_instance_valid(shape):
			shape.disabled = not is_danger
