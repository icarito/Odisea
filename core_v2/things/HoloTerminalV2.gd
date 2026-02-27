tool
extends InteractableBaseV2
class_name HoloTerminalV2

# HoloTerminalV2.gd - Interactive Holographic Screen
# Inherits InteractableBaseV2 for replay determinism.
# V2.2: Integrated local Cinematic Camera System

const DebugOverlayScene = preload("res://core_v2/ui/retro/DebugOverlay.tscn")
const OYSConsoleScript = preload("res://core_v2/ui/retro/OYS_Console.gd")
const HUD_UI_BRIDGE_TOGGLE_ACTION := "toggle_debug_menu"

# --- Terminal Configuration ---
export(float) var slide_speed := 2.0
export(float) var slide_height := 0.8
export(Vector2) var screen_resolution := Vector2(1024, 768)
export(int, 12, 48) var debug_overlay_font_size := 22
export(bool) var active setget set_active_debug

# --- Cinematic Camera Configuration ---
export(bool) var use_cinematic_zone := true
export(bool) var close_on_exit_zone := true
export(bool) var enable_ui_interaction := true
export(bool) var allow_focus_mode := true # If true, pressing 'focus' key transitions to FocusedRig
enum CinematicCameraBehavior {
	CAMERA_FIXED,
	CAMERA_FOLLOW_PLAYER,
}
export(int, "Fixed", "Follow Player") var cinematic_camera_behavior := CinematicCameraBehavior.CAMERA_FIXED setget _set_cinematic_camera_behavior

# HUD runtime config is owned by HelmetHUDV2 and not exposed on regular terminals.
var attach_to_active_camera := false
var hud_attach_as_child := false
var hud_attach_transition_time := 0.35
var hud_attach_target_path := NodePath("ScreenContainer/ScreenMesh")
var hud_screen_x := 0.5
var hud_screen_y := 0.7
var hud_screen_depth := 0.35
var hud_screen_scale := 0.45
var hud_interaction_radius := 3.0
var hud_auto_close_out_of_range := true
var hud_ui_bridge_requires_focus := true
var hud_ui_bridge_use_system_mouse := true
var hud_background_alpha := 0.15
var hud_background_emission := 3.0
var hud_focus_on_activate := true
var hud_local_offset := Vector3.ZERO
var hud_local_rotation_deg := Vector3(0, 180, 0)
var hud_reference_node_path := NodePath("")

# --- Internal Camera References ---
var _camera_zone: Area = null
var _cinematic_rig = null # CinematicPathRig reference
var _focused_rig = null # FocusedRig reference for focus mode
var _terminal_ui = null # TerminalUIV2 reference
var _viewport_input = null # Viewport input bridge
var _player_in_zone := false
var _is_focused := false # True when in focus mode (close-up camera, keyboard to UI)
var _locked_player: Node = null
var _prev_hardware_input_enabled := true
var _console = null
var _hud_attach_target: Spatial = null
var _hud_anchor_camera: Camera = null
var _hud_original_parent: Node = null
var _hud_original_owner: Node = null
var _hud_original_global_transform := Transform.IDENTITY
var _hud_original_local_transform := Transform.IDENTITY
var _hud_original_parent_is_spatial := false
var _hud_attached := false
var _hud_warned_missing_camera := false
var _hud_attachment_suspended := false
var _hud_transition_active := false
var _hud_transition_t := 0.0
var _hud_transition_from_origin := Vector3.ZERO
var _hud_transition_to_origin := Vector3.ZERO
var _hud_transition_target_basis := Basis.IDENTITY
var _hud_last_particle_dir := Vector3.ZERO
var _focus_camera_request_id := -1

