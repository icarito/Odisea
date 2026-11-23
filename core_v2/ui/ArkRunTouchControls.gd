extends Control

# FD-325 T2: controles tactiles de Ark Run (SPIN_REAL), montados en MobileUI por MobileUIManager
# via set_spin_controls_active(). Arranca oculto: solo aparece en escenas que lo piden (ArkRun /
# SpinLab), sin ensuciar Dome_Intro ni RingHub.
#
# Cada boton espeja un input de gamepad: IMPULSO = LT (thruster_boost), CUERDA = RT
# (rope_grapple), AUTONAV = nav_assist. En touch enganchar/soltar la cuerda vive en el MISMO
# boton (toque para enganchar, toque o salto para soltar): nunca hay dos dedos peleando.
#
# Zonas sagradas: los miembros van relativos al FONDO de pantalla y el anillo de Dv rodea el boton
# por su margen: nada invade la franja superior (0..140px) ni la barra central. Sin class_name.
const TouchActionButtonScript = preload("res://core_v2/ui/TouchActionButton.gd")

# T1 define thruster_boost/rope_grapple en el InputMap; si faltan, TouchActionButton no se rompe.
const ACTION_THRUSTER := "thruster_boost"
const ACTION_ROPE := "rope_grapple"
const ACTION_NAV := "nav_assist"

const SAFE_TOP := 140.0 # TopBar + franja superior del HUD: sagrada
const SAFE_MARGIN := 20.0
const BTN_SIZE := 64.0
const NAV_SIZE := Vector2(96.0, 40.0)
const BLOCK_BOTTOM := 100.0 # px desde el fondo hasta el centro del bloque de fila inferior
const RING_TRACK_ALPHA := 0.28
const RING_GAP := 7.0
const CIAN := Color(0.35, 0.85, 1.0) # normal / vuelo libre
const GOLD := Color(1.0, 0.75, 0.25) # anclaje / enganche
const DIM := Color(0.55, 0.6, 0.65, 0.55) # sin anclaje

var _active := false
var _rope_attached := false
var _anchor_in_range := false
var _anchor_range_m := -1.0
var _dv_ratio := 0.0
var _thruster_btn: TouchActionButton = null
var _rope_btn: TouchActionButton = null
var _nav_btn: TouchActionButton = null
var _last_viewport_size := Vector2.ZERO

func _ready() -> void:
	name = "ArkRunTouchControls"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false

# set_spin_controls_active() puede llamarse antes del _ready(): aca se arma y se re-aplica.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		_build()
		set_spin_controls_active(_active)

func set_spin_controls_active(active: bool) -> void:
	_active = active
	visible = active
	# TouchActionButton._input mira SU propio `visible` (no el de los ancestros): un boton oculto
	# por el padre igual se quedaria toques ajenos, asi que cada uno se oculta/muestra explicito.
	for btn in [_thruster_btn, _rope_btn, _nav_btn]:
		if btn != null:
			btn.visible = active
	if active:
		_layout_buttons()
		_sync_labels()

# data: rope_attached, anchor_in_range, anchor_range_m, dv_ratio. Acepta claves parciales.
func update_spin_touch_state(data: Dictionary) -> void:
	if data.has("rope_attached"):
		_rope_attached = bool(data["rope_attached"])
	if data.has("anchor_in_range"):
		_anchor_in_range = bool(data["anchor_in_range"])
	if data.has("anchor_range_m"):
		_anchor_range_m = float(data["anchor_range_m"])
	if data.has("dv_ratio"):
		_dv_ratio = clamp(float(data["dv_ratio"]), 0.0, 1.0)
	if _thruster_btn != null:
		_sync_labels()
		update()

func is_spin_controls_active() -> bool:
	return _active

func get_thruster_button() -> Control:
	return _thruster_btn

func get_rope_button() -> Control:
	return _rope_btn

func get_nav_button() -> Control:
	return _nav_btn

func get_dv_ratio() -> float:
	return _dv_ratio

func _build() -> void:
	if _thruster_btn != null:
		return
	_thruster_btn = _make_button(ACTION_THRUSTER, "IMPULSO")
	_rope_btn = _make_button(ACTION_ROPE, "CUERDA")
	_nav_btn = _make_button(ACTION_NAV, "AUTONAV")
	_nav_btn.rect_min_size = NAV_SIZE
	var tree := get_tree()
	if tree != null and tree.root != null:
		tree.root.connect("size_changed", self, "_on_root_size_changed")
	_layout_buttons()
	set_process(true) # re-layout defensivo si cambia el viewport

