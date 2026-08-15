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
#     camera keeps turning; the rider picks a floor by GESTURE, not by where the
#     camera ended up pointing. The angle of the movement is the choice: push up
#     and the top stop lights, push down and the bottom one does, push right and
#     the dial lands mid-arc. Camera angle is deliberately not part of it —
#     deriving the pick from the aim made the same gesture choose different
#     floors depending on where the rider happened to be facing. The projection
#     still has to be on screen for anything to be selected, so a stray press
#     with the panel behind the rider is ignored instead of grabbing a stop.
#   - Every pointing device drives it the same way, and the last gesture wins:
#     mouse, right stick (both arrive as mouse_delta), movement stick — physical
#     or the virtual joystick — and the touch drag. Only the keyboard is left
#     out, because on desktop the mouse is the pointing device and walking
#     across the cabin must not re-pick the floor.
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
# Cuanto hay que empujar el stick de movimiento para que cuente como gesto del dial.
# Comodo (0.14 de deflexion) porque lo que importa es el angulo, no la fuerza.
const MOVE_GESTURE_DEADZONE_SQ := 0.02

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
# It only gates whether the dial is live at all; it never picks the stop.
export(float) var aim_margin := 0.45
# Touch aims by broad screen area instead of making the rider turn the camera.
# A drag only changes the highlighted floor; a short tap confirms on release.
export(float) var touch_tap_max_duration := 0.35
export(float) var touch_tap_max_distance := 24.0
# Ignore release jitter and tiny camera corrections when deriving radial intent.
export(float) var touch_aim_min_drag_distance := 12.0
# Zona muerta del gesto: pixeles de mouse en UNA muestra de input (1/60 s, el tick de
# fisica, no el frame de video) que hacen falta para que cuente como intencion.
#
# No esta para filtrar movimiento, esta para filtrar RUIDO DE ANGULO. Lo que el dial lee es
# la direccion, y a un pixel de recorrido la direccion es basura: la mano apoyada, el
# temblor y la cuantizacion del sensor alcanzan para mandar el angulo a cualquier lado, y el
# dial saltaba solo. Por debajo de esto la seleccion se sostiene; por encima, el angulo se
# aplica entero, sin escalar por la magnitud — un gesto el doble de largo es la misma
# intencion, no una distinta.
#
# Bajarlo hace el dial mas nervioso, subirlo pide un empujon mas franco. Se mide por muestra
# de fisica, o sea que el tacto no cambia con los FPS.
export(float, 0.5, 40.0) var mouse_gesture_deadzone := 3.0
# Spring arm length forced while the rider is in the car, so the camera comes
# inside with them instead of framing the cabin from outside the shaft. Whatever
# length they had is handed back on the way out. 0 disables it.
export(float) var cabin_zoom_spring_length := 0.5
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
var _touch_index := -1
var _touch_start_time := 0
var _touch_start_position := Vector2.ZERO
var _touch_can_confirm := false
var _mouse_aim_active := false
var _ignore_emulated_mouse_until := 0
# Flanco del click segun el stream grabado. La confirmacion "de verdad" vivia solo en
# _input() como InputEventMouseButton, y en reproduccion no existen eventos de hardware:
# el click quedaba sin registrar y el ascensor nunca recibia la orden. Esto lo reconstruye
# desde InputDataV2, que si se graba y reproduce.
var _stream_confirm_was_down := false


func _init() -> void:
	# El selector de piso decide a que altura viaja el ascensor, o sea que su estado ENTRA
	# en la simulacion del jugador. Estaba fuera de replay_sync, asi que un replay nunca lo
	# capturaba ni lo restauraba: la interaccion grabada con el menu radial no se reproducia,
	# el ascensor no recibia la orden y el jugador terminaba un nivel mas abajo.
	add_to_group("replay_sync")


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
	_mouse_aim_active = false
	# Opens with nothing selected on purpose: the rider has to gesture at a stop.
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

	_drive_from_stream()
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
	"""Keep the dial live only while its projection is on screen.

	The camera decides WHETHER there is anything to pick, never WHICH stop: that
	comes from the gesture (_drive_from_stream). Turning away drops the selection
	and the gesture along with it, so a press with the panel out of view cannot
	commit the floor the rider happened to have highlighted before turning."""
	if _selector == null:
		return
	if _is_projection_in_view():
		return
	_mouse_aim_active = false
	_selector.clear_pointer()