func _ready():
	interaction_text = "Toggle Terminal"

	if attach_to_active_camera:
		# HUD mode bypasses cinematic focus transitions entirely.
		use_cinematic_zone = false
		allow_focus_mode = false

	# Configure base class speed
	if slide_speed > 0:
		anim_speed = slide_speed
		# Keep anim_duration consistent (though logic uses anim_speed)
		anim_duration = 1.0 / slide_speed
	else:
		anim_speed = 1.0

	# Initial state update
	_update_visuals()
	_setup_viewport_texture()
	_apply_hud_screen_material_overrides()
	_apply_viewport_settings()
	
	# Initial toggle logic (ensure correct state)
	if not is_active:
		var particles = get_node_or_null("HoloParticles")
		if particles:
			particles.emitting = false
		var screen_container = get_node_or_null("ScreenContainer")
		if screen_container:
			screen_container.scale = Vector3.ZERO
	
	# --- Cinematic Camera Auto-Wiring ---
	_setup_cinematic_camera()
	_apply_cinematic_camera_behavior()
	_deactivate_terminal_cameras()

	if not String(hud_attach_target_path).empty():
		var attach_target = get_node_or_null(hud_attach_target_path)
		if attach_target and attach_target is Spatial:
			_hud_attach_target = attach_target as Spatial
	if _hud_attach_target == null:
		var default_target = get_node_or_null("ScreenContainer/ScreenMesh")
		if default_target and default_target is Spatial:
			_hud_attach_target = default_target as Spatial
	
	_viewport_input = get_node_or_null("Viewport")
	# Cache TerminalUI reference
	_terminal_ui = get_node_or_null("Viewport/TerminalUI")
	if _terminal_ui and not _terminal_ui.is_connected("debug_button_pressed", self , "_on_terminal_debug_requested"):
		_terminal_ui.connect("debug_button_pressed", self , "_on_terminal_debug_requested")
	_bind_console_events()


func _setup_cinematic_camera() -> void:
	"""Find and cache references to the local CinematicSetup children.
	Signal connections are defined in the .tscn file for editor visibility."""
	if Engine.editor_hint:
		return # Don't run in editor
	
	# Find child nodes
	_camera_zone = get_node_or_null("CinematicSetup/CameraZone")
	_cinematic_rig = get_node_or_null("CinematicSetup/CinematicPathRig")
	_focused_rig = get_node_or_null("CinematicSetup/FocusedRig")
	
	if not _camera_zone:
		if use_cinematic_zone:
			print("[HoloTerminalV2] Warning: CameraZone not found in CinematicSetup")
		return
	
	# Configure initial zone state
	if _camera_zone and "is_zone_active" in _camera_zone:
		_camera_zone.is_zone_active = use_cinematic_zone
	
	if not _cinematic_rig:
		if use_cinematic_zone:
			print("[HoloTerminalV2] Warning: CinematicPathRig not found in CinematicSetup")

func _set_cinematic_camera_behavior(value: int) -> void:
	cinematic_camera_behavior = int(clamp(value, 0, 1))
	_apply_cinematic_camera_behavior()

func _apply_cinematic_camera_behavior() -> void:
	if not _cinematic_rig or not is_instance_valid(_cinematic_rig):
		return
	var follow_player = cinematic_camera_behavior == CinematicCameraBehavior.CAMERA_FOLLOW_PLAYER

	if "track_player" in _cinematic_rig:
		_cinematic_rig.set("track_player", follow_player)
	if "follow_player_on_path" in _cinematic_rig:
		_cinematic_rig.set("follow_player_on_path", follow_player)
	if _cinematic_rig.has_method("_update_rotation_mode"):
		_cinematic_rig.call("_update_rotation_mode")

	# Optional compatibility with vcamera-style modifier nodes.
	var follow_node = _cinematic_rig.get_node_or_null("Follow")
	if follow_node and "enabled" in follow_node:
		follow_node.set("enabled", follow_player)
	var look_at_node = _cinematic_rig.get_node_or_null("LookAt")
	if look_at_node and "enabled" in look_at_node:
		look_at_node.set("enabled", follow_player)

func _deactivate_terminal_cameras() -> void:
	# Defensive: terminal cameras must never steal scene camera at load time.
	var path_cam = get_node_or_null("CinematicSetup/CinematicPathRig/PathFollow/Camera")
	if path_cam and path_cam is Camera:
		(path_cam as Camera).current = false
	var focus_cam = get_node_or_null("CinematicSetup/FocusedRig/Camera")
	if focus_cam and focus_cam is Camera:
		(focus_cam as Camera).current = false


