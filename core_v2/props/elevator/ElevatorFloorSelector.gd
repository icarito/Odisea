tool
extends InteractableBaseV2
class_name ElevatorFloorSelector

# ElevatorFloorSelector.gd
# Cabin control for ElevatorController: a holographic radial dial that names every
# stop, replacing the internal call button (which could only ever say "next floor"
# and forced the rider to cycle through the whole shaft).
#
# It projects a Viewport onto a holo quad the same way HoloTerminalV2 does, but it
# deliberately does NOT reuse the terminal's focus machinery:
#
#   - No cinematic rig. The camera does not move, cut or reorient when the dial
#     opens (AGENTS 1.1). A terminal FocusedRig would also be wrong here: the rig
#     restores a global design transform captured at _ready, so on a car that has
#     since travelled up the shaft the camera would snap back to the ground floor.
#   - No mouse cursor and no input handover. The mouse stays captured and the
#     camera keeps turning; _track_aim() projects wherever it ends up onto the
#     projection plane, so the rider picks a floor by looking at it. Looking
#     anywhere near the projection always focuses some stop — there are no holes
#     to sweep across — while looking away focuses nothing at all, which is what
#     lets a stray press be ignored instead of grabbing the nearest stop.
#
# The dial itself is RadialSelectorV2 (see core_v2/ui/radial/).

# "interact" confirms through interact(), not here: the player controller already
# routes that action to us, and handling it twice would pick twice. The left mouse
# button is handled as a raw event rather than an action, because the only click
# action in the project ("cursor_click_primary") is bound to a gamepad face button
# and never to the mouse.
const CONFIRM_ACTIONS := ["ui_accept", "cursor_click_primary"]
# Every key that can confirm, including the one that opens. Used only to decide
# when confirming is armed.
const ARMING_ACTIONS := ["ui_accept", "interact", "cursor_click_primary"]
# Sentinel for "the aim is not on the projection at all".
const NO_AIM := Vector2(INF, INF)

# The elevator this panel drives. Default assumes Platform/ThisPanel.
export(NodePath) var elevator_path = NodePath("../..")
# Optional display names, one per stop, bottom-up. Empty falls back to numbering
# the elevator's own stops from 1.
export(PoolStringArray) var floor_labels = PoolStringArray()
export(String) var floor_label_prefix := ""
export(float) var open_speed := 4.0
# How far the projection rises while it fades in.
export(float) var slide_height := 0.25
export(Vector2) var screen_resolution := Vector2(1024, 1024)
# Distance past which the Viewport stops redrawing.
export(float) var render_distance := 14.0
# Walking further than this closes an open dial. Keep it clear of the interaction
# range, or an auto_interact panel closes and re-triggers on the same step.
export(float) var close_distance := 5.0
# How far off screen the projection may drift and still count as being looked at,
# as a fraction of the screen. Raise it to keep the dial live over a wider turn.
export(float) var aim_margin := 0.45
# Spring arm length forced while the rider is in the car, so the camera comes
# inside with them instead of framing the cabin from outside the shaft. Whatever
# length they had is handed back on the way out. 0 disables it.
export(float) var cabin_zoom_spring_length := 0.9
# Volume that counts as "in the car", so the framing holds for the whole ride
# rather than only while standing at the panel. The elevator owns it: the
# passenger area would have been the obvious reuse, but it feeds
# set_external_velocity and layer 2 carries more than the player actors, so
# widening its mask reaches well past a camera concern. Falls back to this prop's
# own interaction area when the panel is used outside an elevator.
export(NodePath) var cabin_zone_path = NodePath("../CabinZone")

var _selector: Control = null
var _viewport: Viewport = null
var _elevator: Node = null
var _screen_container: Spatial = null
var _particles: CPUParticles = null
var _is_open := false
var _confirm_armed := false
var _current_floor := 0
var _announced_floor := -1
var _zoomed_player: Node = null
var _restore_spring_length := -1.0


