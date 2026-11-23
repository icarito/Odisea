extends HUDableComponent

# FD-324 — app Propulsores (player:thrusters).
#
# Vive en un slot del HUD (por defecto L2 = slot_2, índice 1). No simula: el host
# del slice le empuja el presupuesto de delta-v desde SpinRealPhysicsV2 y si el
# gatillo/tecla de propulsor está activo. El widget sólo refleja esa lectura.
# Determinista: sin randf/randomize ni relojes; el estado sale del slice.

const WidgetScene = preload("res://core_v2/ui/suit_os/ArkRunThrustersWidget.tscn")

const STATE_ACTIVE := "ACTIVE"
const STATE_READY := "READY"
const STATE_EMPTY := "EMPTY"

var _dv_ratio := 1.0
var _active := false
var _remaining := 0.0
var _maximum := 0.0


func _init() -> void:
	hud_screen_id = "player:thrusters"
	hud_screen_title = "Propulsores"
	hud_widget_scene = WidgetScene
	default_relevance = 0.5
	allowed_actions_list = []


# Empujado por ArkRunSuitOSHost desde el slice (10 Hz como máximo, no por frame).
func set_thruster_state(dv_remaining: float, dv_max: float, active: bool) -> void:
	var max_value: float = max(dv_max, 0.0)
	var next_remaining: float = clamp(dv_remaining, 0.0, max_value) if max_value > 0.0 else 0.0
	var next_ratio: float = (next_remaining / max_value) if max_value > 0.0 else 0.0
	var next_active: bool = active and next_remaining > 0.0
	var changed: bool = abs(next_ratio - _dv_ratio) > 0.000001 \
		or abs(next_remaining - _remaining) > 0.000001 \
		or abs(max_value - _maximum) > 0.000001 \
		or next_active != _active
	_dv_ratio = next_ratio
	_remaining = next_remaining
	_maximum = max_value
	_active = next_active
	if changed:
		notify_state_changed()


func is_active() -> bool:
	return _active


func dv_ratio() -> float:
	return _dv_ratio


func remaining() -> float:
	return _remaining


func thruster_state() -> String:
	if _active:
		return STATE_ACTIVE
	return STATE_READY if _dv_ratio > 0.0 else STATE_EMPTY


func widget_snapshot() -> Dictionary:
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online",
		"dv_ratio": _dv_ratio,
		"active": _active,
		"remaining": _remaining,
		"max": _maximum,
		"state": thruster_state(),
	}


func relevance(context: Dictionary = {}) -> float:
	if _active:
		return 1.0
	if _dv_ratio <= 0.0:
		return 0.9
	if bool(context.get("ark_run", false)):
		return 0.7
	return default_relevance


func perform_action(op: String, _args: Dictionary = {}) -> Dictionary:
	if op == "hold_start":
		_active = true
		notify_state_changed()
		return {"ok": true, "active": _active}
	if op == "hold_stop":
		_active = false
		notify_state_changed()
		return {"ok": true, "active": _active}
	return {"ok": false, "error": "Action '%s' not supported" % op}