func _setup_viewport_texture() -> void:
	# Fix ViewportTexture path issue by explicit assignment in code.
	# This avoids load-time errors from invalid paths in the .tscn file.
	var screen_mesh = get_node_or_null("ScreenContainer/ScreenMesh")
	var viewport = get_node_or_null("Viewport")
	if screen_mesh and viewport:
		var mat = screen_mesh.material
		if mat is ShaderMaterial:
			# Assign the texture from the Viewport directly. 
			# In Godot 3.x, this is the most reliable way to handle ViewportTextures.
			mat.set_shader_param("texture_albedo", viewport.get_texture())

func _apply_hud_screen_material_overrides() -> void:
	var screen_mesh = get_node_or_null("ScreenContainer/ScreenMesh")
	if not screen_mesh:
		return
	var mat = screen_mesh.material
	if not (mat is ShaderMaterial):
		return
	var shader_mat = mat as ShaderMaterial
	var albedo = shader_mat.get_shader_param("albedo")
	if typeof(albedo) == TYPE_COLOR:
		var color: Color = albedo
		color.a = clamp(hud_background_alpha, 0.0, 1.0)
		shader_mat.set_shader_param("albedo", color)
	shader_mat.set_shader_param("emission_energy", max(0.0, hud_background_emission))


func interact() -> void:
	# If auto-interact is on, we don't toggle the terminal open/closed.
	# Use 'interact' only to open/close; focus is handled by the dedicated focus action.
	if auto_interact:
		if is_active:
			set_active(false)
		else:
			if attach_to_active_camera and not _is_player_within_hud_radius():
				return
			set_active(true)
		return

	# Toggle open/close (Standard behavior)
	if is_active:
		set_active(false)
	else:
		if attach_to_active_camera and not _is_player_within_hud_radius():
			return
		set_active(true)
		
		# If cinematic zone is disabled, go straight to focus mode
		if not attach_to_active_camera and not use_cinematic_zone and allow_focus_mode:
			_enter_focus_mode()


# Override set_active to manage cinematic camera on state changes
func set_active(value: bool, immediate: bool = false) -> void:
	# Call base implementation
	.set_active(value, immediate)

	if attach_to_active_camera:
		if value:
			_attach_hud_to_active_camera()
			if hud_focus_on_activate and not _is_focused:
				_enter_focus_mode()
		else:
			_detach_hud_from_camera()
	
	# Ensure we exit focus mode when closing terminal
	if not value and _is_focused:
		_exit_focus_mode()
	
	# --- Cinematic Camera Management ---
	# If NOT using cinematic zone by default, it remains inactive until focused.
	# If using it, it stays active while terminal is open.
	if not use_cinematic_zone and _camera_zone and "is_zone_active" in _camera_zone:
		 # Only activate zone if we are focused (handled in _enter/_exit)
		 # or if we are just closing it.
		 if not value:
			 _camera_zone.is_zone_active = false
	
	# Update UI interaction mode
	_update_ui_mode()


func _on_camera_zone_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_zone = true
	_update_ui_mode()


func _on_camera_zone_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	
	_player_in_zone = false
	_update_ui_mode()
	
	if close_on_exit_zone and is_active:
		# Defer to avoid modifying zone monitoring during signal callback
		call_deferred("set_active", false)


func _update_visuals() -> void:
	var progress = _ease_out_cubic(anim_progress)
	_apply_hud_screen_material_overrides()

	# 2. Apply Movement (Visuals)
	var screen_container = get_node_or_null("ScreenContainer")
	if screen_container:
		# Slide + Scale animation:
		var start_y = - slide_height
		var end_y = 0.0
		var new_y = lerp(start_y, end_y, progress)
		var new_scale = lerp(Vector3.ZERO, Vector3.ONE, progress)
		
		screen_container.translation.y = new_y
		screen_container.scale = new_scale
		screen_container.visible = new_scale.length_squared() > 0.001

	if attach_to_active_camera and _hud_attach_target and is_instance_valid(_hud_attach_target):
		_hud_attach_target.visible = progress > 0.001

	# Also manage Projector Particles
	var particles = get_node_or_null("HoloParticles")
	if particles:
		particles.emitting = is_active


	# 3. Update UI State (Optimization)
	var viewport = get_node_or_null("Viewport")
	if viewport:
		# Only render the viewport if the screen is at least partially visible
		var mode = Viewport.UPDATE_WHEN_VISIBLE if anim_progress > 0 else Viewport.UPDATE_DISABLED
		viewport.render_target_update_mode = mode


func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

