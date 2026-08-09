extends Control
class_name RadialSelectorV2

# RadialSelectorV2.gd
# Aim-driven radial picker built on addons/radial_menu (see that folder's
# ODISEA_NOTES.md).
#
# The dial is pointed at, not scrolled through. The owner projects wherever the
# camera is aiming onto the dial's plane and hands the hit over as a viewport
# coordinate; nothing here touches the OS pointer, so opening the dial costs no
# cursor, no capture toggle and no camera cut. Aiming outside the dial selects
# nothing at all, which is what lets a click be ignored unless the gesture
# unmistakably points at an option.
#
# What comes from the addon is the ring itself — its RadialMenu.tscn and the
# selector shader that draws the highlight arc. Option layout and hit-testing are
# ours:
#
#   - The addon's index math (round(angle / step - 1), clamped) only agrees with
#     its own place_buttons() for some option counts; with 3 options every pick is
#     off by one. It also has no notion of "nothing selected".
#   - Its layout runs the full circle from a fixed angle. Ours covers the right
#     half, from 6 o'clock through 3 to 12, so a floor list reads as a climb on
#     the side the over-the-shoulder camera leaves open.
#   - It has no notion of state, only of choice. This dial also carries a needle
#     pointing at where the car actually is, between stops included.
#   - Its shader setters no-op while the container has no children
#     (set_shader_param bails on an empty child list), so the ring is configured
#     straight on its material here.

signal option_hovered(index)
signal option_selected(index)
signal cancelled()

const RadialMenuScript = preload("res://addons/radial_menu/RadialMenu.gd")

const NONE := -1
# Screen-space angles (Y down). First option at 6 o'clock, last at 12, half a
# turn apart through 3 — so the arc climbs the right-hand side, which is the half
# the over-the-shoulder camera keeps clear. Options run anticlockwise on screen,
# hence every step is subtracted rather than added.
const FIRST_OPTION_ANGLE := PI / 2.0
const ARC_SPAN := PI

export(Vector2) var option_size := Vector2(230.0, 104.0)
export(Resource) var option_font = null
# Where the options sit, as a fraction of half the shorter viewport side.
export(float, 0, 1) var option_radius := 0.65
# Aiming this close to the exact middle carries no usable direction, so the
# current focus simply holds. Small enough that it is not a dead spot you can
# feel — it only exists to stop the angle jittering at the singularity.
export(float) var hub_epsilon := 6.0

# Ring geometry, in the addon shader's units. Its circle() test compares squared
# distance, so the drawn radius is sqrt(width) / 2 of the ring box.
export(float, 0, 1) var width_max := 0.66
export(float, 0, 1) var width_min := 0.24
export(float, 0, 3.1416) var arc_size := 0.42
# The addon's shader draws its track around the whole circle and has no span
# uniform, so on a half dial the unused side would render as a bare stretch of
# track. Leaving it fully transparent sidesteps that: the only ring elements are
# the wedge under the option being aimed at and the level needle, which also
# makes "nothing selected" unmistakable.
export(Color) var color_bg := Color(0.02, 0.15, 0.2, 0.0)
export(Color) var color_fg := Color(0.0, 0.83, 1.0, 0.75)
export(Color) var option_color := Color(0.42, 0.68, 0.76, 1.0)
export(Color) var option_color_hover := Color(1.0, 1.0, 1.0, 1.0)
# The needle reads as state, not as choice, so it stays off the selection cyan.
export(Color) var indicator_color := Color(0.607843, 0.992157, 0.580392, 0.9)
export(float) var readout_slide_time := 0.45
# How far the numbers travel when the level changes, as a multiple of the label
# height. Around one full height reads as a strip scrolling past a window.
export(float) var readout_slide_travel := 1.15
# Where the level readout stands, as a fraction of the dial. Off to the side the
# arc leaves free, not in the middle where the needle pivots.
export(Vector2) var readout_center := Vector2(0.26, 0.5)
export(float) var readout_scale := 1.35

var _radial: Container = null
var _host: Control = null
var _option_layer: Control = null
var _readout_label: Label = null
var _readout_ghost: Label = null
var _title_label: Label = null
var _status_label: Label = null
var _buttons := []
var _option_count := 0
var _hover_index := NONE
var _is_open := false
var _focus_suppressed := false
var _indicator: Polygon2D = null
var _indicator_layer: Control = null
var _readout_layer: Control = null
var _readout_tween: Tween = null
var _level := 0.0


