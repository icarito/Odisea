extends Control
class_name FlashlightScreenView

# FlashlightScreenView.gd - Vista de casco de la Linterna (FD-298), montada via
# FlashlightScreen.view_scene() (HudViewMount._open_presenter/_open_view_2d). Sigue el
# patron de CryoPodUI.gd: este Control es la unica fuente de snapshot/screen_id para el
# canvas ImGui; si el motor trae el modulo dibuja con FlashlightScreenImGui.gd, y si no,
# FlashlightScreen.view_scene() ya devolvio null antes de llegar aca (ver ese archivo),
# asi que esta vista solo se instancia cuando el modulo esta disponible.

const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
# load() diferido: precompilar FlashlightScreenImGui.gd (extends ImGuiCanvas) rompe la
# compilacion del .gd en el binario sin el modulo, igual que CryoPodUI._build_imgui_screen.
const ImGuiScreenPath := "res://core_v2/ui/hud/FlashlightScreenImGui.gd"

var screen_id := "player:flashlight"
var snapshot := {}

var _imgui_screen = null


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ClassDB.class_exists("ImGuiCanvas"):
		call_deferred("_build_imgui_screen")


func _build_imgui_screen() -> void:
	var canvas_script = load(ImGuiScreenPath)
	if canvas_script == null:
		return
	var canvas = canvas_script.new()
	canvas.name = "FlashlightScreenImGui"
	canvas.screen_ui = self
	add_child(canvas)
	_imgui_screen = canvas


# HudViewMount._hydrate() llama esto (update_snapshot/set_snapshot) al abrir la vista y
# en cada state_changed de la pantalla (bateria, encendido).
func update_snapshot(new_snapshot: Dictionary) -> void:
	snapshot = new_snapshot
	screen_id = String(snapshot.get("id", screen_id))


func set_snapshot(new_snapshot: Dictionary) -> void:
	update_snapshot(new_snapshot)


# Boton ENCENDER/APAGAR de la pantalla ImGui: misma accion que el widget de slot.
func toggle() -> void:
	HudWidgetAction.perform(self, screen_id, "toggle")
