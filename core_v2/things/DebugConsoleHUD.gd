tool
extends HelmetHUDV2
class_name DebugConsoleHUD

# DebugConsoleHUD.gd - HUD-attached debug console.
# Reuses the HelmetHUD holographic screen and HoloTerminalV2 focus/input machinery,
# but mounts the OYS shell (the HoloTerminal console) directly. Open/close is driven
# by the "toggle_debug_console" action through DebugConsoleManager.

const OYSShellScene = preload("res://core_v2/ui/retro/OYSShell.tscn")
# Accion PROPIA de la consola. Antes compartia "toggle_debug_menu" con
# HoloTerminalV2.HUD_UI_BRIDGE_TOGGLE_ACTION, y como HoloTerminalV2 la atiende en _input
# —o sea CADA terminal de la escena— una sola pulsacion hacia dos cosas: enfocaba el
# terminal que tuvieras cerca y ademas abria la consola. Ese era el "input doble".
const TOGGLE_ACTION := "toggle_debug_console"
const SHELL_FONT_SIZE := 24

func _ready() -> void:
	if not Engine.editor_hint:
		_ensure_console_singleton()
	._ready()
	if Engine.editor_hint:
		return
	_mount_shell()
	_setup_debug_hud()

func _ensure_console_singleton() -> void:
	var tree = get_tree()
	if tree == null:
		return
	var root = tree.root
	if root == null:
		return
	if root.get_node_or_null("OYS_Console") != null:
		return
	var console = OYSConsoleScript.new()
	console.name = "OYS_Console"
	root.add_child(console)

func _mount_shell() -> void:
	var viewport = get_node_or_null("Viewport")
	if not viewport:
		return
	for child in viewport.get_children():
		if child.has_meta("persistent_viewport_cursor") and bool(child.get_meta("persistent_viewport_cursor")):
			continue
		child.queue_free()
	var shell = OYSShellScene.instance()
	shell.name = "OYSShell"
	shell.font_size = SHELL_FONT_SIZE
	viewport.add_child(shell)

func _setup_debug_hud() -> void:
	# A debug console is not an in-world interactable and must not be part of the
	# deterministic replay snapshot.
	set_is_interactable(false)
	set_is_focusable(false)
	if is_in_group("replay_sync"):
		remove_from_group("replay_sync")
	# Stay open regardless of player distance.
	hud_auto_close_out_of_range = false
	hud_interaction_radius = 0.0

func _wants_continuous_step() -> bool:
	# Keep the HUD synced to the active camera while open (camera switches, menu
	# -> gameplay) instead of freezing after the open animation completes.
	return is_active and attach_to_active_camera

func is_debug_build() -> bool:
	return OS.is_debug_build() or OS.has_feature("editor")

func open_console() -> void:
	if is_active:
		return
	_apply_debug_gating()
	set_active(true)
	_enter_focus_mode()

func close_console() -> void:
	if _is_focused:
		_exit_focus_mode()
	if is_active:
		set_active(false)

func toggle_console() -> void:
	if is_active:
		close_console()
	else:
		open_console()

func _apply_debug_gating() -> void:
	var console = _resolve_console()
	if console == null:
		return
	var debug_build := is_debug_build()
	console.allow_cheats = debug_build
	console.read_only = not debug_build
	if debug_build:
		console.add_log("SYS", "Debug console ready (debug build): cheats + write access enabled.")
	else:
		console.add_log("SYS", "Debug console ready (release build): read-only mode.")

func _resolve_console() -> Node:
	var tree = get_tree()
	if tree == null:
		return null
	var root = tree.root
	if root == null:
		return null
	return root.get_node_or_null("OYS_Console")

func _input(event: InputEvent) -> void:
	if Engine.editor_hint or not is_active:
		return
	# La tecla de la consola se atiende ACA y se consume, antes de delegar al padre.
	# HoloTerminalV2._input, con el terminal enfocado, se queda con TODA tecla y la inyecta
	# al viewport: sin esta rama el backtick se escribia dentro de la consola en vez de
	# cerrarla. Y como la accion ahora es exclusiva de la consola, no hay un segundo dueño:
	# DebugConsoleManager solo la ve cuando esta cerrada y este _input retorna temprano.
	if event.is_action_pressed(TOGGLE_ACTION):
		close_console()
		get_tree().set_input_as_handled()
		return
	# Escape una sola vez: ui_cancel YA es Escape, y el chequeo suelto de KEY_ESCAPE que
	# habia debajo era la misma tecla contada de nuevo.
	if event.is_action_pressed("ui_cancel"):
		close_console()
		get_tree().set_input_as_handled()
		return
	._input(event)