func _ready() -> void:
	interaction_text = "Seleccionar nivel"
	# Cached before the base _ready, which calls _update_visuals() straight away.
	_viewport = get_node_or_null("Viewport") as Viewport
	_screen_container = get_node_or_null("ScreenContainer") as Spatial
	_particles = get_node_or_null("ProjectorMesh/HoloParticles") as CPUParticles
	_selector = get_node_or_null("Viewport/RadialSelector") as Control
	anim_duration = 1.0 / max(0.1, open_speed)
	if _viewport and screen_resolution.x > 0 and screen_resolution.y > 0:
		_viewport.size = screen_resolution
	_setup_viewport_texture()
	._ready()

	if Engine.editor_hint:
		return

	_elevator = get_node_or_null(elevator_path)
	if _elevator == null:
		push_warning("ElevatorFloorSelector: no elevator at '%s'" % [elevator_path])
	elif _elevator.has_signal("floor_state_changed"):
		if not _elevator.is_connected("floor_state_changed", self, "_on_floor_state_changed"):
			_elevator.connect("floor_state_changed", self, "_on_floor_state_changed")

	if _selector:
		if not _selector.is_connected("option_selected", self, "_on_option_selected"):
			_selector.connect("option_selected", self, "_on_option_selected")
		if not _selector.is_connected("cancelled", self, "_on_selector_cancelled"):
			_selector.connect("cancelled", self, "_on_selector_cancelled")
		if not _selector.is_connected("option_hovered", self, "_on_option_hovered"):
			_selector.connect("option_hovered", self, "_on_option_hovered")
	_wire_cabin_zoom()
	call_deferred("_rebuild_options")
	set_process_input(false)
	set_process(false)


# --- Interaction ---

func interact() -> void:
	if not is_interactable:
		return
	if not _is_open:
		set_active(true)
	elif _confirm_armed and _selector:
		# Second tap of the same key picks whatever the look is pointing at.
		_selector.confirm()


func set_active(value: bool, immediate: bool = false) -> void:
	.set_active(value, immediate)
	# auto_interact never calls interact(): the player controller flips set_active()
	# directly when the prop comes into range. Driving the dial from here is what
	# makes the projection actually appear on entering the car, instead of only the
	# empty quad growing until the rider pressed the key a second time.
	if value:
		_begin_dial()
	else:
		_end_dial()


func get_interaction_prompt() -> String:
	if not _is_open:
		return "[F] %s" % [interaction_text]
	if auto_interact:
		# An ambient panel has nothing to cancel: it is up for the whole ride.
		return "[F] o click: confirmar nivel"
	return "[F] o click: confirmar / [ESC] cancelar"


func is_dial_open() -> bool:
	return _is_open


# Both of these are reached only through set_active(), so opening by hand and
# opening by proximity take the exact same path. "SFX Open" is a OneShotActive
# SFXComponentV2 and rides the activated signal, so there is nothing to play here.

func _begin_dial() -> void:
	if _is_open or _selector == null:
		return
	_is_open = true
	# The press that opened the dial must not also confirm it; wait for the player
	# to let go first.
	_confirm_armed = false
	_rebuild_options()
	# Opens with nothing selected on purpose: the rider has to aim at a stop.
	_selector.open()
	set_process_input(true)
	set_process(true)


func _end_dial() -> void:
	if not _is_open:
		return
	_is_open = false
	if _selector:
		_selector.close()
	set_process_input(false)
	set_process(false)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	# The press that opened the dial is usually still held. Confirming only arms
	# once every confirm key is up, so one tap can never open and pick at once —
	# whichever key the player then uses works, not only the one they opened with.
	if not _confirm_armed and not _any_confirm_held():
		_confirm_armed = true

	_track_aim()
	_track_level()

	# The camera is never taken away, so the player can walk off mid-selection.
	var player := _find_player()
	if player and player is Spatial:
		if global_transform.origin.distance_to(player.global_transform.origin) > close_distance:
			set_active(false)


