extends HUDableComponent

# FD-324 — app Cuerda (player:rope).
#
# Vive en un slot del HUD (por defecto R2 = slot_4, índice 3). No simula: el host
# del slice le empuja si la cuerda está enganchada, si hay un anclaje en rango y la
# longitud activa desde SpinRopeInputV2 / SpinRopeSwingV2. Determinista: sin
# randf/randomize ni relojes; el estado sale del slice.

const WidgetScene = preload("res://core_v2/ui/suit_os/ArkRunRopeWidget.tscn")

const STATE_ATTACHED := "ATTACHED"
const STATE_IN_RANGE := "IN_RANGE"
const STATE_NO_ANCHOR := "NO_ANCHOR"

var _attached := false
var _anchor_ready := false
var _length := 0.0


func _init() -> void:
	hud_screen_id = "player:rope"
	hud_screen_title = "Cuerda"
	hud_widget_scene = WidgetScene
	default_relevance = 0.5
	allowed_actions_list = []


# Empujado por ArkRunSuitOSHost desde el slice (10 Hz como máximo, no por frame).
func set_rope_state(attached: bool, anchor_ready: bool, length: float) -> void:
	var next_length: float = max(length, 0.0)
	var changed: bool = attached != _attached \
		or anchor_ready != _anchor_ready \
		or abs(next_length - _length) > 0.000001
	_attached = attached
	_anchor_ready = anchor_ready
	_length = next_length
	if changed:
		notify_state_changed()


func is_attached() -> bool:
	return _attached


func is_anchor_ready() -> bool:
	return _anchor_ready


func rope_length() -> float:
	return _length


func rope_state() -> String:
	if _attached:
		return STATE_ATTACHED
	return STATE_IN_RANGE if _anchor_ready else STATE_NO_ANCHOR


func widget_snapshot() -> Dictionary:
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online",
		"attached": _attached,
		"anchor_ready": _anchor_ready,
		"length": _length,
		"state": rope_state(),
	}


func relevance(context: Dictionary = {}) -> float:
	if _attached:
		return 1.0
	if _anchor_ready:
		return 0.8
	if bool(context.get("ark_run", false)):
		return 0.7
	return default_relevance


func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op == "set_attached":
		set_rope_state(bool(args.get("attached", true)), _anchor_ready, float(args.get("length", _length)))
		return {"ok": true, "attached": _attached}
	return {"ok": false, "error": "Action '%s' not supported" % op}
