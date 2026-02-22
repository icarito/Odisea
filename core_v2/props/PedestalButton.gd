extends PropBaseV2
class_name PedestalButton
tool

# PedestalButton.gd
# A simple button prop that toggles state when interacted with.
# Can be used as an input for OLCS logic.

signal interaction_started()
signal interaction_completed()

export(Color) var color_active = Color(0.0, 1.0, 0.0) # Green
export(Color) var color_inactive = Color(1.0, 0.0, 0.0) # Red
export(NodePath) var light_mesh_path
export(bool) var momentary = false
export(float) var momentary_duration = 0.5

onready var light_mesh = get_node_or_null(light_mesh_path)

func _ready():
    # Ensure visual state matches initial logic state
    _update_visuals()

func interact():
    if momentary:
        set_active(true)
        emit_signal("interaction_started")
        emit_signal("interaction_completed")
        if not Engine.editor_hint:
            yield(get_tree().create_timer(momentary_duration), "timeout")
            set_active(false)
    else:
        # Toggle state
        set_active(not is_active)
        emit_signal("interaction_started")
        emit_signal("interaction_completed")

func _update_visuals():
    if not is_inside_tree():
        return

    var color = color_active if is_active else color_inactive

    if light_mesh:
        var mat = light_mesh.material
        if not mat:
            mat = SpatialMaterial.new()
            light_mesh.material = mat

        # Ensure we are modifying a unique material instance or the shared one if intended
        # For simple props, usually we want unique instance to not affect others
        if mat is SpatialMaterial:
            mat.albedo_color = color
            mat.emission_enabled = true
            mat.emission = color
            mat.emission_energy = 1.0 if is_active else 0.2

# Optional: expose state change for editor tweaking
func set_active(value: bool):
    .set_active(value) # Call parent to update state and anim_progress
    _update_visuals()
