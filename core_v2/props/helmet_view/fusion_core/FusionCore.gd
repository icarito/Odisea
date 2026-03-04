tool
extends PropBaseV2
class_name FusionCore

var housing_mat: Material
var core_mat: Material

func _ready():
    ._ready()
    # Housing shader
    var housing = get_node_or_null("Housing")
    if housing:
        housing_mat = housing.get_surface_material(0)
        if housing_mat:
            housing_mat = housing_mat.duplicate()
            housing.set_surface_material(0, housing_mat)
    # Energy core shader
    var core = get_node_or_null("EnergyCore")
    if core:
        core_mat = core.get_surface_material(0)
        if core_mat:
            core_mat = core_mat.duplicate()
            core.set_surface_material(0, core_mat)

func _update_visuals():
    # Housing glow lines
    if housing_mat and housing_mat is ShaderMaterial:
        housing_mat.set_shader_param("charge_level", anim_progress)
    
    # Energy sphere plasma
    if core_mat and core_mat is ShaderMaterial:
        core_mat.set_shader_param("charge_level", anim_progress)
    
    # Core light
    var light = get_node_or_null("CoreLight")
    if light:
        light.light_energy = anim_progress * 4.0
    
    # Energy particles
    var particles = get_node_or_null("EnergyParticles")
    if particles:
        particles.emitting = anim_progress > 0.1
        particles.speed_scale = 0.3 + 2.0 * anim_progress
