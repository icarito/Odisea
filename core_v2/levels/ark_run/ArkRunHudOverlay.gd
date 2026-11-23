extends CanvasLayer

# FD-325 T3 — HUD diegético mínimo del vertical slice (<200 líneas).
# CanvasLayer + ArkRunTopBarView + marcador 3D→2D del destino; todo en y in [0, 128] px.
# Playtest: en gameplay la navegación es diegética: el mapa del TopBar arranca OCULTO
# (sólo fase+cronómetro arriba-centro + marcador). El mapa vive en Suit OS `ship:ark_nav`
# y se puede reencender con `set_top_map_visible(true)`. Sólo lee el snapshot de 10 Hz.

const TopBarScript = preload("res://core_v2/ui/suit_os/ArkRunTopBarView.gd")
const TargetHintScript = preload("res://core_v2/levels/ark_run/ArkRunHudTargetHint.gd")
const TEXT := Color(0.72, 0.94, 1.0, 1.0)
const DIM := Color(0.45, 0.62, 0.72, 1.0)
const BRIDGE_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const ENGINE_ORANGE := Color(1.0, 0.4, 0.15, 1.0)
const COMPACT_WIDTH := 520.0
# Margen lateral de la franja compacta: las esquinas de slots/sticks de MobileUI miden 320.
const COMPACT_SIDE_MARGIN := 320.0
const COMPACT_TIMER_WIDTH := 100.0

export(bool) var show_top_map := false setget set_top_map_visible

var _phase_label: Label = null
var _timer_label: Label = null
var _stats_label: Label = null
var _top_bar: Control = null
var _target_hint = null
var _last_data: Dictionary = {}

func _ready() -> void:
	layer = 20
	_build()
	if get_viewport() != null:
		get_viewport().connect("size_changed", self, "_layout_compact")

# Mapa superior (barra longitudinal + perfil radial + chips). Oculto en gameplay; el
# reproductor completo vive en `ship:ark_nav`. Lo que queda visible es fase+cronómetro.
func set_top_map_visible(value: bool) -> void:
	show_top_map = value
	if _top_bar != null and is_instance_valid(_top_bar):
		_top_bar.visible = value
	if _stats_label != null and is_instance_valid(_stats_label):
		_stats_label.visible = value
	_layout_compact()

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_color_override("font_color", color)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	return label

func _build() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_top_bar = TopBarScript.new() # mapa longitudinal/radial + chips; oculto en gameplay
	_top_bar.name = "TopBar"
	_top_bar.visible = show_top_map
	root.add_child(_top_bar)

	# Fase (contrato previo: texto puro) + cronómetro, compactos arriba-centro.
	_phase_label = _label("", 15, TEXT)
	_phase_label.name = "PhaseLabel"
	_phase_label.align = Label.ALIGN_RIGHT
	_phase_label.set_size(Vector2(COMPACT_WIDTH, 20))
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_phase_label)

	_timer_label = _label("", 14, BRIDGE_GOLD)
	_timer_label.name = "TimerLabel"
	_timer_label.align = Label.ALIGN_LEFT
	_timer_label.set_size(Vector2(100, 20))
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_timer_label)

	var minimap := Control.new() # contenedor heredado del mapa; oculto con el TopBar
	minimap.name = "Minimap"
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.set_size(Vector2(480, 84))
	root.add_child(minimap)

	# Línea de estado (propulsor / cuerda): sólo con el mapa visible.
	_stats_label = _label("", 12, DIM)
	_stats_label.name = "StatsLabel"
	_stats_label.set_size(Vector2(560, 16))
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stats_label)

	var target_hint = TargetHintScript.new()
	target_hint.name = "TargetHint"
	root.add_child(target_hint)
	_target_hint = target_hint
	set_top_map_visible(show_top_map) # el setget corre antes de crear nodos: reaplicar

# Franja compacta arriba-centro (y=4..24), lejos de slots/esquinas; con el mapa visible
# se rearma también el layout heredado de la franja superior.
func _layout_compact() -> void:
	var view_width := 1280.0
	var vp = get_viewport()
	if vp != null:
		view_width = float(vp.size.x)
	if view_width <= 1.0: # viewport aún sin medir: se re-centra en el próximo resize
		call_deferred("_layout_compact")
		return
	# Franja acotada al ancho central libre (nunca entra en las zonas de slots/sticks).
	var free_width: float = max(view_width - 2.0 * COMPACT_SIDE_MARGIN, 120.0)
	var label_width: float = min(COMPACT_WIDTH, free_width)
	var center_x: float = (view_width - label_width) * 0.5
	var timer_width: float = min(COMPACT_TIMER_WIDTH, label_width * 0.25)
	var phase_width: float = max(label_width - timer_width, 60.0)
	_place(_phase_label, Vector2(center_x, 4.0), Vector2(phase_width, 20.0))
	_place(_timer_label, Vector2(center_x + phase_width, 4.0), Vector2(timer_width, 20.0))
	_place(_stats_label, Vector2(center_x, 108.0), null)
	var minimap = get_node_or_null("HudRoot/Minimap")
	if minimap != null:
		minimap.visible = show_top_map
		minimap.set_position(Vector2(center_x, 30.0))

