extends Spatial
class_name MaintenanceElevator
tool

# MaintenanceElevator.gd
# Open industrial two-stop cargo elevator. Connects the Basement terrace (PB,
# y=0) with the Hatch Floor (1°, y=travel_height). Drives:
#   - The platform (KinematicBody) vertical motion along Y.
#   - The floor hatch (SlidingObjectV2) opening/closing, synced so the hatch
#     opens just before the platform tops out and closes after it clears.
#   - A call button (PedestalButton) that toggles UP/DOWN, plus an optional
#     external PipeValve that requests motion (no toggle).
#   - Industrial motor loop + arrival "ding" + hatch sliding SFX.
#
# Motion is integrated in step(dt) for replay determinism (same pattern as
# InteractableBaseV2 subclasses). The platform carries the player via the
# PassengerArea + transform-delta tracking used by MovingPlatformV2.

enum State { IDLE_BOTTOM, IDLE_TOP, MOVING_UP, MOVING_DOWN, EMERGENCY_STOP }

# --- EXPORTED TUNING ---
export(float) var travel_height := 8.0 setget set_travel_height # Y from PB (0) to 1°
export(float) var speed := 2.0 # m/s cruise speed
export(float) var approach_distance := 3.0 # last metres are eased to a soft stop
export(float) var min_approach_speed := 1.0 # m/s floor so it doesn't crawl forever
export(bool) var starts_at_top := false setget set_starts_at_top
# Hatch opens as soon as the platform enters the approach zone near the top, so
# the slow ~1s door slide finishes well before the deck reaches the opening.
# It closes on the way down once the deck has cleared this far above the floor.
export(float) var hatch_close_trigger := 1.5 # closes after platform > this (m)

# --- NODE PATHS ---
export(NodePath) var platform_path = NodePath("Platform")
export(NodePath) var hatch_path # FloorHatch (SlidingObjectV2 or proxy) — may be external
export(NodePath) var button_path = NodePath("Platform/CallButton")
export(NodePath) var block_area_path = NodePath("Platform/BlockArea")

# --- SIGNALS ---
signal elevator_arrived(floor_idx) # 0 = PB, 1 = 1°
signal elevator_departed(floor_idx)
signal elevator_blocked()

# --- INTERNAL STATE ---
var state = State.IDLE_BOTTOM
var platform_y := 0.0 # current platform local Y offset from PB
var _start_origin := Vector3.ZERO # platform local position at PB (y=0)
var _hatch_commanded_open := false
var _initialized := false

# Cached nodes
var _platform: Spatial = null
var _hatch: Node = null
var _button: Node = null
var _block_area: Area = null
var _sfx_motor: SFXComponentV2 = null
var _sfx_ding: SFXComponentV2 = null

# --- SETTERS ---

func set_starts_at_top(v: bool) -> void:
	starts_at_top = v
	if Engine.editor_hint and _initialized:
		platform_y = travel_height if starts_at_top else 0.0
		state = State.IDLE_TOP if starts_at_top else State.IDLE_BOTTOM
		_apply_platform_y()

func set_travel_height(v: float) -> void:
	travel_height = max(0.5, v)
	if _initialized:
		_apply_guide_rail_extent()
		if Engine.editor_hint:
			platform_y = travel_height if starts_at_top else 0.0
			_apply_platform_y()

func _apply_guide_rail_extent() -> void:
	# Stretch the vertical guide rails to span the full travel (+ a little
	# overshoot at each end so the platform stays captured).
	var rail = get_node_or_null("GuideRail")
	if rail == null:
		return
	var span = travel_height + 0.6 # 0.3m past each stop
	for child in rail.get_children():
		if child is CSGBox:
			child.height = span
			# Centre the rail vertically over the travel range.
			var t = child.transform
			t.origin.y = travel_height * 0.5
			child.transform = t

# --- LIFECYCLE ---

