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
# Material unico de la malla de paneles fusionada (antes habia uno por panel).
var _panels_material: ShaderMaterial = null

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
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float edge_fade = 1.0;
uniform float transparency_min = 0.3;
uniform float transparency_max = 0.95;
uniform float floor_protect_radius = 1.0;
uniform bool stable_mobile_dither = false;
varying vec3 world_pos;

void vertex() {
    world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float occlusion_noise(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
    if (is_active > 0.5) {
        vec3 cam_to_player = player_pos - camera_pos;
        float dist_cam_player = length(cam_to_player);
        vec3 direction = cam_to_player / max(dist_cam_player, 0.001);
        float along = dot(world_pos - camera_pos, direction);
        if (along > 0.1 && along < dist_cam_player) {
            vec3 projection = camera_pos + direction * along;
            float radial = distance(world_pos, projection);
            float radius = hole_radius * edge_fade
                * (1.0 - smoothstep(dist_cam_player - 1.5, dist_cam_player, along));
            if (radial < radius && radius > 0.01) {
                float depth = 1.0 - radial / radius;
                float transparency = mix(transparency_min, transparency_max, depth);
                if (occlusion_noise(FRAGCOORD.xy) < transparency) {
                    discard;
                }
            }
        }
    }
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
    # PropDitherManager can't sniff Shader.code for player_pos/camera_pos/is_active
    # under the headless Dummy rasterizer (CI never populates it there), so tag the
    # shader directly instead of relying on that check.
    _shader.set_meta("odisea_occlusion_uniforms", true)
    _poles_material = SpatialMaterial.new()
    _poles_material.albedo_color = fence_color
    _poles_material.metallic = 0.9
    _poles_material.roughness = 0.6

func _update_materials():
    if _poles_material:
        _poles_material.albedo_color = fence_color
        
    # Los paneles ahora son una sola malla con un solo material, no un MeshInstance por
    # panel: alcanza con tocar ese material.
    if _panels_material:
        _panels_material.set_shader_param("fence_color", fence_color)

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
    # Los postes son todos la MISMA malla con el MISMO material: solo cambia la posicion.
    # Uno por poste eran N+1 MeshInstance, y en GLES2 con iluminacion forward cada luz
    # re-envia la geometria que toca, asi que cada malla suelta se paga varias veces. Medido
    # en Dome_Intro (14 paneles, 10 luces), la reja entera costaba 143 draw calls, el 18% de
    # la escena. Un MultiMeshInstance los dibuja de una sola vez, sin cambiar un pixel.
    var poles_mm := MultiMesh.new()
    poles_mm.transform_format = MultiMesh.TRANSFORM_3D
    poles_mm.mesh = pole_mesh
    poles_mm.instance_count = panel_count + 1

    var points = []
    for i in range(panel_count + 1):
        var offset = (float(i) / float(panel_count)) * total_length
        var p = curve.interpolate_baked(offset)
        points.append(p)

        # Adjust Y so bottom of pole is exactly on the curve
        var pos = p
        pos.y += height * 0.5
        poles_mm.set_instance_transform(i, Transform(Basis(), pos))

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

    var poles_node := MultiMeshInstance.new()
    poles_node.name = "Poles"
    poles_node.multimesh = poles_mm
    poles_node.material_override = _poles_material
    _container.add_child(poles_node)

    # Los paneles se fusionan en UNA malla. Cada uno tenia su propio ShaderMaterial que solo
    # se diferenciaba en `tiling`, y el shader hace `uv = UV * tiling`: horneando ese factor
    # en las UVs, un unico material da un resultado identico pixel a pixel.
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hay_panel := false

    # Generate panels between points
    for i in range(panel_count):
        var p_start = points[i]
        var p_end = points[i + 1]
        
        var segment_dir = p_end - p_start
        var segment_len = segment_dir.length()
        if segment_len < 0.01:
            continue
            
        var center = (p_start + p_end) * 0.5
        
        var quad = QuadMesh.new()
        quad.size = Vector2(segment_len, height)

        center.y += height * 0.5
        var forward = segment_dir.normalized()
        var panel_basis = _build_segment_basis(forward)
        var panel_xform := Transform(panel_basis, center)
        # El mismo factor que antes iba al uniform `tiling` de este panel.
        var tiling := Vector2(segment_len * 6.0, height * 6.0)
        _append_panel(st, quad, panel_xform, tiling)
        hay_panel = true

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

    if hay_panel:
        st.generate_tangents()
        var panels_node := MeshInstance.new()
        panels_node.name = "Panels"
        panels_node.mesh = st.commit()
        _panels_material = ShaderMaterial.new()
        _panels_material.shader = _shader
        _panels_material.set_shader_param("fence_color", fence_color)
        # El tiling ya quedo horneado en las UVs de cada panel; aca tiene que ser neutro.
        _panels_material.set_shader_param("tiling", Vector2.ONE)
        panels_node.material_override = _panels_material
        _panel_material_cache.append(_panels_material)
        _container.add_child(panels_node)


# Copia un panel dentro de la malla acumulada, llevandolo al espacio del contenedor y
# multiplicando sus UV por el tiling que antes viajaba como uniform. Se emiten triangulos
# sueltos porque cada panel trae su propio indice y no se pueden concatenar sin reindexar.
func _append_panel(st: SurfaceTool, quad: QuadMesh, xform: Transform, tiling: Vector2) -> void:
    var arrays: Array = quad.surface_get_arrays(0)
    var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    # QuadMesh no trae array de indices: sus vertices ya vienen en orden de triangulos. Sin
    # este caso el bucle no emitia NADA y la malla fusionada salia vacia — los paneles
    # desaparecian de la escena en silencio.
    var orden := []
    var idx = arrays[Mesh.ARRAY_INDEX]
    if idx != null and idx.size() > 0:
        for k in range(idx.size()):
            orden.append(idx[k])
    else:
        for k in range(verts.size()):
            orden.append(k)
    var base: Basis = xform.basis
    for v in orden:
        st.add_normal(base.xform(norms[v]).normalized())
        st.add_uv(Vector2(uvs[v].x * tiling.x, uvs[v].y * tiling.y))
        st.add_vertex(xform.xform(verts[v]))


func _build_segment_basis(forward: Vector3) -> Basis:
    if forward.length_squared() < 0.0001:
        return Basis()

    var x_axis = forward.normalized()
    var z_axis = x_axis.cross(Vector3.UP).normalized()
    if z_axis.length_squared() < 0.0001:
        z_axis = Vector3.FORWARD
    var y_axis = z_axis.cross(x_axis).normalized()
    return Basis(x_axis, y_axis, z_axis)
