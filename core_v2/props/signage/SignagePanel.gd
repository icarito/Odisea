tool
extends Spatial

# core_v2/props/signage/SignagePanel.gd - Lightweight visual signage component

const COLOR_PRESETS = {
	"warning": Color("#FF8800"),
	"danger": Color("#FF2200"),
	"info": Color("#2288FF"),
	"terminal": Color("#00FF88"),
	"hologram": Color("#00CCFF")
}

export(String) var text: String = "SIGNAGE" setget set_text
export(String, "warning", "danger", "info", "terminal", "hologram", "custom") var color_preset: String = "terminal" setget set_color_preset
export(Color) var custom_color: Color = Color.white setget set_custom_color
export(float) var emission_energy: float = 1.0 setget set_emission_energy

export(bool) var hologram_mode: bool = false setget set_hologram_mode
export(bool) var face_player: bool = false
export(bool) var is_interactive: bool = false setget set_is_interactive
export(String) var interactive_hint: String = "Leer letrero"
export(String) var interactive_text: String = "" # If empty, use 'text'

export(Vector2) var viewport_size: Vector2 = Vector2(128, 64) setget set_viewport_size

signal signage_read(id)

var _base_scale: Vector3 = Vector3.ONE
var _time: float = 0.0
var _material: SpatialMaterial = null
var _is_ready: bool = false

# Compatibility with PlayerControllerV2
var is_interactable: bool setget , get_is_interactable

func get_is_interactable() -> bool:
	return is_interactive

func set_text(v: String) -> void:
	text = v
	if _is_ready:
		update_text()

func set_color_preset(v: String) -> void:
	color_preset = v
	if _is_ready:
		update_text()
		_update_material()

func set_custom_color(v: Color) -> void:
	custom_color = v
	if color_preset == "custom" and _is_ready:
		update_text()
		_update_material()

func set_emission_energy(v: float) -> void:
	emission_energy = v
	if _is_ready:
		_update_material()

func set_hologram_mode(v: bool) -> void:
	hologram_mode = v
	if _is_ready:
		_update_material()
		_update_process_mode()
		update_text() # Background transparency changes

func set_is_interactive(v: bool) -> void:
	is_interactive = v
	if _is_ready:
		_update_interaction_area()

func set_viewport_size(v: Vector2) -> void:
	viewport_size = v
	if _is_ready:
		update_text()

func _ready() -> void:
	_base_scale = scale
	_is_ready = true

	var mesh_instance: MeshInstance = get_node_or_null("MeshInstance")
	if mesh_instance:
		if mesh_instance.material_override:
			_material = mesh_instance.material_override.duplicate()
		else:
			_material = SpatialMaterial.new()
		mesh_instance.material_override = _material

	_update_material()
	_update_interaction_area()
	update_text()
	_update_process_mode()

func update_text() -> void:
	if not _is_ready: return

	var vp = Viewport.new()
	vp.size = viewport_size
	vp.transparent_bg = true
	vp.render_target_v_flip = true
	vp.render_target_update_mode = Viewport.UPDATE_ONCE

	var color = custom_color
	if COLOR_PRESETS.has(color_preset):
		color = COLOR_PRESETS[color_preset]

	var cr = ColorRect.new()
	cr.rect_size = viewport_size
	cr.color = Color(0, 0, 0, 1)
	if hologram_mode:
		cr.color.a = 0.2
		# Add a border for "borde más brillante" if no text
		if text == "":
			var border = ReferenceRect.new()
			border.rect_size = viewport_size
			border.editor_only = false
			border.border_color = color
			border.border_width = 2.0
			cr.add_child(border)

	vp.add_child(cr)

	if text != "":
		var lbl = Label.new()
		lbl.rect_size = viewport_size
		lbl.text = text
		lbl.align = Label.ALIGN_CENTER
		lbl.valign = Label.VALIGN_CENTER
		lbl.add_color_override("font_color", color)

		# Try to find a nice font
		var font_path = "res://assets/fonts/terminal.ttf"
		var alt_font_path = "res://assets/fonts/Ac437_OlivettiThin_8x16.ttf"
		var font = null

		if File.new().file_exists(font_path):
			font = DynamicFont.new()
			font.font_data = load(font_path)
		elif File.new().file_exists(alt_font_path):
			font = DynamicFont.new()
			font.font_data = load(alt_font_path)

		if font:
			font.size = int(viewport_size.y * 0.6)
			lbl.add_font_override("font", font)
		vp.add_child(lbl)

	add_child(vp)

	# Wait for rendering
	if Engine.editor_hint:
		vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
		# In tool mode, we can't yield(idle_frame) reliably for immediate results in _ready
		# but since it's UPDATE_ONCE/ALWAYS it might work.
		# We'll use a small trick to ensure it captures.
		visual_update(vp)
	else:
		yield(get_tree(), "idle_frame")
		visual_update(vp)