func _ready():
	add_to_group("replay_sync")
	# Move the platform before the player's _physics_process so the passenger's
	# transform-delta tracking reads a settled position each frame (no jitter,
	# especially on the way down where gravity fights the descending deck).
	process_priority = -10
	_cache_nodes()
	_initialized = true

	platform_y = travel_height if starts_at_top else 0.0
	state = State.IDLE_TOP if starts_at_top else State.IDLE_BOTTOM
	_hatch_commanded_open = (state == State.IDLE_TOP)

	_apply_guide_rail_extent()
	_apply_platform_y()
	_command_hatch(_hatch_commanded_open, true)

	if Engine.editor_hint:
		return

	# Wire the call button. PedestalButton is momentary: each press fires
	# `activated` once (the auto-release `deactivated` is ignored on purpose).
	if _button:
		if _button.has_signal("activated") and not _button.is_connected("activated", self, "_on_call_pressed"):
			_button.connect("activated", self, "_on_call_pressed")
		_update_button_label()

	# Wire blocking detection.
	if _block_area:
		if not _block_area.is_connected("body_entered", self, "_on_block_area_body"):
			_block_area.connect("body_entered", self, "_on_block_area_body")

func _cache_nodes() -> void:
	_platform = get_node_or_null(platform_path)
	if _platform:
		_start_origin = _platform.translation - Vector3(0, platform_y, 0)
	_hatch = get_node_or_null(hatch_path) if hatch_path else null
	_button = get_node_or_null(button_path)
	_block_area = get_node_or_null(block_area_path)
	_sfx_motor = get_node_or_null("Platform/SFXMotor")
	_sfx_ding = get_node_or_null("Platform/SFXDing")

# --- PUBLIC API ---

func interact() -> void:
	"""Allow the root to be driven directly (e.g. by a PipeValve proxy or the
	prop validator). Same toggle semantics as the call button."""
	call_elevator()

func call_elevator() -> void:
	"""Toggle behaviour: go to the floor we are NOT at. Ignored while moving."""
	match state:
		State.IDLE_BOTTOM:
			_start_move(true)
		State.IDLE_TOP:
			_start_move(false)
		_:
			pass # busy / emergency

func request_up() -> void:
	if state == State.IDLE_BOTTOM:
		_start_move(true)

func request_down() -> void:
	if state == State.IDLE_TOP:
		_start_move(false)

func is_busy() -> bool:
	return state == State.MOVING_UP or state == State.MOVING_DOWN

# --- MOTION ---

func _start_move(going_up: bool) -> void:
	state = State.MOVING_UP if going_up else State.MOVING_DOWN
	# If we're starting a descent from at/near the top, re-assert the hatch open.
	# The floor valve also drives the hatch closed on a "down" turn (an inherited
	# connection we can't remove); this cancels that premature close so the deck
	# isn't capped while still in the opening. The elevator alone decides when to
	# close (once the deck has dropped clear). On the way UP we leave the hatch
	# as-is so it only opens once we reach the approach zone near the top.
	if not going_up and platform_y >= travel_height - approach_distance:
		_command_hatch(true)
	emit_signal("elevator_departed", 0 if going_up else 1)
	_start_motor_sfx()
	_update_button_label()

func step(dt: float) -> void:
	if not _initialized or _platform == null:
		return
	if state != State.MOVING_UP and state != State.MOVING_DOWN:
		return

	var going_up = (state == State.MOVING_UP)
	var target = travel_height if going_up else 0.0
	var remaining = abs(target - platform_y)

	# Ease the last `approach_distance` metres down to a soft stop so the deck
	# arrives gently (and, going up, gives the hatch time to finish opening).
	var v = speed
	if approach_distance > 0.0 and remaining < approach_distance:
		var f = remaining / approach_distance # 1 -> 0 as we near the target
		v = max(min_approach_speed, speed * f)
	var delta_y = v * dt

	if going_up:
		platform_y = min(platform_y + delta_y, travel_height)
		# Open the hatch the moment we enter the approach zone — the slow door
		# slide then completes before the deck reaches the opening.
		if not _hatch_commanded_open and remaining <= approach_distance:
			_command_hatch(true)
		if platform_y >= travel_height:
			_arrive(State.IDLE_TOP, 1)
	else:
		platform_y = max(platform_y - delta_y, 0.0)
		# Close the hatch once the deck has dropped clear of the opening.
		if _hatch_commanded_open and platform_y <= hatch_close_trigger:
			_command_hatch(false)
		if platform_y <= 0.0:
			_arrive(State.IDLE_BOTTOM, 0)

	_apply_platform_y()

