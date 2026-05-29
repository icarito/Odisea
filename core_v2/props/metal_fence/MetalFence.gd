tool
extends PropBaseV2
class_name MetalFence

# MetalFence - A path-based metallic fence prop
# Can be cut or deformed in the future.

export(int, 2, 50) var panel_count := 8 setget set_panel_count
export(Color) var fence_color := Color(0.35, 0.35, 0.35) setget set_fence_color
export(float, 0.5, 100.0, 0.1) var height := 2.5 setget set_height
export(float, 1.0, 50.0) var path_length := 8.0 setget set_path_length
export(float, -10.0, 10.0) var path_height := 0.0 setget set_path_height
const PROP_LAYER := 64 # Layer 7: Prop

var _path_node: Path = null
var _container: Spatial = null
var _shader: Shader = null
var _poles_material: SpatialMaterial = null
var _panel_material_cache: Array = []

func _init():
    is_interactable = false

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
        
    if _path_node:
        # Clone curve so instances don't share it
        if _path_node.curve and _path_node.curve.resource_path != "":
            _path_node.curve = _path_node.curve.duplicate(true)
            
    # Default straight line if no curve
    if not _path_node.curve or _path_node.curve.get_point_count() < 2:
        var c = Curve3D.new()
        var half = path_length * 0.5
        c.add_point(Vector3(-half, path_height, 0))
        c.add_point(Vector3(half, path_height, 0))
        _path_node.curve = c
        
    _container = get_node_or_null("FenceContainer")
    if not _container:
        _container = Spatial.new()
        _container.name = "FenceContainer"
        add_child(_container)
        
    _create_materials()
    _generate_fence()
    _connect_path_curve()

func set_panel_count(v: int) -> void:
    panel_count = v
    if is_inside_tree():
        _generate_fence()

func _connect_path_curve() -> void:
    if _path_node and _path_node.curve:
        if not _path_node.curve.is_connected("changed", self , "_on_curve_changed"):
            _path_node.curve.connect("changed", self , "_on_curve_changed")

func _on_curve_changed() -> void:
    if is_inside_tree():
        _generate_fence()

func set_fence_color(v: Color) -> void:
    fence_color = v
    if is_inside_tree():
        _update_materials()

func set_height(v: float) -> void:
    height = v
    if is_inside_tree():
        _generate_fence()

func set_path_length(v: float) -> void:
    path_length = v
    if is_inside_tree() and _path_node and _path_node.curve:
        var c = _path_node.curve
        if c.get_point_count() == 2:
            var half = path_length * 0.5
            c.set_point_position(0, Vector3(-half, path_height, 0))
            c.set_point_position(1, Vector3(half, path_height, 0))
        # _generate_fence() is called via _on_curve_changed

func set_path_height(v: float) -> void:
    path_height = v
    if is_inside_tree() and _path_node and _path_node.curve:
        var c = _path_node.curve
        for i in range(c.get_point_count()):
            var p = c.get_point_position(i)
            p.y = path_height
            c.set_point_position(i, p)
        # _generate_fence() is called via _on_curve_changed

func _create_materials():
    _shader = Shader.new()
    _shader.code = """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 fence_color : hint_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform vec2 tiling = vec2(10.0, 10.0);
uniform float wire_thickness : hint_range(0.01, 0.5) = 0.08;

void fragment() {
    vec2 uv = UV * tiling;
    
    // Create chainlink diamond pattern
    vec2 grid_uv = fract(vec2(uv.x + uv.y, uv.x - uv.y) * 0.5);
    
    float line_x = step(grid_uv.x, wire_thickness) + step(1.0 - wire_thickness, grid_uv.x);
    float line_y = step(grid_uv.y, wire_thickness) + step(1.0 - wire_thickness, grid_uv.y);
    
    float alpha = clamp(max(line_x, line_y), 0.0, 1.0);
    
    if (alpha < 0.5) {
        discard;
    }
    
    ALBEDO = fence_color.rgb * 0.8;
    METALLIC = 1.0;
    ROUGHNESS = 0.5;
    
    // Ambient occlusion roughly on wire edges 
    vec2 center_dist = abs(grid_uv - 0.5) * 2.0;
    float d = max(center_dist.x, center_dist.y);
    float ao = smoothstep(1.0 - wire_thickness * 2.0, 1.0, d);
    ALBEDO *= mix(1.0, 0.5, ao);
}
"""
    _poles_material = SpatialMaterial.new()
    _poles_material.albedo_color = fence_color
    _poles_material.metallic = 0.9
    _poles_material.roughness = 0.6

