extends Control

# SuitScreenView.gd - Vista de casco de la pantalla "Traje", montada via
# SuitScreen.view_scene() (HudViewMount). Mismo patron que ProtocolScreenView: este
# Control es la unica fuente de snapshot/screen_id para el canvas ImGui; si el motor
# trae el modulo dibuja con SuitScreenImGui.gd, y si no, SuitScreen.view_scene() ya
# devolvio null antes de llegar aca.
#
# No tiene class_name a proposito (ver HudWidget.gd).

# load() diferido: precompilar SuitScreenImGui.gd (extends ImGuiCanvas) rompe la
# compilacion del .gd en el binario sin el modulo.
const ImGuiScreenPath := "res://core_v2/ui/hud/SuitScreenImGui.gd"

var screen_id := "suit:status"
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
	canvas.name = "SuitScreenImGui"
	canvas.screen_ui = self
	add_child(canvas)
	_imgui_screen = canvas


# HudViewMount._hydrate() llama esto al abrir la vista y en cada state_changed.
func update_snapshot(new_snapshot: Dictionary) -> void:
	snapshot = new_snapshot
	screen_id = String(snapshot.get("id", screen_id))


func set_snapshot(new_snapshot: Dictionary) -> void:
	update_snapshot(new_snapshot)