func _track_level() -> void:
	"""Drive the needle from the car's real height, and tick the hub readout over
	as it passes each stop."""
	if _selector == null or _elevator == null:
		return
	if not _elevator.has_method("get_exact_floor"):
		return
	var level: float = _elevator.get_exact_floor()
	_selector.set_level(level)

	var nearest: int = int(round(level))
	if nearest == _announced_floor:
		return
	var labels := _resolve_labels()
	if nearest < 0 or nearest >= labels.size():
		return
	if _announced_floor < 0:
		_selector.set_readout_text(String(labels[nearest]))
	else:
		_selector.announce_readout_text(String(labels[nearest]), 1 if nearest > _announced_floor else -1)
	_announced_floor = nearest


func _track_aim() -> void:
	"""Point the dial wherever the camera is looking, or at nothing."""
	if _selector == null:
		return
	var aim := _aim_in_viewport()
	if aim == NO_AIM:
		_selector.clear_pointer()
	else:
		_selector.point_at(aim)


func _aim_in_viewport() -> Vector2:
	"""Which way the player is looking relative to the projection, as pixels in the
	dial's own Viewport. Returns NO_AIM when the projection is not on screen.

	This is a heading, not a crosshair. Casting the camera ray onto the quad and
	using the hit point made the dial behave like a rifle sight: zooming in blows
	the projection up across the screen, so the same small turn of the head swings
	the hit right across the stops, and picking the top floor meant craning off to
	one side. Here only the direction from the middle of the view to the
	projection is used. Direction is invariant under zoom and field of view — they
	change how far the offset reaches, never where it points — so a stop sits in
	the same direction however close the camera is.

	The sentinel has to be unreachable rather than merely off-screen: the heading
	is free to land outside the dial's rect, so anything like (-1, -1) would read
	as a miss on the left-hand side only."""
	var miss := NO_AIM
	var screen_mesh := get_node_or_null("ScreenContainer/ScreenMesh") as MeshInstance
	var scene_viewport := get_viewport()
	if screen_mesh == null or _viewport == null or scene_viewport == null:
		return miss
	var camera := scene_viewport.get_camera()
	if camera == null:
		return miss

	var projection_origin := screen_mesh.global_transform.origin
	if camera.is_position_behind(projection_origin):
		return miss # Turned away from the panel entirely.

	var view_size: Vector2 = scene_viewport.size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return miss
	var projection_on_screen: Vector2 = camera.unproject_position(projection_origin)
	# Off the screen by more than the margin means the rider is looking elsewhere.
	var slack := view_size * aim_margin
	if projection_on_screen.x < -slack.x or projection_on_screen.x > view_size.x + slack.x:
		return miss
	if projection_on_screen.y < -slack.y or projection_on_screen.y > view_size.y + slack.y:
		return miss

	# From where the camera is pointing towards the projection, in screen pixels.
	# Normalised by half the shorter screen side so the feel does not change with
	# resolution, then re-expressed against the dial's own radius. Only the angle
	# of this vector is read; its length just has to clear the dial's hub so that
	# looking straight at the panel still counts as no heading.
	var heading := (view_size * 0.5 - projection_on_screen) / (min(view_size.x, view_size.y) * 0.5)
	return _viewport.size * 0.5 + heading * (min(_viewport.size.x, _viewport.size.y) * 0.5)


func _any_confirm_held() -> bool:
	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		return true
	for action in ARMING_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _is_open or _selector == null:
		return

	if event.is_action_pressed("ui_cancel"):
		_selector.cancel()
		get_tree().set_input_as_handled()
		return

	if _confirm_armed:
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
			_selector.confirm()
			get_tree().set_input_as_handled()
			return
		for action in CONFIRM_ACTIONS:
			if event.is_action_pressed(action):
				_selector.confirm()
				get_tree().set_input_as_handled()
				return

	# Look events are deliberately not touched here. The camera keeps turning on
	# its own and _track_aim() reads where it ends up, so the dial follows the aim
	# instead of a cursor, and a press with the aim off the dial does nothing.


