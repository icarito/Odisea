extends Node

# DebugConsoleManager.gd - Global entry point for the debug console HUD.
# Listens for the "toggle_debug_console" action and toggles a DebugConsoleHUD
# instance attached to the root viewport. Closes the console on scene swaps so
# the holographic screen never outlives the camera it is attached to.

const DebugConsoleHUDScene = preload("res://core_v2/props/decor/DebugConsoleHUD.tscn")
# Accion PROPIA de la consola. Antes compartia "toggle_debug_menu" con
# HoloTerminalV2.HUD_UI_BRIDGE_TOGGLE_ACTION, y como HoloTerminalV2 la atiende en _input
# —o sea CADA terminal de la escena— una sola pulsacion hacia dos cosas: enfocaba el
# terminal que tuvieras cerca y ademas abria la consola. Ese era el "input doble".
const TOGGLE_ACTION := "toggle_debug_console"

var _hud: Node = null

func _ready() -> void:
	set_process_unhandled_input(true)
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and not scene_manager.is_connected("pre_scene_swap", self, "_on_pre_scene_swap"):
		scene_manager.connect("pre_scene_swap", self, "_on_pre_scene_swap")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle_console()
		get_tree().set_input_as_handled()

func toggle_console() -> void:
	var hud = _get_or_spawn_hud()
	if hud == null:
		return
	if hud.has_method("toggle_console"):
		hud.toggle_console()

func _get_or_spawn_hud() -> Node:
	if _hud and is_instance_valid(_hud):
		return _hud
	var tree = get_tree()
	if tree == null:
		return null
	var root = tree.root
	if root == null:
		return null
	var hud = DebugConsoleHUDScene.instance()
	root.add_child(hud)
	_hud = hud
	return hud

func _on_pre_scene_swap(_old_scene: Node, _new_scene: Node, _params: Dictionary) -> void:
	if _hud and is_instance_valid(_hud) and _hud.has_method("close_console"):
		if bool(_hud.get("is_active")):
			_hud.close_console()