func _on_terminal_debug_requested() -> void:
	var viewport = get_node_or_null("Viewport")
	if not viewport:
		return
	for child in viewport.get_children():
		if child.has_meta("persistent_viewport_cursor") and bool(child.get_meta("persistent_viewport_cursor")):
			continue
		child.queue_free()
	var overlay = DebugOverlayScene.instance()
	if "pixel_font_size" in overlay:
		overlay.set("pixel_font_size", debug_overlay_font_size)
	viewport.add_child(overlay)
	_terminal_ui = overlay
	_update_ui_mode()

func _apply_viewport_settings() -> void:
	var viewport = get_node_or_null("Viewport")
	if not viewport:
		return
	var target_size = Vector2(max(320.0, screen_resolution.x), max(240.0, screen_resolution.y))
	viewport.size = target_size
	# Avoid duplicated events: viewport input is injected explicitly via HoloTerminalViewportInput.
	viewport.gui_disable_input = true


# Property aliases for spec compliance (read-only access to state)
func get_is_open() -> bool:
	return is_active


func set_active_debug(val: bool) -> void:
	active = val
	set_active(val, true) # Immediate update for editor


# --- UI Mode Management ---
func _update_ui_mode() -> void:
	"""Update TerminalUI cursor based on terminal state and player position."""
	if Engine.editor_hint:
		return

	if attach_to_active_camera:
		var hud_interactive = is_active and enable_ui_interaction and (not hud_ui_bridge_requires_focus or _is_focused)
		if _terminal_ui and _terminal_ui.has_method("set_ui_mode"):
			_terminal_ui.set_ui_mode(hud_interactive)
		if _viewport_input and _viewport_input.has_method("set_ui_mode"):
			_viewport_input.set_ui_mode(hud_interactive)
		if _viewport_input and _viewport_input.has_method("set_use_system_mouse"):
			var use_system_mouse = hud_ui_bridge_use_system_mouse and _is_focused and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
			_viewport_input.set_use_system_mouse(use_system_mouse)
		if not is_active:
			interaction_text = "Show HUD"
		elif _is_focused:
			interaction_text = "Exit UI Bridge"
		else:
			interaction_text = "Toggle UI Bridge"
		set_process_input(is_active and enable_ui_interaction)
		return
	
	# UI should be interactive if:
	# 1. Logic is active (terminal open)
	# 2. UI interaction is enabled in config
	# 3. Player is either in the zone OR explicitly focused
	var base_interactive = is_active and enable_ui_interaction and (_player_in_zone or _is_focused)
	var should_be_active = base_interactive
	
	# If cinematic zone is off, UI interaction is strictly limited to focus mode
	if not use_cinematic_zone and not _is_focused:
		should_be_active = false
	
	if _terminal_ui and _terminal_ui.has_method("set_ui_mode"):
		_terminal_ui.set_ui_mode(should_be_active)
	if _viewport_input and _viewport_input.has_method("set_ui_mode"):
		_viewport_input.set_ui_mode(should_be_active)
	
	# Update interaction text based on auto_interact and focus state
	if base_interactive and auto_interact:
		interaction_text = "Focus Terminal" if not _is_focused else "Interacting..."
	else:
		interaction_text = "Toggle Terminal"
	
	# Enable/disable input processing based on UI mode (either zone interaction or focus)
	set_process_input(base_interactive)


func is_ui_interactive() -> bool:
	"""Returns true if the terminal is in interactive UI mode."""
	if attach_to_active_camera:
		var active = is_active and enable_ui_interaction
		if hud_ui_bridge_requires_focus:
			return active and _is_focused
		return active
	var base_interactive = is_active and enable_ui_interaction and (_player_in_zone or _is_focused)
	if not use_cinematic_zone:
		return base_interactive and _is_focused
	return base_interactive


