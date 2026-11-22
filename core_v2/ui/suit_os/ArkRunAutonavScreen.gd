extends HUDableComponent

# FD-324 F4 — app Autonavegador (player:autonav).
#
# Vive en un slot del HUD (por defecto R1 = slot_3, índice 2; L1 sigue siendo la
# linterna). El contrato de "mantener para conducir" es de InputProviderV2 /
# AutopilotInputV2: esta pantalla sólo refleja el estado de asistencia y deja que
# la nave proponga/cambie el destino. No toca velocidad, transform ni cámara.

const WidgetScene = preload("res://core_v2/ui/suit_os/ArkRunAutonavWidget.tscn")
const Model = preload("res://core_v2/ui/suit_os/ArkRunNavigationModel.gd")
const ArkNavScreenId := "ship:ark_nav"

signal assist_changed(held)

var _assist_held := false


func _init() -> void:
	hud_screen_id = "player:autonav"
	hud_screen_title = "Autonavegador"
	hud_widget_scene = WidgetScene
	default_relevance = 0.55
	allowed_actions_list = ["cycle_destination", "set_destination"]


func set_nav_assist(held: bool) -> void:
	if _assist_held == held:
		return
	_assist_held = held
	emit_signal("assist_changed", held)
	notify_state_changed()


func is_nav_assist_held() -> bool:
	return _assist_held


func _nav_screen() -> Object:
	if not has_node("/root/SuitOS"):
		return null
	var suit_os = get_node("/root/SuitOS")
	if suit_os.has_method("get_screen"):
		return suit_os.get_screen(ArkNavScreenId)
	return null


func widget_snapshot() -> Dictionary:
	var nav = _nav_screen()
	var snapshot: Dictionary = {}
	if nav != null and nav.has_method("widget_snapshot"):
		snapshot = nav.widget_snapshot().duplicate(true)
	else:
		snapshot = {
			"proto": 1,
			"source": "online",
			"map": {},
			"destination_map": {},
			"gravity": {},
			"destination": {},
			"destinations": [],
			"ignition": Model.ignition_snapshot("IDLE", 0.0),
			"urgency": "quiet",
		}
	snapshot["id"] = screen_id()
	snapshot["title"] = screen_title()
	snapshot["nav_screen_id"] = ArkNavScreenId
	snapshot["assist"] = {
		"held": _assist_held,
		"active": _assist_held,
		"manual": not _assist_held,
	}
	return snapshot


func relevance(context: Dictionary = {}) -> float:
	if _assist_held:
		return 1.0
	var nav = _nav_screen()
	if nav != null and String(nav.get("ignition_state")) != "IDLE":
		return 0.9
	elif bool(context.get("ark_run", false)):
		return 0.8
	return default_relevance


func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	var nav = _nav_screen()
	if nav != null and nav.has_method("perform_action") \
			and (op == "cycle_destination" or op == "set_destination"):
		return nav.perform_action(op, args)
	if op == "set_nav_assist":
		set_nav_assist(bool(args.get("held", true)))
		return {"ok": true, "held": _assist_held}
	return {"ok": false, "error": "Action '%s' not supported" % op}
