tool
extends StaticBody

# AreaInfoScreen.gd - Interactive Information Panel

enum Preset { INFO, WARNING, DANGER, TERMINAL, HOLOGRAM }

export(String) var panel_title := "Information"
export(String) var panel_body := ""
export(Texture) var map_texture: Texture = null
export(Preset) var preset := Preset.INFO setget set_preset
export(bool) var show_icon := true
export(bool) var show_in_world_text := true
export(String) var world_text := ""
export(bool) var close_on_exit := true
export(float) var auto_read_timer := 0.0

const OVERLAY_SCENE = preload("res://core_v2/props/signage/InfoOverlay.tscn")
const PRESET_COLORS = {
	Preset.INFO: Color(0.0, 1.0, 1.0),     # Cyan
	Preset.WARNING: Color(1.0, 0.8, 0.0),  # Amber
	Preset.DANGER: Color(1.0, 0.2, 0.1),   # Red
	Preset.TERMINAL: Color(0.2, 1.0, 0.2), # Green
	Preset.HOLOGRAM: Color(0.5, 0.7, 1.0)  # Light Blue
}

var _player_in_range := false
var _overlay_instance: Node = null
var _auto_read_elapsed := 0.0

onready var proximity_area = $ProximityArea
onready var interaction_entity = $InteractableEntity
onready var viewport = $Viewport
onready var world_label = $Viewport/VBox/Title
onready var panel_mesh = $MeshInstance
onready var omni_light = $OmniLight

func _ready():
	if Engine.editor_hint: return
	
	add_to_group("info_screens")
	_update_marker()
	_update_world_visuals()
	
	proximity_area.connect("body_entered", self, "_on_body_entered")
	proximity_area.connect("body_exited", self, "_on_body_exited")

func _process(delta):
	if Engine.editor_hint: return
	
	if _player_in_range and auto_read_timer > 0.0 and _overlay_instance == null:
		_auto_read_elapsed += delta
		if _auto_read_elapsed >= auto_read_timer:
			_open_overlay()

func set_preset(v):
	preset = v
	if is_inside_tree():
		_update_world_visuals()
		_update_marker()

func _update_marker():
	if not interaction_entity: return
	
	var config = MarkerConfig.new()
	config.label = panel_title
	config.hint = "Leer"
	config.accent_color = PRESET_COLORS[preset]
	config.interaction_range = 2.5
	interaction_entity.set_marker_config(config)

func _update_world_visuals():
	var color = PRESET_COLORS[preset]
	
	if world_label:
		world_label.text = world_text if world_text != "" else panel_title
		world_label.add_color_override("font_color", color)
	
	if omni_light:
		omni_light.light_color = color
	
	if viewport:
		viewport.render_target_update_mode = Viewport.UPDATE_ONCE
		# Wait a frame for viewport to render if needed
		call_deferred("_apply_viewport_texture")

func _apply_viewport_texture():
	if not panel_mesh or not viewport: return
	var mat = panel_mesh.get_surface_material(0)
	if mat is SpatialMaterial:
		mat = mat.duplicate()
		mat.albedo_texture = viewport.get_texture()
		mat.emission_enabled = true
		mat.emission_texture = viewport.get_texture()
		mat.emission = Color.white
		mat.emission_energy = 1.0
		panel_mesh.set_surface_material(0, mat)

func _on_body_entered(body):
	if not body.is_in_group("player"): return
	_player_in_range = true
	_auto_read_elapsed = 0.0

func _on_body_exited(body):
	if not body.is_in_group("player"): return
	_player_in_range = false
	if close_on_exit and _overlay_instance:
		_overlay_instance.close()

func _input(event):
	if Engine.editor_hint: return
	if not _player_in_range: return
	
	if event.is_action_pressed("interact"):
		if _overlay_instance:
			_overlay_instance.close()
		else:
			_open_overlay()
		get_tree().set_input_as_handled()

func _open_overlay():
	if _overlay_instance: return
	
	_overlay_instance = OVERLAY_SCENE.instance()
	get_tree().root.add_child(_overlay_instance)
	_overlay_instance.setup(panel_title, panel_body, map_texture, PRESET_COLORS[preset])
	_overlay_instance.connect("closed", self, "_on_overlay_closed")
	_overlay_instance.open()
	
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").emit_signal("info_screen_read", panel_title)

func _on_overlay_closed():
	_overlay_instance = null
	_auto_read_elapsed = 0.0