func _update_materials():
    if _poles_material:
        _poles_material.albedo_color = fence_color
        
    if _container:
        for child in _container.get_children():
            if child is MeshInstance and child.name.begins_with("FencePanel"):
                var mat = child.material_override as ShaderMaterial
                if mat:
                    mat.set_shader_param("fence_color", fence_color)

func _generate_fence():
    if not _container:
        return
        
    _panel_material_cache.clear()

    for child in _container.get_children():
        child.queue_free()
        
    if not _path_node or not _path_node.curve:
        return
        
    var curve = _path_node.curve
    if curve.get_point_count() < 2:
        return
        
    var total_length = curve.get_baked_length()
    if total_length < 0.01:
        return
        
    var pole_radius := 0.05
    var pole_mesh = CylinderMesh.new()
    pole_mesh.top_radius = pole_radius
    pole_mesh.bottom_radius = pole_radius
    pole_mesh.height = height
    pole_mesh.radial_segments = 8
    
    # Generate points along the path
    var points = []
    for i in range(panel_count + 1):
        var offset = (float(i) / float(panel_count)) * total_length
        var p = curve.interpolate_baked(offset)
        points.append(p)
        
        # Create pole
        var pole = MeshInstance.new()
        pole.name = "Pole_%d" % i
        pole.mesh = pole_mesh
        pole.material_override = _poles_material
        
        # Adjust Y so bottom of pole is exactly on the curve
        var pos = p
        pos.y += height * 0.5
        pole.translation = pos
        _container.add_child(pole)
        
        var p_body = StaticBody.new()
        p_body.name = "PoleBody_%d" % i
        p_body.collision_layer = PROP_LAYER
        p_body.collision_mask = 255
        var p_col = CollisionShape.new()
        var p_cyl = CylinderShape.new()
        p_cyl.radius = pole_radius
        p_cyl.height = height
        p_col.shape = p_cyl
        p_body.add_child(p_col)
        p_body.translation = pos
        _container.add_child(p_body)
        
    # Generate panels between points
    for i in range(panel_count):
        var p_start = points[i]
        var p_end = points[i + 1]
        
        var segment_dir = p_end - p_start
        var segment_len = segment_dir.length()
        if segment_len < 0.01:
            continue
            
        var center = (p_start + p_end) * 0.5
        
        var panel = MeshInstance.new()
        panel.name = "FencePanel_%d" % i
        var quad = QuadMesh.new()
        quad.size = Vector2(segment_len, height)
        panel.mesh = quad
        
        var mat = ShaderMaterial.new()
        mat.shader = _shader
        mat.set_shader_param("fence_color", fence_color)
        mat.set_shader_param("tiling", Vector2(segment_len * 6.0, height * 6.0))
        panel.material_override = mat
        
        center.y += height * 0.5
        panel.translation = center
        
        var forward = segment_dir.normalized()
        var panel_basis = _build_segment_basis(forward)
        panel.transform = Transform(panel_basis, center)

        _container.add_child(panel)
        _panel_material_cache.append(mat)
        
        var body = StaticBody.new()
        body.name = "FenceBarrier_%d" % i
        body.collision_layer = PROP_LAYER
        body.collision_mask = 255
        var col_shape = CollisionShape.new()
        var box = BoxShape.new()
        box.extents = Vector3(segment_len * 0.5, height * 0.5, 0.02)
        col_shape.shape = box
        body.add_child(col_shape)
        
        body.translation = center
        body.transform = Transform(panel_basis, center)
                
        _container.add_child(body)

func _build_segment_basis(forward: Vector3) -> Basis:
    if forward.length_squared() < 0.0001:
        return Basis()

    var x_axis = forward.normalized()
    var z_axis = x_axis.cross(Vector3.UP).normalized()
    if z_axis.length_squared() < 0.0001:
        z_axis = Vector3.FORWARD
    var y_axis = z_axis.cross(x_axis).normalized()
    return Basis(x_axis, y_axis, z_axis)
