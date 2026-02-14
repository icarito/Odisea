tool
extends InteractableBaseV2
class_name HoloTerminalV2

# HoloTerminalV2.gd - Interactive Holographic Screen
# Inherits InteractableBaseV2 for replay determinism.
# V2.2: Integrated local Cinematic Camera System

const DebugOverlayScene = preload("res://core_v2/ui/retro/DebugOverlay.tscn")

# --- Terminal Configuration ---
export(float) var slide_speed := 2.0
export(float) var slide_height := 0.8
export(Vector2) var screen_resolution := Vector2(800, 600)
export(int, 12, 48) var debug_overlay_font_size := 22
export(bool) var active setget set_active_debug

# --- Cinematic Camera Configuration ---
export(bool) var use_cinematic_zone := true
export(bool) var close_on_exit_zone := true
export(bool) var enable_ui_interaction := true
export(bool) var allow_focus_mode := true # If true, pressing 'focus' key transitions to FocusedRig

# --- Internal Camera References ---
var _camera_zone: Area = null
var _cinematic_rig = null # CinematicPathRig reference
var _focused_rig = null # FocusedRig reference for focus mode
var _terminal_ui = null # TerminalUIV2 reference
var _viewport_input = null # Viewport input bridge
var _player_in_zone := false
var _is_focused := false # True when in focus mode (close-up camera, keyboard to UI)

func _ready():
	interaction_text = "Toggle Terminal"

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
	
	_viewport_input = get_node_or_null("Viewport")
	# Cache TerminalUI reference
	_terminal_ui = get_node_or_null("Viewport/TerminalUI")
	if _terminal_ui and not _terminal_ui.is_connected("debug_button_pressed", self, "_on_terminal_debug_requested"):
		_terminal_ui.connect("debug_button_pressed", self, "_on_terminal_debug_requested")


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


func interact() -> void:
	# If auto-interact is on, we don't toggle the terminal open/closed.
	# Instead, 'interact' focuses the terminal directly if it's already active.
	if auto_interact:
		if is_active and not _is_focused and allow_focus_mode:
			_enter_focus_mode()
		return

	# Toggle open/close (Standard behavior)
	if is_active:
		set_active(false)
	else:
		set_active(true)
		
		# If cinematic zone is disabled, go straight to focus mode
		if not use_cinematic_zone and allow_focus_mode:
			_enter_focus_mode()


# Override set_active to manage cinematic camera on state changes
func set_active(value: bool, immediate: bool = false) -> void:
	# Call base implementation
	.set_active(value, immediate)
	
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
	# 2. Apply Movement (Visuals)
	var screen_container = get_node_or_null("ScreenContainer")
	if screen_container:
		var progress = _ease_out_cubic(anim_progress)
		
		# Slide + Scale animation:
		var start_y = -1.2
		var end_y = 0.0
		var new_y = lerp(start_y, end_y, progress)
		var new_scale = lerp(Vector3.ZERO, Vector3.ONE, progress)
		
		screen_container.translation.y = new_y
		screen_container.scale = new_scale
		screen_container.visible = new_scale.length_squared() > 0.001
				
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
	var base_interactive = is_active and enable_ui_interaction and (_player_in_zone or _is_focused)
	if not use_cinematic_zone:
		return base_interactive and _is_focused
	return base_interactive


func _input(event):
	"""Handle focus mode toggling and forward input to viewport-driven UI."""
	if Engine.editor_hint:
		return
	
	# Handle focus mode toggle
	if is_ui_interactive() and allow_focus_mode:
		if event.is_action_pressed("focus") and not _is_focused:
			print("[HoloTerminalV2] Focus key pressed, entering focus mode")
			_enter_focus_mode()
			get_tree().set_input_as_handled()
			return
		elif event.is_action_pressed("ui_cancel") and _is_focused:
			print("[HoloTerminalV2] Cancel key pressed, exiting focus mode")
			_exit_focus_mode()
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
			_viewport_input.process_mouse_motion(event.relative)
			get_tree().set_input_as_handled()
			return
		if _terminal_ui and _terminal_ui.has_method("process_mouse_motion"):
			_terminal_ui.process_mouse_motion(event.relative)
		get_tree().set_input_as_handled()
	
	# Forward mouse clicks to viewport input bridge.
	elif event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if _viewport_input and _viewport_input.has_method("process_mouse_click"):
				_viewport_input.process_mouse_click(event.button_index, event.pressed)
				get_tree().set_input_as_handled()
				return
			if event.pressed and _terminal_ui and _terminal_ui.has_method("process_mouse_click"):
				_terminal_ui.process_mouse_click()
				get_tree().set_input_as_handled()


func _enter_focus_mode():
	"""Switch to FocusedRig camera for close-up terminal interaction."""
	if not _focused_rig:
		print("[HoloTerminalV2] Cannot enter focus mode: FocusedRig not found")
		return
	
	_is_focused = true
	print("[HoloTerminalV2] Entering focus mode, activating FocusedRig")
	
	# Switch camera zone to point at FocusedRig
	if _camera_zone and "cinematic_rig_path" in _camera_zone:
		_camera_zone.cinematic_rig_path = _camera_zone.get_path_to(_focused_rig)
		_camera_zone._cache_rig()
		
		# If cinematic zone was disabled, we enable it now to "own" the focus rig
		# if not use_cinematic_zone and "is_zone_active" in _camera_zone:
		# 	_camera_zone.is_zone_active = true
	
	# Activate the focused rig via CinematicManager
	CinematicManager.activate_rig_direct(_focused_rig, CinematicManager.ControlMode.LOCKED_VIEW)
	
	# Ensure UI state is updated (showing cursor, etc)
	_update_ui_mode()


func _exit_focus_mode():
	"""Return to CinematicPathRig camera or regular player camera."""
	_is_focused = false
	
	if not use_cinematic_zone:
		print("[HoloTerminalV2] Exiting focus mode, returning to regular camera")
		if _camera_zone and "is_zone_active" in _camera_zone:
			_camera_zone.is_zone_active = false
		CinematicManager.deactivate_rig()
		return

	if not _cinematic_rig:
		print("[HoloTerminalV2] Cannot exit focus mode: CinematicPathRig not found")
		return
	
	print("[HoloTerminalV2] Exiting focus mode, activating CinematicPathRig")
	
	# Switch camera zone back to CinematicPathRig
	if _camera_zone and "cinematic_rig_path" in _camera_zone:
		_camera_zone.cinematic_rig_path = _camera_zone.get_path_to(_cinematic_rig)
		_camera_zone._cache_rig()
	
	# Activate the path rig via CinematicManager
	CinematicManager.activate_rig_direct(_cinematic_rig, CinematicManager.ControlMode.LOCKED_VIEW)
	
	# Ensure UI state is updated (hiding cursor if zone is disabled, etc)
	_update_ui_mode()


func is_focused() -> bool:
	"""Returns true if terminal is in focus mode."""
	return _is_focused