func _make_button(action: String, label: String) -> TouchActionButton:
	var btn := TouchActionButtonScript.new()
	btn.name = action
	btn.action_name = action
	btn.text = label
	btn.add_to_group("touch_control")
	btn.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "pressed", "hover", "disabled"]:
		btn.add_stylebox_override(state, _make_style(CIAN))
	for color in ["font_color", "font_color_hover", "font_color_pressed", "font_color_disabled"]:
		btn.add_color_override(color, Color.white)
	add_child(btn)
	return btn

func _make_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.13, 0.82)
	sb.set_corner_radius_all(32)
	sb.set_border_width_all(2)
	sb.border_color = color
	return sb

func _process(_delta: float) -> void:
	if _thruster_btn != null and get_viewport_rect().size != _last_viewport_size: # solo si cambio
		_layout_buttons()

func _layout_buttons(vsize: Vector2 = Vector2.ZERO) -> void: # vsize: seam de tests
	if _thruster_btn == null:
		return
	_last_viewport_size = get_viewport_rect().size
	if vsize.x <= 0.0 or vsize.y <= 0.0:
		vsize = _viewport_size()
	var size := BTN_SIZE * (0.8 if vsize.y < 520.0 else 1.0) # perfiles bajos (800x480)
	var block_y := vsize.y - BLOCK_BOTTOM
	for btn in [_thruster_btn, _rope_btn]:
		btn.rect_min_size = Vector2(size, size)
		btn.rect_size = Vector2(size, size)
	# Izq: arco superior sobre MoveJoystick (90..290px del borde izq). Der: sobre ActionButtons.
	_thruster_btn.rect_position = Vector2(SAFE_MARGIN + 110.0 - size * 0.5, block_y - size * 0.5)
	_rope_btn.rect_position = Vector2(vsize.x - SAFE_MARGIN - 150.0 - size * 0.5, block_y - size * 0.5)
	_nav_btn.rect_min_size = NAV_SIZE
	_nav_btn.rect_size = NAV_SIZE
	_nav_btn.rect_position = Vector2(vsize.x - SAFE_MARGIN - NAV_SIZE.x, SAFE_TOP + 10.0)
	update()

func _viewport_size() -> Vector2:
	var rv := get_viewport_rect().size
	return rv if rv.x > 0.0 and rv.y > 0.0 else Vector2(1280.0, 720.0)

func _sync_labels() -> void:
	if _thruster_btn == null:
		return
	_thruster_btn.text = "RETRAER" if _rope_attached else "IMPULSO"
	_tint(_thruster_btn, GOLD if _rope_attached else CIAN)
	if _rope_attached:
		_rope_btn.text = "SOLTAR"
		_tint(_rope_btn, GOLD)
	elif _anchor_in_range:
		_rope_btn.text = "CUERDA\n%d m" % int(round(_anchor_range_m))
		_tint(_rope_btn, CIAN)
	else:
		_rope_btn.text = "CUERDA"
		_tint(_rope_btn, DIM)
	_nav_btn.text = "AUTONAV"
	_tint(_nav_btn, CIAN)

func _tint(btn: TouchActionButton, color: Color) -> void:
	for state in ["normal", "pressed", "hover", "disabled"]:
		btn.add_stylebox_override(state, _make_style(color))
	btn.modulate = Color(1, 1, 1, 0.55) if color == DIM else Color(1, 1, 1, 1)

# Anillo de Dv: lo dibuja este Control en su _draw() (los botones hijos se pintan encima), asi que
# el arco va en el MARGEN del boton (radio > semi-lado) y no queda tapado por el relleno opaco.
func _draw() -> void:
	if _thruster_btn == null:
		return
	_draw_ring(_thruster_btn, GOLD if _rope_attached else CIAN)
	_draw_ring(_rope_btn, GOLD if _rope_attached else CIAN)

func _draw_ring(btn: Control, color: Color) -> void:
	var side := min(btn.rect_size.x, btn.rect_size.y)
	if side <= 4.0:
		return
	var center := btn.rect_position + btn.rect_size * 0.5
	var radius := side * 0.5 + RING_GAP
	var top_limit := SAFE_TOP + 4.0 # defensivo: nunca trepa a la franja sagrada
	if center.y - radius < top_limit:
		radius = max(side * 0.5, center.y - top_limit)
	draw_arc(center, radius, 0.0, TAU, 56, Color(color.r, color.g, color.b, RING_TRACK_ALPHA), 2.0, true)
	if _dv_ratio > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * _dv_ratio, 56, color, 5.0, true)
