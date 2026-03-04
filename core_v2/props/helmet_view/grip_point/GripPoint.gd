tool
extends PropBaseV2
class_name GripPoint

var indicator_mat: Material

func _ready():
    ._ready()
    var ring = get_node_or_null("IndicatorRing")
    if ring:
        indicator_mat = ring.get_surface_material(0)
        if indicator_mat:
            indicator_mat = indicator_mat.duplicate()
            ring.set_surface_material(0, indicator_mat)

func _update_visuals():
    # Indicator ring shader
    if indicator_mat and indicator_mat is ShaderMaterial:
        indicator_mat.set_shader_param("activation", anim_progress)
    
    # Grip light
    var light = get_node_or_null("GripLight")
    if light:
        light.light_energy = anim_progress * 3.0