# El stick de movimiento ya no se lee por separado para touch. Vivia aca en una segunda
# implementacion que, sin proveedor de input, sondeaba Input.get_action_strength() y se
# activaba con _is_touch_device(): dos formas de resolver el mismo gesto, y la eleccion del
# piso dependia del dispositivo en el que se REPRODUCIA. Ahora sale una sola vez de
# _drive_from_stream(), sobre el move_vec grabado y su analog_move_active.


func _is_projection_in_view() -> bool:
	"""Whether the hologram is on screen at all, within aim_margin of slack.

	This used to return a heading — the direction from the middle of the view to
	the projection — and that heading picked the stop. It read as a rifle sight
	pointed by the neck: the same flick of the mouse chose a different floor
	depending on where the camera already was, and the top stop could only be
	reached by craning off to one side. The pick now comes from the gesture
	angle, which is the same wherever the rider is facing, and all that is left
	for the camera to say is whether the dial is worth driving."""
	var screen_mesh := get_node_or_null("ScreenContainer/ScreenMesh") as MeshInstance
	var scene_viewport := get_viewport()
	if screen_mesh == null or _viewport == null or scene_viewport == null:
		return false
	var camera := scene_viewport.get_camera()
	if camera == null:
		return false

	var projection_origin := screen_mesh.global_transform.origin
	if camera.is_position_behind(projection_origin):
		return false # Turned away from the panel entirely.

	var view_size: Vector2 = scene_viewport.size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return false
	var projection_on_screen: Vector2 = camera.unproject_position(projection_origin)
	# Off the screen by more than the margin means the rider is looking elsewhere.
	var slack := view_size * aim_margin
	if projection_on_screen.x < -slack.x or projection_on_screen.x > view_size.x + slack.x:
		return false
	if projection_on_screen.y < -slack.y or projection_on_screen.y > view_size.y + slack.y:
		return false
	return true


# InputDataV2 del frame, tomado del proveedor del jugador que esta usando la consola. En
# reproduccion ese proveedor entrega el input GRABADO, asi que la confirmacion se replica.
# Devuelve null cuando no hay proveedor (editor, o nadie en la cabina).
func _frame_input():
	var body: Node = _zoomed_player
	if not is_instance_valid(body):
		var sm = get_node_or_null("/root/SessionManager")
		if sm != null:
			body = sm.player
	if not is_instance_valid(body):
		return null
	if not ("input_provider" in body) or not is_instance_valid(body.input_provider):
		return null
	# peek_input(), NO get_input(): este ultimo avanza playback_index, asi que leerlo desde
	# aca se comia una entrada del buffer por frame y desincronizaba la reproduccion.
	if not body.input_provider.has_method("peek_input"):
		return null
	return body.input_provider.peek_input()


# Apuntado y confirmacion, ambos desde el input grabado. Vivian solo en _input() —el giro
# del dial como InputEventMouseMotion.relative, el click como InputEventMouseButton— y en
# reproduccion no hay eventos de hardware, asi que el radial no se comportaba de forma
# determinista: el click caia en el momento equivocado porque la aguja nunca se habia
# movido. mouse_delta y tool_fire_primary SI se graban en InputDataV2, o sea que leyendo de
# aca el dial hace lo mismo en vivo que en reproduccion.
func _drive_from_stream() -> void:
	var input = _frame_input()
	if input == null:
		_stream_confirm_was_down = false
		return
	if _selector == null:
		return

	# EL GESTO ES LA ELECCION. El angulo con el que el jugador movio el mouse es el angulo
	# del dial: arriba el piso mas alto, abajo el mas bajo, a la derecha el medio del arco.
	# Nada de esto mira la camara, asi que el mismo gesto elige el mismo piso mire donde
	# mire el jugador (antes la puntería salia de la direccion camara→panel y el resultado
	# dependia de hacia donde estaba dado vuelta).
	#
	# Se lee el delta DEL FRAME, sin acumular: _process puede correr varias veces por cada
	# muestra de input —peek_input() devuelve la misma muestra— y acumular contaria el mismo
	# gesto de mas, que es justo lo que hacia que una reproduccion terminara en otro piso.
	# En InputProviderV2 mouse_delta ya viene con Y invertida (arriba es +Y); en pantalla
	# arriba es -Y, de ahi el signo.
	var gesture := Vector2(input.mouse_delta.x, -input.mouse_delta.y)
	var move := Vector2(input.move_vec.x, input.move_vec.y)
	if _touch_index < 0 and gesture.length() >= mouse_gesture_deadzone:
		# El mouse (o el stick derecho, que suma al mismo delta) manda mientras no haya un
		# dedo apoyado: en touch el arrastre de camara tambien alimenta mouse_delta, con
		# otra convencion de signos, y pisaria el gesto que ya resolvio _input().
		_mouse_aim_active = true
		_point_at_screen_direction(gesture)
	elif move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		# El stick de MOVIMIENTO tambien apunta, y su ultima direccion vale igual que la de
		# la mirada: en mobile el joystick virtual es la forma natural de manejar el dial, y
		# en joypad el stick derecho suma a mouse_delta, asi que sin esto la primera mirada
		# dejaba muerto al izquierdo para siempre. Manda el ultimo gesto, venga de donde
		# venga.
		#
		# El teclado es la excepcion, y para eso esta analog_move_active: WASD no es un
		# dispositivo de apuntado —para eso esta el mouse— y caminar por la cabina no puede
		# reelegir el piso. Solo apunta mientras el jugador todavia no movio el mouse.
		_point_at_screen_direction(move)

	var down: bool = bool(input.tool_fire_primary)
	if down and not _stream_confirm_was_down and _confirm_armed and _selector:
		_selector.confirm()
	_stream_confirm_was_down = down


