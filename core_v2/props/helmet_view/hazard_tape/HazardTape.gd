tool
extends PropBaseV2
class_name HazardTape

var mat: Material

func _ready():
    ._ready()
    var mesh_inst = get_node_or_null("Mesh")
    if mesh_inst:
        mat = mesh_inst.get_surface_material(0)
        if mat:
            mat = mat.duplicate()
            mesh_inst.set_surface_material(0, mat)

func _update_visuals():
    if mat and mat is ShaderMaterial:
        # Subtle increase in speed and pulse when active
        mat.set_shader_param("scroll_speed", 0.3 + anim_progress * 1.0)
        mat.set_shader_param("pulse", anim_progress)
