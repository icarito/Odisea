extends CanvasLayer

# FD-325 T3 — HUD diegético mínimo del vertical slice (<200 líneas).
# CanvasLayer + ArkRunTopBarView en la franja superior + marcador 3D→2D del
# destino. Todo lo informativo vive en y in [0, 128] px: nada de mapas/paneles en
# las esquinas inferiores (ahí viven los sticks/botones de MobileUI). Sólo lee el
# snapshot que ArkRunSliceWiring/ArkRunLiveLoop pasan a 10 Hz; no toca física.

const TopBarScript = preload("res://core_v2/ui/suit_os/ArkRunTopBarView.gd")
const TargetHintScript = preload("res://core_v2/levels/ark_run/ArkRunHudTargetHint.gd")
const TEXT := Color(0.72, 0.94, 1.0, 1.0)
const DIM := Color(0.45, 0.62, 0.72, 1.0)
const BRIDGE_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const ENGINE_ORANGE := Color(1.0, 0.4, 0.15, 1.0)

var _phase_label: Label = null
var _stats_label: Label = null
var _top_bar: Control = null
var _target_hint = null
var _last_data: Dictionary = {}

func _ready() -> void:
	layer = 20
	_build()

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

	# Barra superior unificada: barra longitudinal + perfil radial + gravedad + chips.
	_top_bar = TopBarScript.new()
	_top_bar.name = "TopBar"
	root.add_child(_top_bar)

	# Compatibilidad con tests/sistemas previos: la etiqueta de fase sigue viva
	# dentro de la franja superior y el nodo "Minimap" ahora es la barra longitudinal.
	_phase_label = _label("", 15, TEXT)
	_phase_label.name = "PhaseLabel"
	_phase_label.set_position(Vector2(206, 6))
	_phase_label.set_size(Vector2(480, 20))
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_phase_label)

	var minimap := Control.new()
	minimap.name = "Minimap"
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.set_position(Vector2(206, 34))
	minimap.set_size(Vector2(480, 84))
	root.add_child(minimap)

	# Línea compacta de estado (propulsor / cuerda) arriba, bajo la barra.
	_stats_label = _label("", 12, DIM)
	_stats_label.name = "StatsLabel"
	_stats_label.set_position(Vector2(16, 108))
	_stats_label.set_size(Vector2(560, 16))
	_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stats_label)

	var target_hint = TargetHintScript.new()
	target_hint.name = "TargetHint"
	root.add_child(target_hint)
	_target_hint = target_hint

func refresh(data: Dictionary) -> void:
	if _top_bar == null:
		return
	_last_data = data
	var timer: float = float(data.get("timer", 0.0))
	var best: float = float(data.get("best", -1.0))
	_phase_label.text = "" if _phase_label == null else String(data.get("phase", ""))
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
	var minutes: int = int(clamped / 60.0)
	var secs: float = fmod(clamped, 60.0)
	return "%02d:%05.2f" % [minutes, secs]

func get_phase_label() -> Label:
	return _phase_label

func get_top_bar() -> Control:
	return _top_bar