# Posiciona un Control si existe; `size` null conserva el tamaño actual.
func _place(control, position: Vector2, size) -> void:
	if control == null or not is_instance_valid(control):
		return
	if size != null:
		control.set_size(size)
	control.set_position(position)

func refresh(data: Dictionary) -> void:
	if _top_bar == null:
		return
	_last_data = data
	var timer: float = float(data.get("timer", 0.0))
	var best: float = float(data.get("best", -1.0))
	# `get_phase_label().text` es la fase pura (contrato previo); el cronómetro compacto
	# va en su propia etiqueta. El detalle largo (MEJOR/fantasma) vive en el mapa.
	_phase_label.text = "" if _phase_label == null else String(data.get("phase", ""))
	if _timer_label != null:
		_timer_label.text = _format_time(timer)
	_stats_label.text = _stats_line(data)
	var z_m: float = float(data.get("z", 0.0)) * 1000.0
	var ghost_z: float = float(data.get("ghost_z", NAN)) if data.has("ghost_z") else NAN
	var radial_ratio: float = float(data.get("radial", 0.0))
	# `g` ya viene como magnitud |g_eff| (m/s²) desde ArkRunLiveLoop; a_axial sólo
	# orienta la flecha (abajo en centrífuga, ~45° hacia popa al encender).
	var g_mag: float = float(data.get("g", 0.0))
	var a_axial: float = float(data.get("a_axial", 0.0))
	_top_bar.set_data({
		"phase": String(data.get("phase", "")),
		"timer_text": _format_time(timer),
		"best_text": "MEJOR " + (_format_time(best) if best >= 0.0 and best < 1.0e9 else "--:--.--"),
		"z_norm": TopBarScript.z_norm_for(z_m),
		"ghost_visible": not is_nan(ghost_z),
		"ghost_z_norm": clamp(ghost_z, -1.0, 1.0) if not is_nan(ghost_z) else 0.0,
		"radial_ratio": clamp(radial_ratio, 0.0, 1.0),
		"g_mag": g_mag,
		"a_axial": a_axial,
		"flashlight_on": bool(data.get("flashlight_on", false)),
		"autonav_active": bool(data.get("autonav_active", false)),
	})
	_update_target(data)

func _stats_line(data: Dictionary) -> String:
	var g_mag: float = float(data.get("g", 0.0))
	var state := "g %.1f m/s² · Δv %d%%" % [g_mag, int(round(float(data.get("dv", 0.0)) * 100.0))]
	var rope: String = String(data.get("rope", "IDLE"))
	if rope == "ATTACHED":
		state += " · CUERDA ENGANCHADA"
	elif rope == "REELING":
		state += " · CUERDA RETRACCIÓN"
	elif rope == "READY":
		state += " · CUERDA LISTA (%d m)" % int(round(float(data.get("rope_distance", 0.0))))
	if bool(data.get("thrusting", false)):
		state = "PROPULSOR ACTIVO · " + state
	return state

func _update_target(data: Dictionary) -> void:
	var target = data.get("target_pos", null)
	if not bool(data.get("target_visible", true)):
		if _target_hint != null:
			_target_hint.visible = false
		return
	if typeof(target) == TYPE_VECTOR3 and _target_hint != null:
		var target_label: String = String(data.get("target_label", "PUENTE"))
		var color: Color = BRIDGE_GOLD if target_label == "PUENTE" else ENGINE_ORANGE
		_target_hint.update_hint(get_viewport().get_camera(), target, target_label, color)
	elif _target_hint != null:
		_target_hint.visible = false

func update_destination_marker(target_pos: Vector3, label: String, color: Color) -> void:
	if _target_hint != null:
		_target_hint.update_hint(get_viewport().get_camera(), target_pos, label, color)

func _format_time(seconds: float) -> String:
	var clamped: float = max(seconds, 0.0)
	return "%02d:%05.2f" % [int(clamped / 60.0), fmod(clamped, 60.0)]

func get_phase_label() -> Label: return _phase_label
func get_top_bar() -> Control: return _top_bar
