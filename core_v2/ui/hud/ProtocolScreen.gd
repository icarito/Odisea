extends HUDableComponent
class_name ProtocolScreen

# ProtocolScreen.gd - Pantalla "Protocolo de arranque" (FD-319 T4), mismo contrato que
# FlashlightScreen/DebugHudScreen: declara id/titulo, el widget de slot (ProtocolWidget)
# y su vista de casco cuando el motor trae el modulo ImGui. Sin el modulo, view_scene()
# devuelve null y HudViewMount cae al widget ampliado, como la Linterna.
#
# El dato es UNO: un ProtocolModel (core_v2/ui/hud/ProtocolModel.gd) que T5 conduce con
# advance()/fail()/complete()/clear_fail() y de aca sale el snapshot, tanto para el
# widget de slot como para la pantalla grande. Esta pantalla NO marca pasos por su
# cuenta ni conoce el grafo de sistemas (eso es T5): set_model() + notify_state_changed()
# es todo el cableado que pide.
#
# Q-2: el widget vive en un slot fijo del HUD mientras dure el protocolo; Q-3: el paso 2
# es "mantener E en la consola central" — para este archivo ambas son ajenas (son
# decisiones de host/interaccion, no de este contrato).

const ProtocolModel = preload("res://core_v2/ui/hud/ProtocolModel.gd")
const WidgetScene := preload("res://core_v2/ui/hud/ProtocolWidget.tscn")
const ScreenViewScene := preload("res://core_v2/ui/hud/ProtocolScreenView.tscn")
const VIEW_SIZE := Vector2(520.0, 420.0)

var model = null # ProtocolModel; null = sin lectura (snapshot offline)


func _init() -> void:
	hud_screen_id = ProtocolModel.SCREEN_ID
	hud_screen_title = ProtocolModel.SCREEN_TITLE
	hud_widget_scene = WidgetScene
	default_relevance = 0.1
	allowed_actions_list = [] # solo lectura: marcar pasos es tarea del grafo de T5


func set_model(new_model) -> void:
	model = new_model


func view_scene() -> PackedScene:
	if ClassDB.class_exists("ImGuiCanvas"):
		return ScreenViewScene
	return null


func view_size() -> Vector2:
	return VIEW_SIZE


# La pantalla grande muestra el mismo dato que el widget, sin canal propio: el snapshot
# del modelo con id/titulo de esta pantalla. Sin modelo, offline (Manual §7).
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


func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": "suit:protocol es solo lectura; el grafo de progresion (T5) marca los pasos"}
