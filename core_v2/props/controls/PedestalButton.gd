extends PropBaseV2
class_name PedestalButton
tool

# PedestalButton.gd
# A simple button prop that toggles state when interacted with.
# Can be used as an input for OLCS logic.

export(Color) var color_active = Color(0.0, 1.0, 0.0) # Green
export(Color) var color_inactive = Color(1.0, 0.0, 0.0) # Red
export(NodePath) var light_mesh_path
export(bool) var momentary = false
export(float) var momentary_duration = 0.5

onready var light_mesh = get_node_or_null(light_mesh_path)

# The indicator material has to belong to this button alone. ElevatorController
# clones its floors with Node.duplicate(), which shares resources rather than
# copying them, so every landing ended up writing the same material and lighting
# up together. resource_local_to_scene does not help: the flag survives the
# duplicate, it just stops being true of the instance.
var _owns_light_material := false

func _ready():
    # Ensure visual state matches initial logic state
    _update_visuals()

var _momentary_timer = null

func interact():
    if momentary:
        set_active(true, true)
        
        if _momentary_timer:
            _momentary_timer.disconnect("timeout", self , "_on_momentary_timeout")
            _momentary_timer = null

        if not Engine.editor_hint:
            _momentary_timer = get_tree().create_timer(momentary_duration)
            _momentary_timer.connect("timeout", self , "_on_momentary_timeout")
    else:
        # Toggle state
        set_active(not is_active, true)

func _on_momentary_timeout():
    set_active(false, true)
    _momentary_timer = null

func _update_visuals():
    if not is_inside_tree():
        return

    var color = color_active if is_active else color_inactive

    if light_mesh:
        var mat = _own_light_material()
        if mat is SpatialMaterial:
            mat.albedo_color = color
            mat.emission_enabled = true
            mat.emission = color
            mat.emission_energy = 1.0 if is_active else 0.2


# Returns this button's private indicator material, making one on first use.
# The ButtonMesh is in the no_occlusion group so PropDitherManager leaves it be:
# the prop layer otherwise gets its SpatialMaterial swapped for the dither
# shader, and the indicator stops changing colour altogether.
func _own_light_material():
    if light_mesh == null:
        return null
    var mat = light_mesh.material_override
    if not _owns_light_material or mat == null:
        mat = mat.duplicate() if mat != null else SpatialMaterial.new()
        mat.resource_local_to_scene = true
        light_mesh.material_override = mat
        _owns_light_material = true
    return mat

# Optional: expose state change for editor tweaking
func set_active(value: bool, immediate: bool = false):
    .set_active(value, immediate) # Call parent to update state and anim_progress
    _update_visuals()