func _input(event):
	"""Handle focus mode toggling and forward input to viewport-driven UI."""
	if Engine.editor_hint:
		return

	if attach_to_active_camera and is_active:
		if event.is_action_pressed(HUD_UI_BRIDGE_TOGGLE_ACTION):
			if _is_focused:
				_exit_focus_mode()
			else:
				_enter_focus_mode()
			get_tree().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			if _is_focused:
				_exit_focus_mode()
			else:
				set_active(false)
			get_tree().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			if _is_focused:
				_exit_focus_mode()
			else:
				set_active(false)
			get_tree().set_input_as_handled()
			return

	if _is_focused:
		if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			print("[HoloTerminalV2] ESC pressed, exiting focus mode")
			_exit_focus_mode()
			get_tree().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			print("[HoloTerminalV2] ui_cancel pressed, exiting focus mode")
			_exit_focus_mode()
			get_tree().set_input_as_handled()
			return
	
	# Handle focus mode toggle
	if is_ui_interactive() and allow_focus_mode and not attach_to_active_camera:
		if event.is_action_pressed("focus") and not _is_focused:
			print("[HoloTerminalV2] Focus key pressed, entering focus mode")
			_enter_focus_mode()
			get_tree().set_input_as_handled()
			return
	
	# When focused, forward key events to viewport input bridge first.
	if _is_focused and event is InputEventKey:
		if _viewport_input and _viewport_input.has_method("process_key_event"):
			if _viewport_input.has_method("focus_command_input"):
				_viewport_input.focus_command_input()
			_viewport_input.process_key_event(event)
			get_tree().set_input_as_handled()
			return
		if _terminal_ui and _terminal_ui.has_method("process_key_event"):
			_terminal_ui.process_key_event(event)
			get_tree().set_input_as_handled()
			return
	
	# Standard UI mode (not focused): forward mouse input
	# Only forward mouse if is_ui_interactive (which handles the cinematic zone check)
	if not is_ui_interactive():
		return
	
	if not _viewport_input and not _terminal_ui:
		return
	
	# Forward mouse motion to viewport input bridge.
	if event is InputEventMouseMotion:
		if _viewport_input and _viewport_input.has_method("process_mouse_motion"):
			var use_system_mouse = Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
			if use_system_mouse and _viewport_input.has_method("process_system_mouse_motion"):
				_viewport_input.process_system_mouse_motion(event.position, event.global_position, event.relative, get_viewport().size)
			else:
				_viewport_input.process_mouse_motion(event.relative)
			get_tree().set_input_as_handled()
			return
		if _terminal_ui and _terminal_ui.has_method("process_mouse_motion"):
			_terminal_ui.process_mouse_motion(event.relative)
		get_tree().set_input_as_handled()
	
	# Forward mouse clicks to viewport input bridge.
	elif event is InputEventMouseButton:
		if _viewport_input and _viewport_input.has_method("process_mouse_click"):
			var use_system_mouse = Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
			if use_system_mouse and _viewport_input.has_method("process_system_mouse_button"):
				_viewport_input.process_system_mouse_button(event.button_index, event.pressed, event.doubleclick, event.position, event.global_position, get_viewport().size)
			else:
				_viewport_input.process_mouse_click(event.button_index, event.pressed, event.doubleclick)
			get_tree().set_input_as_handled()
			return
		if event.button_index == BUTTON_LEFT and event.pressed and _terminal_ui and _terminal_ui.has_method("process_mouse_click"):
			_terminal_ui.process_mouse_click()
			get_tree().set_input_as_handled()


func _enter_focus_mode():
	"""Switch to FocusedRig camera for close-up terminal interaction."""
	if _is_focused:
		return

	if attach_to_active_camera:
		_is_focused = true
		_set_player_input_blocked(true)
		_update_ui_mode()
		return

	if not _focused_rig:
		print("[HoloTerminalV2] Cannot enter focus mode: FocusedRig not found")
		return
	
	_is_focused = true
	_set_player_input_blocked(true)
	print("[HoloTerminalV2] Entering focus mode, activating FocusedRig")
	_request_focus_camera_rig(_focused_rig)
	
	# Ensure UI state is updated (showing cursor, etc)
	_update_ui_mode()


func _exit_focus_mode():
	"""Return to CinematicPathRig camera or regular player camera."""
	if not _is_focused:
		return

	if attach_to_active_camera:
		_is_focused = false
		_set_player_input_blocked(false)
		_update_ui_mode()
		return

	_is_focused = false
	_set_player_input_blocked(false)
	_release_focus_camera_request()
	
	if not use_cinematic_zone:
		print("[HoloTerminalV2] Exiting focus mode, returning to regular camera")
		if _camera_zone and "is_zone_active" in _camera_zone:
			_camera_zone.is_zone_active = false
		return

	print("[HoloTerminalV2] Exiting focus mode, returning to zone rig")
	
	# Ensure UI state is updated (hiding cursor if zone is disabled, etc)
	_update_ui_mode()