func _ready() -> void:
	_host = get_node_or_null("RadialHost")
	_title_label = get_node_or_null("Title")
	_status_label = get_node_or_null("Status")
	_option_layer = get_node_or_null("Options")
	_indicator_layer = get_node_or_null("Indicator")
	_readout_layer = get_node_or_null("Readout")
	_readout_tween = Tween.new()
	_readout_tween.name = "ReadoutTween"
	add_child(_readout_tween)
	_build_radial()
	_build_indicator()
	_build_readout_label()
	visible = false
	connect("resized", self, "_on_resized")


# --- Public API ---

func set_options(labels: Array) -> void:
	"""Replace the dial contents. Labels are drawn as-is, in order."""
	if _option_layer == null:
		return
	_clear_options()
	for label in labels:
		var option := Label.new()
		option.text = String(label)
		option.align = Label.ALIGN_CENTER
		option.valign = Label.VALIGN_CENTER
		option.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option.rect_size = option_size
		option.rect_pivot_offset = option_size / 2.0
		if option_font is Font:
			option.add_font_override("font", option_font)
		_option_layer.add_child(option)
		_buttons.append(option)
	_option_count = _buttons.size()
	_place_options()
	_apply_hover(NONE, true)


func set_title(text: String) -> void:
	if _title_label:
		_title_label.text = text


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func set_readout_text(text: String) -> void:
	"""Level readout, set outright. Always the car's own floor, never the aim: the
	wedge and the lit number already say what is being pointed at."""
	if _readout_label == null:
		return
	_readout_tween.stop_all()
	_readout_label.text = text
	_readout_label.modulate = Color(1, 1, 1, 1)
	_readout_label.rect_position = _readout_rest_position()
	if _readout_ghost:
		_readout_ghost.modulate = Color(1, 1, 1, 0)


