extends PropBaseV2

func _ready():
    pass

func _update_visuals():
    var sprite = get_node_or_null("PlantSprite")
    if sprite:
        var mat = sprite.material_override
        if mat and mat is ShaderMaterial:
            mat.set_shader_param("activation", anim_progress)
            mat.set_shader_param("glitch_intensity", 0.01 + 0.08 * anim_progress)
        
        # Scale the sprite via scale property: 0.8 to 1.3
        sprite.scale = Vector3.ONE * (0.8 + 0.5 * anim_progress)

    var particles = get_node_or_null("AmbientParticles")
    if particles:
        particles.emitting = anim_progress > 0.01
        particles.amount = int(5 + 20 * anim_progress)
