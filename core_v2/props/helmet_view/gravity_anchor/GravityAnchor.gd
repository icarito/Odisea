tool
extends PropBaseV2
class_name GravityAnchor

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
        mat.set_shader_param("stability", anim_progress)