func _arrive(new_state: int, floor_idx: int) -> void:
	state = new_state
	_stop_motor_sfx()
	_play_ding_sfx()
	# Ensure hatch matches the resting state (open at top, closed at bottom).
	_command_hatch(floor_idx == 1)
	_update_button_label()
	emit_signal("elevator_arrived", floor_idx)

func _apply_platform_y() -> void:
	if _platform:
		_platform.translation = _start_origin + Vector3(0, platform_y, 0)

# --- HATCH ---

func _command_hatch(should_open: bool, immediate: bool = false) -> void:
	_hatch_commanded_open = should_open
	if _hatch == null:
		return
	if _hatch.has_method("set_active"):
		_hatch.set_active(should_open, immediate)
	elif _hatch.has_method("interact"):
		# Proxy that toggles — only call if it changes state.
		_hatch.interact()

# --- INTERACTION HANDLERS ---

func _on_call_pressed() -> void:
	call_elevator()

func _on_block_area_body(body) -> void:
	# BlockArea masks only layer 7 (Prop), so the world, hatch and player never
	# reach here — only a foreign prop body obstructing the rail does.
	if not is_busy():
		return
	if body == _platform or body.get_parent() == _platform:
		return
	_emergency_stop()

func _emergency_stop() -> void:
	if not is_busy():
		return
	state = State.EMERGENCY_STOP
	_stop_motor_sfx()
	emit_signal("elevator_blocked")

func resume_after_block() -> void:
	"""Clear an emergency stop. Resumes toward the nearest reasonable rest."""
	if state != State.EMERGENCY_STOP:
		return
	# Resume toward the floor we were heading to based on position.
	if platform_y >= travel_height - 0.01:
		_arrive(State.IDLE_TOP, 1)
	elif platform_y <= 0.01:
		_arrive(State.IDLE_BOTTOM, 0)
	else:
		# Continue upward if past halfway, else go down.
		_start_move(platform_y >= travel_height * 0.5)

# --- BUTTON LABEL ---

func _update_button_label() -> void:
	if _button == null:
		return
	var label := "SUBIR"
	match state:
		State.IDLE_BOTTOM:
			label = "SUBIR"
		State.IDLE_TOP:
			label = "BAJAR"
		State.MOVING_UP, State.MOVING_DOWN, State.EMERGENCY_STOP:
			label = "OCUPADO"
	if "interaction_text" in _button:
		_button.interaction_text = label

# --- AUDIO ---

func _start_motor_sfx() -> void:
	if Engine.editor_hint:
		return
	if _sfx_motor and not _sfx_motor.playing:
		_sfx_motor.play_sfx()

func _stop_motor_sfx() -> void:
	if _sfx_motor and _sfx_motor.playing:
		_sfx_motor.stop_sfx()

func _play_ding_sfx() -> void:
	if Engine.editor_hint:
		return
	if _sfx_ding:
		_sfx_ding.play_sfx()

# --- PHYSICS ---

func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	step(delta)

# --- REPLAY SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"state": state,
		"platform_y": platform_y,
		"hatch_open": _hatch_commanded_open
	}

func restore_snapshot(data: Dictionary) -> void:
	state = int(data.get("state", State.IDLE_BOTTOM))
	platform_y = float(data.get("platform_y", 0.0))
	_hatch_commanded_open = bool(data.get("hatch_open", false))
	_apply_platform_y()
	_command_hatch(_hatch_commanded_open, true)
	_update_button_label()
	if is_busy():
		_start_motor_sfx()
	else:
		_stop_motor_sfx()