func _any_confirm_held() -> bool:
	if _touch_index >= 0:
		return true
	# El stream grabado manda cuando existe: sondear Input.* aca dejaba la confirmacion
	# fuera del replay, el menu radial nunca recibia el click y el ascensor no viajaba.
	var input = _frame_input()
	if input != null:
		if bool(input.interact):
			return true
		if ("tool_fire_primary" in input) and bool(input.tool_fire_primary):
			return true
		# Sin hardware real detras (reproduccion), el stream es la unica verdad.
		if not bool(input.hardware_mouse_active):
			return false
	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		return true
	for action in ARMING_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _is_open or _selector == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _is_over_touch_control(event.position):
			return
		_handle_screen_touch(event)
		return
	if event is InputEventScreenDrag and event.index == _touch_index:
		# Use the whole gesture, not its last delta. Android can report a short
		# opposite "yank" as the finger lifts; it must not replace the intended
		# direction established by the rest of the drag.
		var gesture_direction: Vector2 = event.position - _touch_start_position
		if gesture_direction.length() >= touch_aim_min_drag_distance:
			_point_at_screen_direction(gesture_direction)
		return
	# El movimiento del mouse NO se lee aca: lo hace _drive_from_stream() sobre
	# InputDataV2.mouse_delta, la MISMA fuente en vivo y en reproduccion. Tener dos
	# implementaciones del mismo gesto era lo que hacia que el replay eligiera otro piso:
	# el stream invierte el signo de Y y lo cuantiza, el evento crudo no.

	if event.is_action_pressed("ui_cancel"):
		if auto_interact:
			# Ambient panel: nothing of its own to cancel. Don't swallow the event —
			# let it fall through to PauseManager so Esc/right-click still opens the
			# pause menu and releases the mouse while riding.
			return
		_selector.cancel()
		get_tree().set_input_as_handled()
		return

	if _confirm_armed:
		# El click primario tampoco se confirma aca: _drive_from_stream() lo detecta por
		# flanco sobre InputDataV2.tool_fire_primary, igual en vivo que en replay.
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
			get_tree().set_input_as_handled()
			return
		for action in CONFIRM_ACTIONS:
			if event.is_action_pressed(action):
				_selector.confirm()
				get_tree().set_input_as_handled()
				return

	# Look events are deliberately not consumed here. The camera keeps turning on
	# its own; the very same motion drives the dial through the input stream, so
	# the rider never has to choose between turning and picking a floor.


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	# Godot also emits a left mouse click for this touch. Ignore that duplicate;
	# touch confirmation has release and movement semantics of its own.
	_ignore_emulated_mouse_until = OS.get_ticks_msec() + 500
	if event.pressed:
		if _touch_index >= 0:
			return
		_touch_index = event.index
		_touch_start_time = OS.get_ticks_msec()
		_touch_start_position = event.position
		_touch_can_confirm = _confirm_armed
		return
	if event.index != _touch_index:
		return
	var duration: float = (OS.get_ticks_msec() - _touch_start_time) / 1000.0
	var distance: float = event.position.distance_to(_touch_start_position)
	_touch_index = -1
	var stayed_a_tap: bool = distance <= min(touch_tap_max_distance, touch_aim_min_drag_distance)
	if _touch_can_confirm and duration <= touch_tap_max_duration and stayed_a_tap:
		var direct_aim := _touch_in_viewport(event.position)
		if direct_aim != NO_AIM and _selector.option_at(direct_aim) >= 0:
			_selector.point_at(direct_aim)
			_selector.confirm()
	_touch_can_confirm = false


