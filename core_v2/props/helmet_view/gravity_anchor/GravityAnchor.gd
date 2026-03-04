tool
extends PropBaseV2
class_name GravityAnchor

var field_mat: Material

func _ready():
    ._ready()
    var field = get_node_or_null("GravityField")
    if field:
        field_mat = field.get_surface_material(0)
        if field_mat:
            field_mat = field_mat.duplicate()
            field.set_surface_material(0, field_mat)

func _update_visuals():
    # Gravity field shader
    if field_mat and field_mat is ShaderMaterial:
        field_mat.set_shader_param("stability", anim_progress)
    
    # Anchor light
    var light = get_node_or_null("AnchorLight")
    if light:
        light.light_energy = anim_progress * 3.0
        light.light_color = Color(1, 0.4, 0).linear_interpolate(Color(0, 1, 1), anim_progress)
    
    # Particles fall inward when stable
    var particles = get_node_or_null("FieldParticles")
    if particles:
        particles.emitting = anim_progress > 0.05
        particles.speed_scale = 0.5 + 1.5 * anim_progress