func is_focused() -> bool:
	"""Returns true if terminal is in focus mode."""
	return _is_focused

func _set_player_input_blocked(blocked: bool) -> void:
	var player = _find_player()
	if player == null:
		return
	if blocked:
		if _locked_player and is_instance_valid(_locked_player):
			return
		_locked_player = player
		if "input_provider" in player and player.input_provider:
			_prev_hardware_input_enabled = bool(player.input_provider.hardware_input_enabled)
			player.input_provider.hardware_input_enabled = false
		else:
			_prev_hardware_input_enabled = true
		if player.has_method("set_camera_input_locked"):
			player.call("set_camera_input_locked", true)
	elif _locked_player and is_instance_valid(_locked_player):
		if _locked_player.has_method("set_camera_input_locked"):
			_locked_player.call("set_camera_input_locked", false)
		if "input_provider" in _locked_player and _locked_player.input_provider:
			_locked_player.input_provider.hardware_input_enabled = _prev_hardware_input_enabled
		_locked_player = null

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _request_focus_camera_rig(rig: Node) -> void:
	_release_focus_camera_request()
	if rig == null or not is_instance_valid(rig):
		return
	var transition_time := 0.0
	if "transition_time" in rig:
		transition_time = float(rig.transition_time)
	var payload = {
		"rig": rig,
		"transition_time": transition_time,
		# Keep player movement stable while entering/exiting terminal focus.
		"latch_on_enter": true,
		"latch_on_exit": true,
	}
	_focus_camera_request_id = CinematicManager.request_camera_mode(
		CinematicManager.ControlMode.LOCKED_VIEW,
		payload,
		"terminal_focus_" + name,
		12
	)

func _release_focus_camera_request() -> void:
	if _focus_camera_request_id == -1:
		return
	CinematicManager.release_camera_request(_focus_camera_request_id)
	_focus_camera_request_id = -1

func _bind_console_events() -> void:
	var root = get_tree().root
	if root == null:
		return
	_console = root.get_node_or_null("OYS_Console")
	if _console == null:
		_console = OYSConsoleScript.new()
		_console.name = "OYS_Console"
		root.call_deferred("add_child", _console)
		call_deferred("_bind_console_events")
		return
	if _console and not _console.is_connected("quit_requested", self , "_on_console_quit_requested"):
		_console.connect("quit_requested", self , "_on_console_quit_requested")

func _on_console_quit_requested() -> void:
	if _is_focused:
		_exit_focus_mode()
	set_active(false)

func _exit_tree() -> void:
	_release_focus_camera_request()


func _physics_process(delta: float) -> void:
	._physics_process(delta)

	if _hud_transition_active:
		_step_hud_transition(delta)

	if not attach_to_active_camera or not is_active or _hud_attachment_suspended:
		return
	if hud_auto_close_out_of_range and not _is_player_within_hud_radius():
		set_active(false)
		return
	_sync_hud_attachment()
	_update_hud_particle_flow()


func _sync_hud_attachment() -> void:
	var active_camera = _resolve_active_camera()
	if not active_camera:
		if not _hud_warned_missing_camera:
			print("[HoloTerminalV2] HUD mode active but no camera was found.")
			_hud_warned_missing_camera = true
		return

	_hud_warned_missing_camera = false
	if active_camera != _hud_anchor_camera or not _hud_attached:
		_attach_to_camera(active_camera)
	elif not hud_attach_as_child:
		_apply_hud_world_transform(active_camera)


func _attach_hud_to_active_camera() -> void:
	var active_camera = _resolve_active_camera()
	if not active_camera:
		if not _hud_warned_missing_camera:
			print("[HoloTerminalV2] Could not attach HUD: active camera not found.")
			_hud_warned_missing_camera = true
		return
	_hud_warned_missing_camera = false
	_attach_to_camera(active_camera, true)


