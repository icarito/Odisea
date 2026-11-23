extends Control

# FD-325 T3 — HUD superior unificado (<200 líneas).
#
# Toda la info fija vive en la franja superior (y in [0, 128] px), NUNCA en las
# esquinas inferiores donde viven los sticks/botones táctiles de MobileUI.
# Tres sub-controles fijos dibujados con _draw() (sin _process):
#   CenterBar -> barra longitudinal del cilindro (Puente/Core/Motor + Elías/fantasma)
#   Radial    -> perfil HUB/TERRAZA/CASCO + magnitud g + flecha de gravedad efectiva
#   Chips     -> accesos rápidos L1 Linterna / R1 Autonav
# Las funciones estáticas de layout son puras: deterministas y testeables sin nodos.

const Parts = preload("res://core_v2/ui/suit_os/ArkRunTopBarParts.gd")
const STRIP_HEIGHT := 128.0
const PAD := 16.0
const LEFT_WIDTH := 190.0
const RIGHT_WIDTH := 150.0
const RADIAL_PROFILE := [8.0, 240.0, 340.0]
const CORE_SLICE_M := 2000.0
const G_REF := 9.8

var center_bar: Control = null
var radial_panel: Control = null
var chips_panel: Control = null

# z (m) -> posición normalizada [-1, 1]; +1 = Puente (+Z), -1 = Motor (-Z).
static func z_norm_for(z: float) -> float:
	if CORE_SLICE_M <= 0.0:
		return 0.0
	return clamp(z / (CORE_SLICE_M * 0.5), -1.0, 1.0)

# radio (m) -> [0, 1] sobre HUB(0) / TERRAZA(240/340) / CASCO(1).
static func radial_ratio_for(radius: float) -> float:
	return clamp(radius / RADIAL_PROFILE[2], 0.0, 1.0)

# t en [-1, 1] -> x entre `left` y `right` (+1 = derecha = Motor).
static func z_point_x(left: float, right: float, t: float) -> float:
	return lerp(left, right, clamp((1.0 - t) * 0.5, 0.0, 1.0))

static func radial_point_x(left: float, right: float, ratio: float) -> float:
	return lerp(left, right, clamp(ratio, 0.0, 1.0))

# Vector 2D de gravedad en pantalla: centrifuga normal (0, +1) hacia abajo;
# con a_axial > 0 gira hacia POPA ~45 grados por g (popa = +x en pantalla).
static func gravity_arrow(a_axial: float, g_magnitude: float) -> Vector2:
	if abs(a_axial) < 0.000001 or g_magnitude <= 0.000001:
		return Vector2(0.0, 1.0)
	var angle: float = atan2(abs(a_axial), G_REF)
	return Vector2(sin(angle), cos(angle)).normalized()

static func gravity_rotation_deg(a_axial: float, g_magnitude: float) -> float:
	return rad2deg(acos(clamp(gravity_arrow(a_axial, g_magnitude).y, -1.0, 1.0)))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	rect_min_size = Vector2(0.0, STRIP_HEIGHT)
	rect_position = Vector2.ZERO
	rect_size = Vector2(max(rect_size.x, 640.0), STRIP_HEIGHT)
	var width: float = rect_size.x
	center_bar = Parts.CenterBar.new()
	center_bar.name = "CenterBar"
	center_bar.rect_position = Vector2(PAD + LEFT_WIDTH, 6.0)
	center_bar.rect_size = Vector2(width - 2.0 * (PAD + LEFT_WIDTH), 100.0)
	add_child(center_bar)
	radial_panel = Parts.RadialPanel.new()
	radial_panel.name = "Radial"
	radial_panel.rect_position = Vector2(PAD, 8.0)
	radial_panel.rect_size = Vector2(LEFT_WIDTH, 100.0)
	add_child(radial_panel)
	chips_panel = Parts.ChipsPanel.new()
	chips_panel.name = "Chips"
	chips_panel.rect_position = Vector2(width - RIGHT_WIDTH - PAD, 34.0)
	chips_panel.rect_size = Vector2(RIGHT_WIDTH, 60.0)
	add_child(chips_panel)

func set_data(data: Dictionary) -> void:
	if center_bar == null:
		return
	center_bar.phase = String(data.get("phase", center_bar.phase))
	center_bar.timer_text = String(data.get("timer_text", center_bar.timer_text))
	center_bar.best_text = String(data.get("best_text", center_bar.best_text))
	center_bar.z_norm = clamp(float(data.get("z_norm", 0.0)), -1.0, 1.0)
	center_bar.ghost_visible = bool(data.get("ghost_visible", false))
	center_bar.ghost_z_norm = clamp(float(data.get("ghost_z_norm", 0.0)), -1.0, 1.0)
	radial_panel.radial_ratio = clamp(float(data.get("radial_ratio", 0.0)), 0.0, 1.0)
	radial_panel.g_mag = float(data.get("g_mag", 0.0))
	radial_panel.a_axial = float(data.get("a_axial", 0.0))
	chips_panel.flashlight_on = bool(data.get("flashlight_on", false))
	chips_panel.autonav_active = bool(data.get("autonav_active", false))
	center_bar.update()
	radial_panel.update()
	chips_panel.update()

func get_fixed_panels() -> Array:
	return [radial_panel, center_bar, chips_panel]
