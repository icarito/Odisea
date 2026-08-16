tool
extends Spatial

# core_v2/props/signage/SignagePanel.gd - Lightweight visual signage component

# Color preset palette mapping:
# warning:  Amber/orange (#FF8800) - Cautionary alerts and hazards
# danger:   Red (#FF2200)          - Critical errors and danger zones
# info:     Cyan (#00FFFF)         - General information and status screens
# terminal: Green (#00FF88)        - System consoles and command prompts
# hologram: Light cyan (#00CCFF)   - Projection displays and spatial interfaces
const COLOR_PRESETS = {
	"warning": Color("#FF8800"),
	"danger": Color("#FF2200"),
	"info": Color("#00FFFF"),
	"terminal": Color("#00FF88"),
	"hologram": Color("#00CCFF")
}

export(String) var text: String = "SIGNAGE" setget set_text
export(String, "warning", "danger", "info", "terminal", "hologram", "custom") var color_preset: String = "terminal" setget set_color_preset
export(Color) var custom_color: Color = Color.white setget set_custom_color
# Color del texto. Con alpha < 0 usa el color del preset, que es el comportamiento previo.
# Separarlo es lo que permite tener contraste: el mismo color pintaba la letra Y la
# emisión del panel, así que el texto siempre quedaba del mismo tono que su fondo.
export(Color) var text_color: Color = Color(0, 0, 0, -1) setget set_text_color
export(float) var emission_energy: float = 1.0 setget set_emission_energy

export(DynamicFont) var font: DynamicFont = null setget set_font
export(int, 0, 256) var font_size: int = 0 setget set_font_size
export(int, "Left", "Center", "Right") var alignment: int = Label.ALIGN_CENTER setget set_alignment
export(int, "None", "Upper", "Lower") var case_mode: int = 0 setget set_case_mode
export(float) var padding: float = 8.0 setget set_padding
export(Color) var outline_color: Color = Color(0, 0, 0, 0.6) setget set_outline_color
export(int, 0, 16) var outline_size: int = 0 setget set_outline_size

export(bool) var border_enabled: bool = false setget set_border_enabled
export(Color) var border_color: Color = Color.white setget set_border_color
export(float) var border_width: float = 2.0 setget set_border_width

export(float) var interaction_radius: float = 2.0 setget set_interaction_radius

# Opacidad del fondo del letrero. Un letrero puede ser translúcido sin ser un holograma:
# el modo holograma es aditivo y se lo come la luz de la sala. 1.0 = placa opaca.
export(float, 0.0, 1.0) var panel_alpha: float = 1.0 setget set_panel_alpha
# Espacio reservado a la izquierda para el icono del letrero (FD-260). Con 0 no se
# reserva nada y el texto ocupa todo el ancho útil.
export(float) var icon_slot_width: float = 0.0 setget set_icon_slot_width
export(bool) var hologram_mode: bool = false setget set_hologram_mode
export(bool) var face_player: bool = false
export(bool) var is_interactive: bool = false setget set_is_interactive
export(String) var interactive_hint: String = "Leer letrero"
export(String) var interactive_text: String = "" # If empty, use 'text'

# Viewport size default matches QuadMesh 5:3 aspect ratio (1.2 x 0.72).
# Note: Overriding viewport_size implies accepting texture stretching if aspect ratio differs.
export(Vector2) var viewport_size: Vector2 = Vector2(512, 307) setget set_viewport_size

signal signage_read(id)

var _base_scale: Vector3 = Vector3.ONE
var _time: float = 0.0
var _material: SpatialMaterial = null
var _is_ready: bool = false
var _viewport: Viewport = null

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

func set_text_color(v: Color) -> void:
	text_color = v
	if _is_ready:
		update_text()


func set_custom_color(v: Color) -> void:
	custom_color = v
	if color_preset == "custom" and _is_ready:
		update_text()
		_update_material()

func set_emission_energy(v: float) -> void:
	emission_energy = v
	if _is_ready:
		_update_material()

func set_font(v: DynamicFont) -> void:
	font = v
	if _is_ready:
		update_text()

func set_font_size(v: int) -> void:
	font_size = v
	if _is_ready:
		update_text()

func set_alignment(v: int) -> void:
	alignment = v
	if _is_ready:
		update_text()

func set_case_mode(v: int) -> void:
	case_mode = v
	if _is_ready:
		update_text()

func set_padding(v: float) -> void:
	padding = v
	if _is_ready:
		update_text()

func set_outline_color(v: Color) -> void:
	outline_color = v
	if _is_ready:
		update_text()

func set_outline_size(v: int) -> void:
	outline_size = v
	if _is_ready:
		update_text()

func set_border_enabled(v: bool) -> void:
	border_enabled = v
	if _is_ready:
		update_text()

func set_border_color(v: Color) -> void:
	border_color = v
	if _is_ready:
		update_text()

func set_border_width(v: float) -> void:
	border_width = v
	if _is_ready:
		update_text()

func set_interaction_radius(v: float) -> void:
	interaction_radius = v
	if _is_ready:
		_update_interaction_area()

func set_panel_alpha(v: float) -> void:
	panel_alpha = clamp(v, 0.0, 1.0)
	if _is_ready:
		update_text()
		_update_material()