func _point_at_screen_direction(direction: Vector2) -> void:
	"""Aim the dial along a screen-space heading. Only the ANGLE is used: the dial
	maps 6 o'clock to the bottom stop and 12 to the top, so a flick upwards picks
	the top floor however short it was. The magnitude is normalised away on
	purpose — a gesture twice as long is the same intent, not a different one."""
	if _viewport == null or _selector == null or direction.length_squared() <= 0.0000001:
		return
	var radius: float = min(_viewport.size.x, _viewport.size.y) * 0.5
	_selector.point_at(_viewport.size * 0.5 + direction.normalized() * radius)


func _touch_in_viewport(screen_position: Vector2) -> Vector2:
	"""Map a tap onto the billboarded hologram. Unlike gesture aiming, this is a
	strict visual hit used only for direct tap confirmation."""
	var screen_mesh := get_node_or_null("ScreenContainer/ScreenMesh") as MeshInstance
	var scene_viewport := get_viewport()
	if screen_mesh == null or _viewport == null or scene_viewport == null:
		return NO_AIM
	var camera := scene_viewport.get_camera()
	if camera == null or not (screen_mesh.mesh is QuadMesh):
		return NO_AIM
	var origin: Vector3 = screen_mesh.global_transform.origin
	if camera.is_position_behind(origin):
		return NO_AIM
	var half_size: Vector2 = screen_mesh.mesh.size * 0.5
	var center: Vector2 = camera.unproject_position(origin)
	var right: Vector2 = camera.unproject_position(origin + camera.global_transform.basis.x * half_size.x) - center
	var up: Vector2 = camera.unproject_position(origin + camera.global_transform.basis.y * half_size.y) - center
	if right.length_squared() <= 0.001 or up.length_squared() <= 0.001:
		return NO_AIM
	var delta: Vector2 = screen_position - center
	var uv := Vector2(0.5 + delta.dot(right) / (2.0 * right.length_squared()),
		0.5 - delta.dot(up) / (2.0 * up.length_squared()))
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return NO_AIM
	return Vector2(uv.x * _viewport.size.x, uv.y * _viewport.size.y)


func _is_over_touch_control(screen_position: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("touch_control"):
		if node is Control and node.visible and node.is_inside_tree():
			if node.get_global_rect().has_point(screen_position):
				return true
	return false


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
	if OS.get_environment("DBG_SELECTOR") != "":
		print("[cabin] zona=%s  monitoring=%s  mask=%s" % [
			zone.name if zone != null else "NINGUNA",
			str(zone.monitoring) if zone != null else "-",
			str(zone.collision_mask) if zone != null else "-"])
	if zone == null:
		return
	if not zone.is_connected("body_entered", self, "_on_cabin_body_entered"):
		zone.connect("body_entered", self, "_on_cabin_body_entered")
	if not zone.is_connected("body_exited", self, "_on_cabin_body_exited"):
		zone.connect("body_exited", self, "_on_cabin_body_exited")


func _on_cabin_body_entered(body: Node) -> void:
	if OS.get_environment("DBG_SELECTOR") != "":
		print("[cabin] body_entered: %s  es_player=%s  ya_zoomed=%s" % [
			body.name, _is_player(body), _zoomed_player != null])
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


# Estado logico que decide el destino del ascensor. Deliberadamente NO se guarda el estado
# de puntería (touch/mouse aim), que es de entrada momentanea y se reconstruye solo.
func get_snapshot() -> Dictionary:
	return {
		"is_open": _is_open,
		"confirm_armed": _confirm_armed,
		"current_floor": _current_floor,
		"announced_floor": _announced_floor,
	}


func restore_snapshot(data: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	_is_open = bool(data.get("is_open", _is_open))
	_confirm_armed = bool(data.get("confirm_armed", _confirm_armed))
	_current_floor = int(data.get("current_floor", _current_floor))
	_announced_floor = int(data.get("announced_floor", _announced_floor))
	if is_inside_tree():
		_update_visuals()


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
