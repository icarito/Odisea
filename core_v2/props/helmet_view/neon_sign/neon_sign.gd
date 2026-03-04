tool
extends PropBaseV2

func _ready():
    pass

func _update_visuals():
    if has_node("NeonLight"):
        var light = $NeonLight
        light.light_energy = 2.0 * anim_progress

    if has_node("NeonTube"):
        var mat = $NeonTube.get_surface_material(0)
        if mat and mat is SpatialMaterial:
            mat = mat.duplicate()
            mat.emission_energy = 3.0 * anim_progress
            $NeonTube.set_surface_material(0, mat)
