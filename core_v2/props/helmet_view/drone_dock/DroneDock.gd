tool
extends PropBaseV2
class_name DroneDock

var pad_mat: Material

func _ready():
    ._ready()
    var pad = get_node_or_null("HoloPad")
    if pad:
        pad_mat = pad.get_surface_material(0)
        if pad_mat:
            pad_mat = pad_mat.duplicate()
            pad.set_surface_material(0, pad_mat)

func _update_visuals():
    # Holographic landing pad shader
    if pad_mat and pad_mat is ShaderMaterial:
        pad_mat.set_shader_param("activation", anim_progress)
    
    # Beacon light
    var light = get_node_or_null("BeaconLight")
    if light:
        light.light_energy = anim_progress * 3.0
    
    # Dust/energy particles
    var particles = get_node_or_null("DustParticles")
    if particles:
        particles.emitting = anim_progress > 0.1
        particles.speed_scale = 0.5 + 1.5 * anim_progress
