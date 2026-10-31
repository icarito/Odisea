extends HUDableComponent

# SuitScreen.gd - Pantalla "Traje" (OdiseaOS): estado del traje + comunicaciones + objetivos.
#
# Mismo contrato que ProtocolScreen/FlashlightScreen: declara id, titulo, el widget de
# slot (SuitWidget) y su vista de casco cuando el motor trae el modulo ImGui. Sin el
# modulo, view_scene() devuelve null y el HUD cae al widget ampliado.
#
# El dato es UNO: un SuitModel (core_v2/ui/hud/SuitModel.gd) con el estado del traje, el
# log de comunicaciones y la lista de objetivos. Esta pantalla es un espejo de lectura:
# el primer objetivo ("Encender las luces") es data por ahora (decision de producto); el
# cableado al sistema real de luces queda para una tarea posterior.
#
# No tiene class_name a proposito (ver HudWidget.gd): registrar una clase global exige
# que el editor reescriba project.godot.
#
# Registro: se monta como hijo del jugador en Pilot_v2.tscn, asi que esta disponible en
# todo nivel donde haya Elías.

const SuitModelScript = preload("res://core_v2/ui/hud/SuitModel.gd")
const WidgetScene := preload("res://core_v2/ui/hud/SuitWidget.tscn")
const ScreenViewScene := preload("res://core_v2/ui/hud/SuitScreenView.tscn")
const VIEW_SIZE := Vector2(560.0, 480.0)

var model = null # SuitModel; null = sin lectura (snapshot offline)


func _init() -> void:
	hud_screen_id = SuitModelScript.SCREEN_ID
	hud_screen_title = SuitModelScript.SCREEN_TITLE
	hud_widget_scene = WidgetScene
	default_relevance = 0.1
	allowed_actions_list = [] # solo lectura: el modelo lo conduce quien lo tenga


func _ready() -> void:
	if model == null:
		model = SuitModelScript.new()


func set_model(new_model) -> void:
	model = new_model


# El modelo vivo, creandolo si hace falta. Para quien lo mutee y luego llame
# notify_state_changed().
func ensure_model():
	if model == null:
		model = SuitModelScript.new()
	return model


func view_scene() -> PackedScene:
	if ClassDB.class_exists("ImGuiCanvas"):
		return ScreenViewScene
	return null


func view_size() -> Vector2:
	return VIEW_SIZE


# La pantalla Traje se usa a pantalla completa: es una superficie de lectura, no un widget
# de un vistazo. Con el default del presentador (scale 0.5, depth 0.5) el holograma quedaba
# chico y el vidrio a alfa 0.15 se leia mal contra el mundo de atras. 0.75 llena ~98% del
# alto a la fov del piloto (80). El alfa se limita en HudViewMount (widget_alpha), asi que
# 0.7 es el maximo real.
func view_hud_config() -> Dictionary:
	return {
		"scale": 0.75,
		"background_alpha": 0.7,
	}


# La pantalla muestra el mismo dato que el widget, sin canal propio. Sin modelo,
# offline (Manual §7).
func widget_snapshot() -> Dictionary:
	if model == null or not model.has_method("snapshot"):
		return {
			"proto": 1,
			"id": screen_id(),
			"title": screen_title(),
			"source": "offline"
		}
	var snap: Dictionary = model.snapshot()
	snap["id"] = screen_id()
	snap["title"] = screen_title()
	return snap


func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	if model != null and model.has_method("snapshot"):
		var snap: Dictionary = model.snapshot()
		var status := String(snap.get("state", {}).get("status", SuitModelScript.STATUS_NOMINAL))
		if status == SuitModelScript.STATUS_ALARM:
			rel += 0.6
		elif status == SuitModelScript.STATUS_CAUTION:
			rel += 0.3
		if int(snap.get("unread_comms", 0)) > 0:
			rel += 0.1
	return clamp(rel, 0.0, 1.0)


func perform_action(_op: String, _args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": "suit:status es de lectura; el estado lo conduce su SuitModel"}