# --- Elevator wiring ---

func _rebuild_options() -> void:
	if _selector == null:
		return
	var labels := _resolve_labels()
	if labels.empty():
		return
	if _elevator and _elevator.has_method("get_current_floor"):
		_current_floor = int(clamp(_elevator.get_current_floor(), 0, labels.size() - 1))
	_selector.set_options(labels)
	# Reset so the first _track_level() seeds the readout without an animation.
	_announced_floor = -1
	_selector.set_readout_text(String(labels[_current_floor]))
	_selector.set_status(_describe_state(_current_floor, _current_floor, false))


func _resolve_labels() -> Array:
	if floor_labels.size() > 0:
		return Array(floor_labels)
	var count := 0
	if _elevator and _elevator.has_method("get_floor_count"):
		count = int(_elevator.get_floor_count())
	if count <= 0:
		return []
	# Stops are named the way a rider counts them, from 1 up.
	var labels := []
	for i in range(count):
		labels.append("%s%d" % [floor_label_prefix, i + 1])
	return labels


func _on_option_selected(index: int) -> void:
	if _elevator and _elevator.has_method("request_floor"):
		_elevator.request_floor(index)
	_play_sfx("SFX Select")
	# The aim has not moved, so without this the stop just chosen lights straight
	# back up. The hub goes back to reading the car's own level until the rider
	# looks away or the car arrives.
	if _selector:
		_selector.suppress_focus()
	_dismiss()


func _on_option_hovered(_index: int) -> void:
	_play_sfx("SFX Hover")


func _on_selector_cancelled() -> void:
	_dismiss()


func _dismiss() -> void:
	# An auto_interact panel is ambient: it belongs to the car, not to a keypress,
	# so it stays up for the whole ride. Closing it here would only flicker — the
	# controller re-triggers auto_interact the moment is_active goes false. Rearm
	# instead, so a held key or click cannot fire twice.
	if auto_interact:
		_confirm_armed = false
		return
	set_active(false)


func _on_floor_state_changed(current_floor: int, target_floor: int, is_moving: bool) -> void:
	if current_floor >= 0:
		_current_floor = current_floor
	if _selector == null:
		return
	_selector.set_status(_describe_state(current_floor, target_floor, is_moving))
	# The hub readout is driven by _track_level(), which follows the car's real
	# height rather than waiting for arrival.
	if not is_moving:
		_selector.resume_focus()


func _describe_state(current_floor: int, target_floor: int, is_moving: bool) -> String:
	var labels := _resolve_labels()
	if not is_moving:
		if current_floor < 0 or current_floor >= labels.size():
			return "EN TRANSITO"
		return "EN %s" % [labels[current_floor]]
	if target_floor < 0 or target_floor >= labels.size():
		return "EN MOVIMIENTO"
	var direction: String = "SUBIENDO" if target_floor > current_floor else "BAJANDO"
	return "%s A %s" % [direction, labels[target_floor]]


# --- Cabin zoom ---
#
# Same handover AirlockZoneV2 uses for its tight framing, and for the same
# reason: a 5.5 m spring arm inside a 3.6 m car puts the camera out in the shaft,
# behind the fence. Only base_spring_length_3d is written, never the arm itself,
# so PlayerControllerV2 lerps in and out and the camera never cuts (AGENTS 1.1).