func _attach_to_camera(active_camera: Camera, animate := false) -> void:
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return
	var world_before = attach_target.global_transform

	if not _hud_attached:
		_hud_original_parent = attach_target.get_parent()
		_hud_original_owner = attach_target.owner
		_hud_original_global_transform = attach_target.global_transform
		if _hud_original_parent and _hud_original_parent is Spatial:
			_hud_original_parent_is_spatial = true
			_hud_original_local_transform = attach_target.transform
		else:
			_hud_original_parent_is_spatial = false
		_hud_attached = true

	_hud_anchor_camera = active_camera
	_reset_hud_particles()
	if hud_attach_as_child:
		var parent = attach_target.get_parent()
		if parent != active_camera:
			if parent:
				parent.remove_child(attach_target)
			active_camera.add_child(attach_target)
			attach_target.owner = null
		var target_local = _build_hud_target_local_transform(active_camera)
		if animate and hud_attach_transition_time > 0.0:
			var start_local = active_camera.global_transform.affine_inverse() * world_before
			_hud_transition_from_origin = start_local.origin
			_hud_transition_to_origin = target_local.origin
			_hud_transition_target_basis = target_local.basis.orthonormalized()
			_hud_transition_t = 0.0
			_hud_transition_active = true
			attach_target.transform.basis = _hud_transition_target_basis
			attach_target.transform.origin = _hud_transition_from_origin
		else:
			_hud_transition_active = false
			attach_target.transform = target_local
	else:
		_hud_transition_active = false
		_apply_hud_world_transform(active_camera)


func _detach_hud_from_camera() -> void:
	if not _hud_attached:
		return

	_reset_hud_particles()
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return

	var original_parent = _hud_original_parent
	if original_parent and is_instance_valid(original_parent):
		var parent = attach_target.get_parent()
		if parent:
			parent.remove_child(attach_target)
		original_parent.add_child(attach_target)
		attach_target.owner = _hud_original_owner
		if _hud_original_parent_is_spatial:
			attach_target.transform = _hud_original_local_transform
		else:
			attach_target.global_transform = _hud_original_global_transform

	_hud_anchor_camera = null
	_hud_attached = false
	_hud_transition_active = false
	_hud_transition_t = 0.0
	_hud_original_parent = null
	_hud_original_owner = null
	_hud_original_global_transform = Transform.IDENTITY
	_hud_original_local_transform = Transform.IDENTITY
	_hud_original_parent_is_spatial = false


func _resolve_active_camera() -> Camera:
	var viewport = get_viewport()
	if viewport:
		var viewport_camera = viewport.get_camera()
		if viewport_camera:
			return viewport_camera

	var player = _find_player()
	if player:
		var player_camera = player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera")
		if player_camera and player_camera is Camera:
			return player_camera as Camera

	var scene_root = get_tree().current_scene if get_tree() else null
	if scene_root:
		var current_camera = _find_current_camera_recursive(scene_root)
		if current_camera:
			return current_camera

	return null


func _find_current_camera_recursive(node: Node) -> Camera:
	if node is Camera and (node as Camera).current:
		return node as Camera
	for child in node.get_children():
		var current_camera = _find_current_camera_recursive(child)
		if current_camera:
			return current_camera
	return null


func _build_hud_reference_local_transform(active_camera: Camera) -> Transform:
	var depth_t = clamp(hud_screen_depth, 0.0, 1.0)
	var fov_deg = 70.0
	var aspect = 16.0 / 9.0
	var near_plane = 0.05
	if active_camera:
		fov_deg = active_camera.fov
		near_plane = active_camera.near
		var view = active_camera.get_viewport()
		if view and view.size.y > 0.0:
			aspect = view.size.x / view.size.y
	# Keep relative controls 0..1 while preventing near-plane clipping.
	var min_distance = max(0.07, near_plane + 0.03)
	var max_distance = max(min_distance + 0.01, 0.55)
	var distance = lerp(min_distance, max_distance, depth_t)
	var half_height = tan(deg2rad(fov_deg) * 0.5) * distance
	var half_width = half_height * aspect
	var local_x = lerp(-half_width, half_width, clamp(hud_screen_x, 0.0, 1.0))
	var local_y = lerp(half_height, -half_height, clamp(hud_screen_y, 0.0, 1.0))
	var local_z = -distance
	var scale_t = clamp(hud_screen_scale, 0.0, 1.0)
	# 0..1 maps to tiny->large while keeping sane mid values in gameplay.
	var scale_factor = lerp(0.08, 2.4, scale_t)

	var basis = Basis.IDENTITY
	basis = basis.rotated(Vector3.RIGHT, deg2rad(hud_local_rotation_deg.x))
	basis = basis.rotated(Vector3.UP, deg2rad(hud_local_rotation_deg.y))
	basis = basis.rotated(Vector3.BACK, deg2rad(hud_local_rotation_deg.z))
	basis = basis.scaled(Vector3.ONE * scale_factor)
	return Transform(basis, Vector3(local_x, local_y, local_z) + hud_local_offset)


