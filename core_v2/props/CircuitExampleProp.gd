extends Spatial

# CircuitExampleProp.gd
# Refactored for staircase circuit; adds two switches and one light.
# Provides interaction entry points for pipeline and visual ON/OFF feedback.

func interact():
    # Default pipeline interaction: toggle SwitchA
    var switch_a = get_node_or_null("SwitchA")
    if switch_a and switch_a.has_method("interact"):
        switch_a.interact()
        _update_visual_feedback()
        return


func interact_switch_a():
    var switch_a = get_node_or_null("SwitchA")
    if switch_a and switch_a.has_method("interact"):
        switch_a.interact()
        _update_visual_feedback()
        return true
    return false

func interact_switch_b():
    var switch_b = get_node_or_null("SwitchB")
    if switch_b and switch_b.has_method("interact"):
        switch_b.interact()
        _update_visual_feedback()
        return true
    return false

func _update_visual_feedback():
    # SwitchA feedback
    var switch_a = get_node_or_null("SwitchA")
    var visual_a = switch_a.get_node_or_null("Visual") if switch_a else null
    if visual_a:
        # Color yellow if on, gray if off
        visual_a.material_override = _get_switch_material(switch_a.is_active if switch_a else false)
    # SwitchB feedback
    var switch_b = get_node_or_null("SwitchB")
    var visual_b = switch_b.get_node_or_null("Visual") if switch_b else null
    if visual_b:
        visual_b.material_override = _get_switch_material(switch_b.is_active if switch_b else false)
    # Light feedback
    var light = get_node_or_null("Light")
    var visual_l = light.get_node_or_null("Visual") if light else null
    if visual_l:
        visual_l.material_override = _get_light_material(_is_light_on())

func _get_switch_material(is_on):
    var mat = SpatialMaterial.new()
    mat.albedo_color = Color(1, 1, 0) if is_on else Color(0.5, 0.5, 0.5)
    return mat

func _get_light_material(is_on):
    var mat = SpatialMaterial.new()
    mat.albedo_color = Color(1, 1, 1) if is_on else Color(0.2, 0.2, 0.2)
    return mat

func _is_light_on():
    var light = get_node_or_null("Light")
    # Try direct flag for deterministic replay, otherwise use cable/circuit connection
    if light and "is_active" in light:
        return light.is_active
    return false

func _ready():
    _update_visual_feedback()

func _physics_process(delta):
    # Poll visual feedback to reflect circuit changes
    _update_visual_feedback()
