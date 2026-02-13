extends Spatial
class_name InteractableBase

# InteractableBase.gd - Abstract Base Class for Deterministic Interactables
# Ensures 100% mathematical determinism for replay integrity.
# Subclasses implement _update_visuals() for specific behavior.

# --- EXPORTED TUNING ---
export(String) var interaction_text := "Interact"
export(float) var anim_duration := 1.0 # Seconds to complete animation
export(bool) var starts_active := false setget set_starts_active # Initial logical state
export(bool) var auto_interact := false # If true, automatically triggers when player is in range
export(bool) var one_off := false # If true, can only be used once (manually or automatically)
export(bool) var is_interactable := true # If false, ignore player interaction
export(bool) var manual_toggle := true # If false, emit signal but don't toggle state automatically
export(bool) var debug := false

func set_starts_active(v: bool) -> void:
	starts_active = v
	if Engine.editor_hint:
		is_active = v
		anim_progress = 1.0 if is_active else 0.0
		target_progress = anim_progress
		_update_visuals()

# --- STATE VARIABLES ---
# These are snapshotted for replay determinism
var is_active := false # Logical state (true = open/on, false = closed/off)
var is_used := false # Has it been triggered if one_off is true?
var _auto_triggered := false # Has auto-trigger already happened?
var anim_progress := 0.0 # Current visual position (0.0 to 1.0)
var target_progress := 0.0 # Goal state (1.0 or 0.0)

# Derived from anim_duration
var anim_speed := 1.0 # Progress increment per second

# --- SIGNALS ---
signal activated()
signal deactivated()
signal interaction_requested()
signal interaction_started()
signal interaction_completed()

func _init():
	add_to_group("interactable")
	add_to_group("replay_sync")

func _ready():
	# Initial state setup
	is_active = starts_active
	anim_progress = 1.0 if is_active else 0.0
	target_progress = anim_progress
	
	# Calculate speed from duration
	if anim_duration > 0:
		anim_speed = 1.0 / anim_duration
	else:
		anim_speed = 1.0
	
	# Initialize visuals to current state
	_update_visuals()

# --- CORE API ---

func interact() -> void:
	"""Toggle the active state. Called by player interaction system."""
	if not is_interactable:
		return

	if one_off and is_used:
		if debug:
			print("[%s] Already used (one_off), ignoring interaction." % name)
		return
	
	emit_signal("interaction_requested")
	
	if manual_toggle:
		set_active(not is_active)
	
	if one_off:
		is_used = true

func set_active(value: bool, immediate: bool = false) -> void:
	"""Set the logical state and start/snap animation."""
	if is_active == value and not immediate:
		return
		
	is_active = value
	target_progress = 1.0 if is_active else 0.0
	
	if immediate:
		anim_progress = target_progress
		_update_visuals()
		_on_animation_completed()
	else:
		emit_signal("interaction_started")
	
	if debug:
		print("[%s] set_active(%s) -> target=%s" % [name, is_active, target_progress])

func step(dt: float) -> void:
	"""Called during fixed physics step. Updates animation progress."""
	if abs(anim_progress - target_progress) < 0.001:
		# Already at target
		if anim_progress != target_progress:
			anim_progress = target_progress
			_on_animation_completed()
		return
	
	# Move towards target
	var direction = sign(target_progress - anim_progress)
	anim_progress += direction * anim_speed * dt
	
	# Clamp and check completion
	if direction > 0 and anim_progress >= target_progress:
		anim_progress = target_progress
		_on_animation_completed()
	elif direction < 0 and anim_progress <= target_progress:
		anim_progress = target_progress
		_on_animation_completed()
	
	_update_visuals()

func _on_animation_completed() -> void:
	"""Called when animation reaches target. Override for sound triggers."""
	emit_signal("interaction_completed")
	
	if is_active:
		emit_signal("activated")
	else:
		emit_signal("deactivated")
	
	if debug:
		print("[%s] Animation completed: progress=%s" % [name, anim_progress])


# --- VIRTUAL METHODS (Override in subclasses) ---

func _update_visuals() -> void:
	"""Update the visual representation based on anim_progress.
	Override this in subclasses (SlidingObject, RotatingObject, etc.)"""
	pass

# --- EASING UTILITIES ---

func _ease_in_out(t: float) -> float:
	"""Smooth ease-in-out curve."""
	return t * t * (3.0 - 2.0 * t)

func _ease_out(t: float) -> float:
	"""Ease-out curve (fast start, slow end)."""
	return 1.0 - (1.0 - t) * (1.0 - t)

func _ease_in(t: float) -> float:
	"""Ease-in curve (slow start, fast end)."""
	return t * t

# --- REPLAY SYSTEM (Snapshot Serialization) ---

func get_snapshot() -> Dictionary:
	"""Return state dictionary for replay system."""
	return {
		"active": is_active,
		"used": is_used,
		"auto_triggered": _auto_triggered,
		"progress": anim_progress,
		"target": target_progress
	}

func restore_snapshot(data: Dictionary) -> void:
	"""Restore state from snapshot dictionary."""
	is_active = data.get("active", false)
	is_used = data.get("used", false)
	_auto_triggered = data.get("auto_triggered", false)
	anim_progress = data.get("progress", 0.0)
	target_progress = data.get("target", 0.0)
	
	# Immediate visual snap (no animation)
	_update_visuals()

# --- PHYSICS PROCESS ---

func _physics_process(delta: float) -> void:
	# print("DEBUG: _physics_process called on ", name)
	step(delta)