func _build_hud_target_local_transform(active_camera: Camera) -> Transform:
	return _build_hud_reference_local_transform(active_camera)


func _get_hud_attach_target() -> Spatial:
	if _hud_attach_target and is_instance_valid(_hud_attach_target):
		return _hud_attach_target
	return null


func _apply_hud_world_transform(active_camera: Camera) -> void:
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		return
	var target_local = _build_hud_target_local_transform(active_camera)
	attach_target.global_transform = active_camera.global_transform * target_local


func set_hud_attachment_suspended(suspended: bool) -> void:
	_hud_attachment_suspended = suspended
	if suspended:
		_hud_transition_active = false
		_hud_transition_t = 0.0


func _step_hud_transition(delta: float) -> void:
	if not hud_attach_as_child:
		_hud_transition_active = false
		return
	var attach_target = _get_hud_attach_target()
	if attach_target == null:
		_hud_transition_active = false
		return
	if hud_attach_transition_time <= 0.0:
		_hud_transition_active = false
		return

	_hud_transition_t = min(1.0, _hud_transition_t + (delta / hud_attach_transition_time))
	var eased_t = _ease_out_cubic(_hud_transition_t)
	attach_target.transform.basis = _hud_transition_target_basis
	attach_target.transform.origin = _hud_transition_from_origin.linear_interpolate(_hud_transition_to_origin, eased_t)
	if _hud_transition_t >= 1.0:
		_hud_transition_active = false


func _is_player_within_hud_radius() -> bool:
	if hud_interaction_radius <= 0.0:
		return true
	var player = _find_player()
	if player == null:
		return true
	if not (player is Spatial):
		return true
	var dist = global_transform.origin.distance_to((player as Spatial).global_transform.origin)
	return dist <= hud_interaction_radius


func _update_hud_particle_flow() -> void:
	var particles = get_node_or_null("HoloParticles")
	var target = _get_hud_attach_target()
	if not particles or not target or not particles.emitting:
		return
	particles.local_coords = false
	var from = particles.global_transform.origin
	var to = target.global_transform.origin
	var flow_dir = (to - from)
	if flow_dir.length_squared() < 0.0001:
		return
	var dist = flow_dir.length()
	var flow_normal = flow_dir / dist
	# Force a deterministic narrow beam and kill particles before they cross the HUD plane.
	particles.randomness = 0.0
	particles.lifetime_randomness = 0.0
	particles.initial_velocity_random = 0.0
	particles.spread = 0.0
	particles.radial_accel = 0.0
	particles.gravity = Vector3.ZERO
	if _hud_last_particle_dir.length_squared() > 0.0 and _hud_last_particle_dir.dot(flow_normal) < 0.99:
		# Reset on fast camera angle changes so new particles always point to HUD.
		if particles.has_method("restart"):
			particles.restart()
	_hud_last_particle_dir = flow_normal
	particles.direction = flow_normal
	var stop_distance = max(0.02, dist - 0.16)
	var speed = clamp(stop_distance * 12.0, 1.2, 14.0)
	particles.initial_velocity = speed
	particles.lifetime = clamp(stop_distance / speed, 0.03, 0.10)


func _reset_hud_particles() -> void:
	var particles = get_node_or_null("HoloParticles")
	if not particles:
		return
	_hud_last_particle_dir = Vector3.ZERO
	var was_emitting = particles.emitting
	particles.emitting = false
	if particles.has_method("restart"):
		particles.restart()
	particles.emitting = was_emitting


func get_capture_nodes() -> Array:
	var nodes := []
	var target = _get_hud_attach_target()
	if attach_to_active_camera and target and is_instance_valid(target) and target != self and target.get_parent() != self:
		nodes.append(target)
	return nodes
