tool
extends StaticBody

# AreaInfoScreen.gd - Interactive Information Panel

enum Preset { INFO, WARNING, DANGER, TERMINAL, HOLOGRAM }

export(String) var panel_title := "Information" setget set_panel_title
export(String) var screen_id := ""
export(String, MULTILINE) var panel_body := "" setget set_panel_body
export(Texture) var map_texture: Texture = null
export(Preset) var preset := Preset.INFO setget set_preset
export(bool) var show_icon := true setget set_show_icon
export(bool) var show_in_world_text := true setget set_show_in_world_text
export(String) var world_text := "" setget set_world_text
export(bool) var close_on_exit := true
export(float) var auto_read_timer := 0.0

const OVERLAY_SCENE = preload("res://core_v2/ui/overlay/InfoOverlay.tscn")
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
onready var world_label = $Viewport/Title
onready var world_body = $Viewport/Body
onready var world_footer = $Viewport/Footer
onready var header_bar = $Viewport/HeaderBar
onready var panel_mesh = $MeshInstance
onready var bezel_mesh = $Bezel
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

func set_panel_title(v):
	panel_title = v
	if is_inside_tree():
		_update_world_visuals()
		_update_marker()

func set_panel_body(v):
	panel_body = v
	if is_inside_tree():
		_update_world_visuals()

func set_world_text(v):
	world_text = v
	if is_inside_tree():
		_update_world_visuals()

func set_show_icon(v):
	show_icon = v
	if is_inside_tree():
		_update_marker()

func set_show_in_world_text(v):
	show_in_world_text = v
	if is_inside_tree():
		_update_world_visuals()

func _update_marker():
	if not interaction_entity: return
	
	if not show_icon:
		interaction_entity.set_marker_config(null)
		return
		
	var config = MarkerConfig.new()
	config.label = panel_title
	config.hint = "Leer"
	config.accent_color = PRESET_COLORS[preset]
	config.interaction_range = 2.5
	interaction_entity.set_marker_config(config)

func _update_world_visuals():
	var color = PRESET_COLORS[preset]

	# Header bar takes the accent; title sits on it in a dark ink so it reads
	# against the bright band.
	if header_bar:
		header_bar.color = color

	if world_label:
		world_label.visible = show_in_world_text
		var t = world_text if world_text != "" else panel_title
		if t.length() > 24:
			t = t.substr(0, 21) + "..."
		world_label.text = t
		# Dark ink on the bright header bar.
		world_label.add_color_override("font_color", Color(0.03, 0.05, 0.06))

	# Body preview: first line or so of the panel body, tinted toward the accent.
	if world_body:
		world_body.add_color_override("font_color", color.linear_interpolate(Color.white, 0.45))
		world_body.text = _body_preview()

	if world_footer:
		world_footer.add_color_override("font_color", color)

	# Subtle accent tint on the steel bezel so presets read at a glance.
	if bezel_mesh:
		var bmat = bezel_mesh.get_surface_material(0)
		if bmat == null and bezel_mesh.mesh:
			bmat = bezel_mesh.mesh.surface_get_material(0)
		if bmat is SpatialMaterial:
			bmat = bmat.duplicate()
			bmat.albedo_color = Color(0.16, 0.17, 0.19).linear_interpolate(color, 0.18)
			bezel_mesh.set_surface_material(0, bmat)

	if omni_light:
		omni_light.light_color = color

	if viewport:
		viewport.render_target_update_mode = Viewport.UPDATE_ONCE
		# Wait a frame for viewport to render if needed
		call_deferred("_apply_viewport_texture")

# A short, single-paragraph teaser of the body for the in-world screen. The
# full text lives in the overlay; here we just hint there's more to read.
func _body_preview() -> String:
	var t = panel_body.strip_edges()
	if t == "":
		return ""
	t = t.replace("\n", " ")
	if t.length() > 90:
		t = t.substr(0, 87) + "..."
	return t

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
		interact()
		get_tree().set_input_as_handled()

# Public entry point: opens the overlay if closed, closes it if open. Lets the
# player input path, scripted triggers, and the PropZoo lever all drive the same
# behaviour.
func interact():
	if _overlay_instance:
		_overlay_instance.close()
	else:
		_open_overlay()

func _open_overlay():
	if _overlay_instance: return
	
	_overlay_instance = OVERLAY_SCENE.instance()
	get_tree().root.add_child(_overlay_instance)
	_overlay_instance.setup(panel_title, panel_body, map_texture, PRESET_COLORS[preset])
	_overlay_instance.connect("closed", self, "_on_overlay_closed")
	_overlay_instance.open()
	
	if has_node("/root/EventBus"):
		var emit_name = screen_id if screen_id != "" else panel_title
		get_node("/root/EventBus").emit_signal("info_screen_read", emit_name)

func _on_overlay_closed():
	_overlay_instance = null
	_auto_read_elapsed = 0.0