func set_icon_slot_width(v: float) -> void:
	icon_slot_width = max(v, 0.0)
	if _is_ready:
		update_text()


func set_hologram_mode(v: bool) -> void:
	hologram_mode = v
	if _is_ready:
		_update_material()
		_update_process_mode()
		update_text()

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

func _measure_string_size(p_font: Font, p_string: String) -> Vector2:
	var lines = p_string.split("\n")
	var max_w: float = 0.0
	for line in lines:
		var line_sz = p_font.get_string_size(line)
		if line_sz.x > max_w:
			max_w = line_sz.x
	var total_h: float = lines.size() * p_font.get_height()
	return Vector2(max_w, total_h)

func update_text() -> void:
	if not _is_ready: return

	if _viewport == null or not is_instance_valid(_viewport):
		_viewport = Viewport.new()
		_viewport.name = "_Viewport"
		_viewport.transparent_bg = true
		_viewport.render_target_v_flip = true
		add_child(_viewport)

	_viewport.size = viewport_size
	_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS if Engine.editor_hint else Viewport.UPDATE_ONCE
	# UPDATE_ONCE dibuja UN frame, y las glifos de una DynamicFont se rasterizan recién
	# después: ese único frame salía con el fondo y sin texto, y ya no volvía a dibujarse.
	# Re-armar el disparo en el frame siguiente alcanza para que el texto entre.
	if not Engine.editor_hint:
		_viewport.call_deferred("set_render_target_update_mode", Viewport.UPDATE_ONCE)

	for child in _viewport.get_children():
		_viewport.remove_child(child)
		child.queue_free()

	var color = custom_color
	if COLOR_PRESETS.has(color_preset):
		color = COLOR_PRESETS[color_preset]

	var cr = ColorRect.new()
	cr.rect_size = viewport_size
	cr.color = Color(0, 0, 0, panel_alpha)
	if hologram_mode:
		cr.color.a = 0.2

	_viewport.add_child(cr)

	if border_enabled or (hologram_mode and text == ""):
		var border = ReferenceRect.new()
		border.rect_size = viewport_size
		border.editor_only = false
		border.border_color = border_color if border_enabled else color
		border.border_width = border_width
		cr.add_child(border)

	var formatted_text = text
	if case_mode == 1:
		formatted_text = text.to_upper()
	elif case_mode == 2:
		formatted_text = text.to_lower()

	if formatted_text != "":
		var font_to_use: DynamicFont = null
		if font != null and font.font_data != null:
			font_to_use = font.duplicate() as DynamicFont
		else:
			var default_font_path = "res://assets/fonts/SyneMono-Regular.ttf"
			if File.new().file_exists(default_font_path):
				font_to_use = DynamicFont.new()
				font_to_use.font_data = load(default_font_path)

		if font_to_use:
			if outline_size > 0:
				font_to_use.outline_size = outline_size
				font_to_use.outline_color = outline_color

			var avail_w = max(1.0, viewport_size.x - 2.0 * padding)
			var avail_h = max(1.0, viewport_size.y - 2.0 * padding)

			if font_size > 0:
				font_to_use.size = font_size
			else:
				var low: int = 1
				var high: int = int(avail_h)
				var best_size: int = 1
				while low <= high:
					var mid: int = (low + high) / 2
					font_to_use.size = mid
					var measured = _measure_string_size(font_to_use, formatted_text)
					if measured.x <= avail_w and measured.y <= avail_h:
						best_size = mid
						low = mid + 1
					else:
						high = mid - 1
				font_to_use.size = best_size

			var lbl = Label.new()
			lbl.rect_position = Vector2(padding + icon_slot_width, padding)
			lbl.rect_size = Vector2(max(avail_w - icon_slot_width, 1.0), avail_h)
			lbl.text = formatted_text
			lbl.align = alignment
			lbl.valign = Label.VALIGN_CENTER
			lbl.autowrap = true
			lbl.add_color_override("font_color", text_color if text_color.a >= 0.0 else color)
			lbl.add_font_override("font", font_to_use)
			_viewport.add_child(lbl)

	if _material:
		var vp_tex = _viewport.get_texture()
		_material.albedo_texture = vp_tex
		_material.emission_texture = vp_tex

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
		_material.flags_transparent = panel_alpha < 1.0
		_material.params_blend_mode = SpatialMaterial.BLEND_MODE_MIX
		_material.params_cull_mode = SpatialMaterial.CULL_BACK
		_material.albedo_color = Color.white

func _update_interaction_area() -> void:
	var area = get_node_or_null("Area")
	if not area: return

	area.monitoring = is_interactive
	area.monitorable = is_interactive

	var col_shape: CollisionShape = area.get_node_or_null("CollisionShape")
	if col_shape:
		if not (col_shape.shape is SphereShape):
			var sphere = SphereShape.new()
			sphere.radius = interaction_radius
			col_shape.shape = sphere
		else:
			var sphere = col_shape.shape.duplicate() as SphereShape
			sphere.radius = interaction_radius
			col_shape.shape = sphere

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
	var vp = get_viewport()
	if not vp: return
	var cam = vp.get_camera()
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
