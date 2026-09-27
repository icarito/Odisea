extends Control
class_name DebugHudScreenView

# DebugHudScreenView.gd - Pantalla diegetica de "Rendimiento" (system:performance),
# montada via DebugHudScreen.view_scene() (HudViewMount). A diferencia de
# FlashlightScreenView, esta vista lee el estado EN VIVO del autoload DebugHud
# (/root/DebugHud) en vez del widget_snapshot() chico: la pantalla corre siempre en el
# mismo dispositivo (no viaja al telefono, que sigue con el widget de slot solamente),
# asi que no hace falta acotar el payload -- DebugHudScreenImGui.gd puede pedir series
# largas via hud.series_tail(name, n) directo, igual que hace el overlay F1
# (addons/debug_hud/debug_hud_view.gd) con m.series.

# load() diferido: precompilar DebugHudScreenImGui.gd (extends ImGuiCanvas) rompe la
# compilacion del .gd en el binario sin el modulo, igual que CryoPodUI._build_imgui_screen.
const ImGuiScreenPath := "res://core_v2/ui/hud/DebugHudScreenImGui.gd"

var hud = null


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud = get_node_or_null("/root/DebugHud")
	if ClassDB.class_exists("ImGuiCanvas"):
		call_deferred("_build_imgui_screen")


func _build_imgui_screen() -> void:
	var canvas_script = load(ImGuiScreenPath)
	if canvas_script == null:
		return
	var canvas = canvas_script.new()
	canvas.name = "DebugHudScreenImGui"
	canvas.hud = hud
	add_child(canvas)


# HudViewMount._hydrate() llama esto al abrir/actualizar la vista. Esta pantalla lee el
# autoload en vivo (arriba), asi que no necesita nada del snapshot chico.
func update_snapshot(_snapshot: Dictionary) -> void:
	pass


func set_snapshot(_snapshot: Dictionary) -> void:
	pass