func announce_readout_text(text: String, direction: int) -> void:
	"""Level readout, changed the way the numbers would move if they were painted
	on a strip running through the car: climbing a floor scrolls the strip
	downward, so the old number leaves through the bottom while the new one drops
	in from above. Both move at once — one number vanishing and another appearing
	somewhere else does not read as travel."""
	if _readout_label == null or _readout_ghost == null:
		return
	if direction == 0 or readout_slide_time <= 0.0:
		set_readout_text(text)
		return

	var rest := _readout_rest_position()
	# Screen Y grows downward, and the strip travels against the car: up is +Y.
	var away := Vector2(0, _readout_label.rect_size.y * readout_slide_travel) \
		* (1.0 if direction > 0 else -1.0)

	# The label that was showing becomes the one leaving, and the spare takes over.
	var outgoing := _readout_label
	var incoming := _readout_ghost
	_readout_label = incoming
	_readout_ghost = outgoing

	incoming.text = text
	incoming.rect_position = rest - away
	incoming.modulate = Color(1, 1, 1, 0)

	_readout_tween.stop_all()
	_readout_tween.interpolate_property(
		outgoing, "rect_position", rest, rest + away,
		readout_slide_time, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	_readout_tween.interpolate_property(
		outgoing, "modulate", Color(1, 1, 1, 1), Color(1, 1, 1, 0),
		readout_slide_time * 0.8, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	_readout_tween.interpolate_property(
		incoming, "rect_position", rest - away, rest,
		readout_slide_time, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_readout_tween.interpolate_property(
		incoming, "modulate", Color(1, 1, 1, 0), Color(1, 1, 1, 1),
		readout_slide_time * 0.8, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	_readout_tween.start()


func set_level(level: float) -> void:
	"""Where the car is, in stop units — fractions included, so the needle keeps
	moving between stops instead of jumping on arrival."""
	_level = level
	_update_indicator()


func open() -> void:
	_is_open = true
	visible = true
	# Nothing is picked until the player actually aims at an option.
	_focus_suppressed = false
	_apply_hover(NONE, true)


func close() -> void:
	_is_open = false
	visible = false
	_focus_suppressed = false
	_apply_hover(NONE, true)


func suppress_focus() -> void:
	"""Drop the focus and keep it dropped. Used after a pick is committed: the
	aim is still sitting on the stop that was just chosen, so without this the
	dial would light it straight back up and invite picking it again."""
	_focus_suppressed = true
	_apply_hover(NONE, false)


func resume_focus() -> void:
	_focus_suppressed = false


func is_open() -> bool:
	return _is_open


func has_selection() -> bool:
	return _hover_index != NONE


func get_hovered_index() -> int:
	return _hover_index


func option_at(viewport_position: Vector2) -> int:
	"""Return the actual label under a direct pointer, without radial-sector
	expansion. Used by touch confirmation so taps outside visible buttons do not
	commit a choice."""
	for i in range(_buttons.size()):
		if _buttons[i].get_global_rect().has_point(viewport_position):
			return i
	return NONE


func point_at(viewport_position: Vector2) -> void:
	"""Aim, in this dial's own viewport pixels. Off the dial clears the selection."""
	if not _is_open or _option_count <= 0 or _focus_suppressed:
		return
	_apply_hover(_index_at(viewport_position), false)


func clear_pointer() -> void:
	"""The aim left the dial's plane entirely (looking away, or behind it)."""
	if not _is_open:
		return
	# Looking away is also how a rider releases the hold left by a committed pick.
	_focus_suppressed = false
	_apply_hover(NONE, false)


func confirm() -> void:
	# No selection means the gesture was never unambiguous: swallow the press
	# rather than picking whatever happens to be nearest.
	if not _is_open or _hover_index == NONE:
		return
	emit_signal("option_selected", _hover_index)


func cancel() -> void:
	if not _is_open:
		return
	emit_signal("cancelled")


# --- Hit testing ---

func _ring_size() -> float:
	return min(rect_size.x, rect_size.y)


func _index_at(position: Vector2) -> int:
	# Direction is the whole story: once the aim is on the projection at all, some
	# option is focused. There is no ring to hit and no dead sector — the owner
	# decides whether the player is looking at the dial, and everything from there
	# in is a heading. Anything else meant sweeping past a stop and getting
	# nothing, which reads as the dial being broken rather than strict.
	var offset := position - rect_size / 2.0
	if offset.length() < hub_epsilon:
		return _hover_index # No usable heading at the singularity; hold.

	var travelled: float = wrapf(FIRST_OPTION_ANGLE - atan2(offset.y, offset.x), 0.0, TAU)
	if travelled > (ARC_SPAN + TAU) / 2.0:
		# Inside the unused half but past its midpoint: nearer the first option
		# than the last, so it wraps rather than sticking to the top of the list.
		return 0
	return int(clamp(round(travelled / _step()), 0, _option_count - 1))


func _step() -> float:
	if _option_count <= 1:
		return ARC_SPAN
	return ARC_SPAN / float(_option_count - 1)


func _index_to_screen_angle(index: int) -> float:
	return FIRST_OPTION_ANGLE - index * _step()


# --- Ring ---

func _build_radial() -> void:
	if _host == null or (_radial != null and is_instance_valid(_radial)):
		return
	_radial = RadialMenuScript.new()
	_radial.name = "Radial"
	_radial.width_max = width_max
	_radial.width_min = width_min
	_host.add_child(_radial)
	_radial.set_anchors_and_margins_preset(Control.PRESET_WIDE)

	# Cut the addon off from the OS pointer. Without this, every mouse motion
	# rewrites its cursor from get_global_mouse_position(), which is frozen while
	# the mouse is captured.
	var cursor_pos: Node = _radial.get_node_or_null("RadialMenu/CursorPos")
	if cursor_pos:
		cursor_pos.set_process_input(false)
	_radial.set_process_input(false)

	_apply_ring_material()


# The readout lives in our own layer rather than the addon's CenterNode, which is
# a CenterContainer and would fight the slide animation by re-centring the label
# on every sort.
func _build_readout_label() -> void:
	# Two of them: the level change crosses one out while the other comes in, so
	# there has to be a spare standing by at all times.
	if _readout_layer == null or _readout_label != null:
		return
	_readout_label = _new_readout_label("ReadoutLabel")
	_readout_ghost = _new_readout_label("ReadoutGhost")
	_readout_ghost.modulate = Color(1, 1, 1, 0)


func _new_readout_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_color_override("font_color", option_color_hover)
	if option_font is Font:
		label.add_font_override("font", option_font)
	_readout_layer.add_child(label)
	return label


func _build_indicator() -> void:
	if _indicator_layer == null or _indicator != null:
		return
	_indicator = Polygon2D.new()
	_indicator.name = "LevelNeedle"
	_indicator.color = indicator_color
	_indicator_layer.add_child(_indicator)


func _angle_for_level(level: float) -> float:
	"""Same mapping as the options, but continuous, so a car between two stops
	puts the needle between their two labels."""
	if _option_count <= 1:
		return FIRST_OPTION_ANGLE
	return FIRST_OPTION_ANGLE - clamp(level, 0.0, float(_option_count - 1)) * _step()


func _update_indicator() -> void:
	if _indicator == null:
		return
	_indicator.visible = _option_count > 1
	_indicator.position = rect_size / 2.0
	_indicator.rotation = _angle_for_level(_level)


func _readout_rest_position() -> Vector2:
	# Parked in the half the dial does not use. A 180 degree arc leaves that side
	# empty, and a big standing level number is exactly what belongs there.
	if _readout_label == null:
		return Vector2.ZERO
	return Vector2(rect_size.x * readout_center.x, rect_size.y * readout_center.y) \
		- _readout_label.rect_size / 2.0


func _apply_ring_material() -> void:
	# selector.tres ships as a shared ExtResource with a red debug bevel; duplicate
	# it so two dials in one scene cannot fight over the same params.
	var background = _radial.get_node_or_null("RadialMenu/Background")
	if background == null or not (background.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = background.material.duplicate()
	background.material = mat
	mat.set_shader_param("width_max", width_max)
	mat.set_shader_param("width_min", width_min)
	mat.set_shader_param("cursor_size", arc_size)
	mat.set_shader_param("color_bg", color_bg)
	mat.set_shader_param("color_fg", color_fg)
	mat.set_shader_param("bevel_enabled", false)


func _set_arc(index: int) -> void:
	var background = _radial.get_node_or_null("RadialMenu/Background") if _radial else null
	if background == null or not (background.material is ShaderMaterial):
		return
	if index == NONE:
		# The shader always paints an arc somewhere, so a zero width is the only
		# way to say "nothing is selected".
		background.material.set_shader_param("cursor_size", 0.0)
		return
	# The shader reads cursor_size as a half-width, so capping it at half a step
	# keeps the wedge inside its own sector. Without the cap a fixed width bleeds
	# over the neighbouring stops as soon as the option count grows or the arc
	# shortens, and the wedge stops saying which stop it belongs to.
	background.material.set_shader_param("cursor_size", min(arc_size, _step() * 0.5))
	# The shader compares against atan(), which returns -PI..PI. Handing it an
	# angle from outside that range leaves the arc lopsided and drifting off its
	# option by up to half a sector, so normalise before sending.
	var angle: float = _index_to_screen_angle(index)
	background.material.set_shader_param("cursor_deg", wrapf(angle + PI, 0.0, TAU) - PI)


# --- Option layout ---

func _clear_options() -> void:
	for option in _buttons:
		if is_instance_valid(option):
			_option_layer.remove_child(option)
			option.free()
	_buttons.clear()
	_option_count = 0
	_hover_index = NONE


func _on_resized() -> void:
	_place_options()


func _place_options() -> void:
	_shape_indicator()
	for label in [_readout_label, _readout_ghost]:
		if label == null:
			continue
		label.rect_size = Vector2(_ring_size() * 0.36, _ring_size() * 0.26)
		label.rect_pivot_offset = label.rect_size / 2.0
		label.rect_scale = Vector2(readout_scale, readout_scale)
		label.rect_position = _readout_rest_position()
	if _option_count <= 0 or _option_layer == null:
		return
	var center := rect_size / 2.0
	var radius: float = _ring_size() / 2.0 * option_radius
	for i in range(_option_count):
		var angle := _index_to_screen_angle(i)
		_buttons[i].rect_size = option_size
		_buttons[i].rect_position = center + Vector2(cos(angle), sin(angle)) * radius - option_size / 2.0


func _shape_indicator() -> void:
	"""A needle spanning the ring band, drawn pointing along +X so that setting
	its rotation to a screen angle aims it straight at that spot on the dial."""
	if _indicator == null:
		return
	var ring := _ring_size()
	# The addon shader compares squared distance, hence the sqrt on the widths.
	var inner: float = sqrt(width_min) / 2.0 * ring
	var outer: float = sqrt(width_max) / 2.0 * ring
	var half_width: float = ring * 0.022
	_indicator.polygon = PoolVector2Array([
		Vector2(outer * 1.04, 0.0),
		Vector2(outer * 0.82, -half_width),
		Vector2(inner * 0.45, 0.0),
		Vector2(outer * 0.82, half_width),
	])
	_update_indicator()


func _apply_hover(index: int, silent: bool) -> void:
	var changed: bool = index != _hover_index
	_hover_index = index
	_set_arc(index)
	for i in range(_buttons.size()):
		var is_hovered: bool = i == index
		_buttons[i].add_color_override("font_color", option_color_hover if is_hovered else option_color)
		_buttons[i].rect_scale = Vector2(1.15, 1.15) if is_hovered else Vector2.ONE
		_buttons[i].rect_pivot_offset = option_size / 2.0
	if changed and not silent:
		emit_signal("option_hovered", index)