func _wire_cabin_zoom() -> void:
	if cabin_zoom_spring_length <= 0.0:
		return
	var zone := get_node_or_null(cabin_zone_path) as Area
	if zone == null:
		zone = get_node_or_null("InteractableEntity") as Area
	if zone == null:
		return
	if not zone.is_connected("body_entered", self, "_on_cabin_body_entered"):
		zone.connect("body_entered", self, "_on_cabin_body_entered")
	if not zone.is_connected("body_exited", self, "_on_cabin_body_exited"):
		zone.connect("body_exited", self, "_on_cabin_body_exited")


func _on_cabin_body_entered(body: Node) -> void:
	if _zoomed_player != null or not _is_player(body):
		return
	var current = body.get("base_spring_length_3d")
	if current == null:
		return
	_zoomed_player = body
	_restore_spring_length = float(current)
	body.set("base_spring_length_3d", cabin_zoom_spring_length)


func _on_cabin_body_exited(body: Node) -> void:
	if body != _zoomed_player:
		return
	_release_cabin_zoom()


func _release_cabin_zoom() -> void:
	if _zoomed_player == null:
		return
	if is_instance_valid(_zoomed_player) and _restore_spring_length > 0.0:
		_zoomed_player.set("base_spring_length_3d", _restore_spring_length)
	_zoomed_player = null
	_restore_spring_length = -1.0


func _is_player(body: Node) -> bool:
	return is_instance_valid(body) and body.is_in_group("player")


func _exit_tree() -> void:
	# Leaving the scene mid-ride must not strand the camera inside the car.
	_release_cabin_zoom()


# --- Player ---
#
# Note there is no input handover here, unlike HoloTerminalV2. That terminal takes
# the player's input provider away and locks the camera while its cursor is up.
# This dial deliberately leaves both alone: the mouse stays captured, the camera
# keeps turning, and the dial reads the same motion. Nothing to hand back, and
# nothing to leak if the scene changes mid-selection.

func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null


# --- Visuals ---

func _setup_viewport_texture() -> void:
	# A ViewportTexture saved in a .tscn cannot resolve its own path reliably, so
	# the binding is made here (same reason HoloTerminalV2 does it in code).
	var screen_mesh = get_node_or_null("ScreenContainer/ScreenMesh")
	if screen_mesh == null or _viewport == null:
		return
	var mat = null
	if screen_mesh is MeshInstance:
		mat = (screen_mesh as MeshInstance).get_surface_material(0)
		if mat == null:
			mat = (screen_mesh as MeshInstance).material_override
	else:
		mat = screen_mesh.get("material")
	if mat is ShaderMaterial:
		mat.set_shader_param("texture_albedo", _viewport.get_texture())


func _update_visuals() -> void:
	var progress: float = 1.0 - pow(1.0 - anim_progress, 3.0)

	if _screen_container:
		_screen_container.translation.y = lerp(-slide_height, 0.0, progress)
		_screen_container.scale = lerp(Vector3.ZERO, Vector3.ONE, progress)
		_screen_container.visible = progress > 0.01

	if _particles:
		_particles.emitting = is_active

	if _viewport:
		# WHEN_VISIBLE rather than ALWAYS even while open: an auto_interact panel is
		# up for the whole ride, and ALWAYS would keep redrawing a 1024² target with
		# the projection off screen behind the rider.
		var mode: int = Viewport.UPDATE_DISABLED
		if progress > 0.0:
			mode = Viewport.UPDATE_WHEN_VISIBLE
			var player := _find_player()
			if player and player is Spatial:
				var dist: float = global_transform.origin.distance_to(player.global_transform.origin)
				if dist > render_distance:
					mode = Viewport.UPDATE_DISABLED
		if _viewport.render_target_update_mode != mode:
			_viewport.render_target_update_mode = mode


func _play_sfx(node_name: String) -> void:
	if Engine.editor_hint:
		return
	var sfx = get_node_or_null(node_name)
	if sfx == null:
		return
	if sfx.has_method("play_sfx"):
		sfx.play_sfx()
	elif sfx is AudioStreamPlayer3D:
		(sfx as AudioStreamPlayer3D).play()
