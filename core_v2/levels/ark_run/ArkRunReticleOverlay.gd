extends Control

# FD-325 polish — crosshair y retícula diegéticos con `_draw()`.
# Se dibujan 4 trazos SEPARADOS (una Line2D continua unía los extremos con diagonales):
#   - crosshair central (cruz cortada) que brilla cian cuando hay blanco del crosshair;
#   - retícula magnética: 4 corchetes que se cierran sobre el anclaje visible.
# Un Label real junto a la retícula muestra "%d m · %s" (ej: "84 m · RT"). Sólo dibujo.

const CROSS_GAP := 5.0; const CROSS_ARM := 7.0
const DIM_COLOR := Color(0.75, 0.95, 1.0, 0.55); const HOT_COLOR := Color(0.15, 0.92, 1.0, 1.0)
const RETICLE_COLOR := Color(0.15, 0.92, 1.0, 0.9); const BRACKET_SIZE := 26.0; const BRACKET_GAP := 34.0

var _center := Vector2.ZERO
var _hot := false
var _reticle_on := false
var _reticle_pos := Vector2.ZERO
var _reticle_text := ""
var _label: Label = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_label = Label.new()
	_label.name = "ReticleLabel"
	_label.add_color_override("font_color", RETICLE_COLOR)
	_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	_label.add_constant_override("shadow_offset_x", 1)
	_label.add_constant_override("shadow_offset_y", 1)
	_label.visible = false
	add_child(_label)

# Estado por frame desde el presentador: centro del crosshair, si hay blanco, y
# retícula opcional sobre el anclaje visible (pantalla) con su etiqueta.
func set_state(center: Vector2, hot: bool, reticle_on: bool, reticle_pos: Vector2, text: String) -> void:
	_center = center
	_hot = hot
	_reticle_on = reticle_on
	_reticle_pos = reticle_pos
	_reticle_text = text
	if _label != null:
		_label.visible = reticle_on and text != ""
		_label.text = text
		_label.rect_position = _reticle_pos + Vector2(14.0, -10.0)
	update()

func is_hot() -> bool:
	return _hot

func get_reticle_label_text() -> String:
	return _reticle_text

func _draw() -> void:
	# Crosshair central: 4 trazos cortados (sin diagonales).
	var color: Color = HOT_COLOR if _hot else DIM_COLOR
	var axes := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	for axis in axes:
		draw_line(_center + axis * CROSS_GAP, _center + axis * (CROSS_GAP + CROSS_ARM), color, 2.0)
	if not _reticle_on:
		return
	# Retícula magnética: 4 corchetes separados alrededor del anclaje proyectado.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tip: Vector2 = _reticle_pos + Vector2(corner.x * BRACKET_GAP, corner.y * BRACKET_GAP)
		var arm_x: Vector2 = tip - Vector2(corner.x * BRACKET_SIZE, 0.0)
		var arm_y: Vector2 = tip - Vector2(0.0, corner.y * BRACKET_SIZE)
		draw_line(tip, arm_x, RETICLE_COLOR, 2.0)
		draw_line(tip, arm_y, RETICLE_COLOR, 2.0)
