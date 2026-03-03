tool
extends PropBaseV2
class_name FusionCore

var mat: Material

func _ready():
    ._ready()
    var mesh_inst = get_node_or_null("Mesh")
    if mesh_inst and mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
        var m = mesh_inst.mesh.surface_get_material(0)
        if m:
            mat = m.duplicate()
            mesh_inst.mesh.surface_set_material(0, mat)

func _update_visuals():
    if mat and mat is ShaderMaterial:
        mat.set_shader_param("charge_level", anim_progress)