func visual_update(vp: Viewport) -> void:
	if not is_instance_valid(vp): return
	var tex_data = vp.get_texture().get_data()
	var tex = ImageTexture.new()
	tex.create_from_image(tex_data)

	if _material:
		_material.albedo_texture = tex
		_material.emission_texture = tex

	vp.queue_free()

func _update_material() -> void:
	if not _material: return

	var color = custom_color
	if COLOR_PRESETS.has(color_preset):
		color = COLOR_PRESETS[color_preset]

	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy = emission_energy

	if hologram_mode:
		_material.flags_transparent = true
		_material.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
		_material.albedo_color = Color(1, 1, 1, 0.5)
	else:
		_material.flags_transparent = false
		_material.params_blend_mode = SpatialMaterial.BLEND_MODE_MIX
		_material.params_cull_mode = SpatialMaterial.CULL_BACK
		_material.albedo_color = Color.white

func _update_interaction_area() -> void:
	var area = get_node_or_null("Area")
	if not area: return

	area.monitoring = is_interactive
	area.monitorable = is_interactive

	if is_interactive:
		if not is_in_group("interactable"):
			add_to_group("interactable")
		if not area.is_connected("body_entered", self, "_on_body_entered"):
			area.connect("body_entered", self, "_on_body_entered")
		if not area.is_connected("body_exited", self, "_on_body_exited"):
			area.connect("body_exited", self, "_on_body_exited")
	else:
		if is_in_group("interactable"):
			remove_from_group("interactable")
		if area.is_connected("body_entered", self, "_on_body_entered"):
			area.disconnect("body_entered", self, "_on_body_entered")
		if area.is_connected("body_exited", self, "_on_body_exited"):
			area.disconnect("body_exited", self, "_on_body_exited")

func _update_process_mode() -> void:
	set_process(hologram_mode or face_player)
	if not hologram_mode:
		scale = _base_scale

func _process(delta: float) -> void:
	if hologram_mode:
		_time += delta
		var s = 1.0 + sin(_time * 8.0) * 0.01
		scale = _base_scale * s

	if face_player:
		_do_face_player(delta)

func _do_face_player(delta: float) -> void:
	var cam = get_viewport().get_camera()
	if not cam: return

	var target_pos = cam.global_transform.origin
	target_pos.y = global_transform.origin.y # Only rotate on Y axis

	if global_transform.origin.distance_squared_to(target_pos) < 0.001:
		return

	var look_at_transform = global_transform.looking_at(target_pos, Vector3.UP)
	# rotate 180 because QuadMesh faces -Z
	look_at_transform = look_at_transform.rotated(Vector3.UP, PI)

	global_transform.basis = global_transform.basis.slerp(look_at_transform.basis, delta * 5.0)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		var hint_manager = get_node_or_null("/root/PlayerHintManager")
		if hint_manager:
			hint_manager.show_interaction_hint(interactive_hint)

func interact() -> void:
	if is_interactive:
		signage_read()

func signage_read() -> void:
	emit_signal("signage_read", name)

	var display_text = interactive_text if interactive_text != "" else text
	var hint_manager = get_node_or_null("/root/PlayerHintManager")
	if hint_manager:
		hint_manager.show_status_hint(display_text, 3.0)

	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus and event_bus.has_method("emit_signal"):
		event_bus.emit_signal("signage_read", self)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		var hint_manager = get_node_or_null("/root/PlayerHintManager")
		if hint_manager:
			hint_manager.clear_interaction_hint()
