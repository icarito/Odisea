extends Control
class_name ProtocolScreenView

# ProtocolScreenView.gd - Vista de casco del Protocolo de arranque (FD-319 T4), montada
# via ProtocolScreen.view_scene() (HudViewMount._open_presenter/_open_view_2d). Sigue el
# patron de FlashlightScreenView: este Control es la unica fuente de snapshot/screen_id
# para el canvas ImGui; si el motor trae el modulo dibuja con ProtocolScreenImGui.gd, y
# si no, ProtocolScreen.view_scene() ya devolvio null antes de llegar aca.

# load() diferido: precompilar ProtocolScreenImGui.gd (extends ImGuiCanvas) rompe la
# compilacion del .gd en el binario sin el modulo, igual que FlashlightScreenView.
const ImGuiScreenPath := "res://core_v2/ui/hud/ProtocolScreenImGui.gd"

var screen_id := "suit:protocol"
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
	canvas.name = "ProtocolScreenImGui"
	canvas.screen_ui = self
	add_child(canvas)
	_imgui_screen = canvas


# HudViewMount._hydrate() llama esto (update_snapshot/set_snapshot) al abrir la vista y
# en cada state_changed de la pantalla.
func update_snapshot(new_snapshot: Dictionary) -> void:
	snapshot = new_snapshot
	screen_id = String(snapshot.get("id", screen_id))


func set_snapshot(new_snapshot: Dictionary) -> void:
	update_snapshot(new_snapshot)
