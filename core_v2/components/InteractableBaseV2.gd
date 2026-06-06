extends Spatial
class_name InteractableBaseV2

# InteractableBaseV2.gd - Abstract Base Class for Deterministic Interactables
# Ensures 100% mathematical determinism for replay integrity.
# Subclasses implement _update_visuals() for specific behavior.

# --- EXPORTED TUNING ---
export(String) var interaction_text := "Interact"
export(float) var anim_duration := 1.0 # Seconds to complete animation
export(bool) var starts_active := false setget set_starts_active # Initial logical state
export(bool) var auto_interact := false # If true, automatically triggers when player is in range
export(bool) var one_off := false # If true, can only be used once (manually or automatically)
export(bool) var is_interactable := true setget set_is_interactable # If false, ignore player interaction
export(bool) var is_focusable := false setget set_is_focusable # If true, player can target this for focus-only actions
export(String) var focus_text := "Focus"
export(bool) var manual_toggle := true # If false, emit signal but don't toggle state automatically
export(bool) var debug := false

func set_starts_active(v: bool) -> void:
	starts_active = v
	if Engine.editor_hint:
		is_active = v
		anim_progress = 1.0 if is_active else 0.0
		target_progress = anim_progress
		_update_visuals()

func set_is_interactable(v: bool) -> void:
	is_interactable = v
	if is_interactable:
		if not is_in_group("interactable"):
			add_to_group("interactable")
	else:
		if is_in_group("interactable"):
			remove_from_group("interactable")

func set_is_focusable(v: bool) -> void:
	is_focusable = v
	if is_focusable:
		if not is_in_group("focusable"):
			add_to_group("focusable")
	else:
		if is_in_group("focusable"):
			remove_from_group("focusable")

# --- STATE VARIABLES ---
# These are snapshotted for replay determinism
var is_active := false # Logical state (true = open/on, false = closed/off)
var is_used := false # Has it been triggered if one_off is true?
var _auto_triggered := false # Has auto-trigger already happened?
var anim_progress := 0.0 # Current visual position (0.0 to 1.0)
var target_progress := 0.0 # Goal state (1.0 or 0.0)

# Derived from anim_duration
var anim_speed := 1.0 # Progress increment per second
var _perf_monitor = null

# --- HIGHLIGHT SYSTEM ---
var _highlight_meshes: Array = []
var _proximity_meshes: Array = []
const PROXIMITY_SHADER_PATH = "res://shaders/proximity_glow.shader"
const _HIGHLIGHT_SHADER: Shader = preload("res://core_v2/visual/interact_highlight.shader")

# --- SIGNALS ---
signal activated()
signal deactivated()
signal interaction_requested()
signal interaction_started()
signal interaction_completed()

func _init():
	set_is_interactable(is_interactable)
	set_is_focusable(is_focusable)
	add_to_group("replay_sync")

func _ready():
	set_is_interactable(is_interactable)
	set_is_focusable(is_focusable)
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

	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor and _perf_monitor.has_method("register_monitored_node"):
			_perf_monitor.register_monitored_node(self )

# --- CORE API ---

func interact() -> void:
	"""Toggle the active state. Called by player interaction system."""
	if has_meta("airlock_controller_owned") and bool(get_meta("airlock_controller_owned")):
		_forward_airlock_owned_interaction()
		return
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

func _forward_airlock_owned_interaction() -> void:
	if not has_meta("airlock_controller_owner_path"):
		return
	var owner_path = get_meta("airlock_controller_owner_path")
	var owner: Node = null
	if owner_path is NodePath:
		owner = get_node_or_null(owner_path)
	if not is_instance_valid(owner):
		return
	var door_name := String(get_meta("airlock_door_name") if has_meta("airlock_door_name") else "")
	if owner.has_method("request_door_interaction"):
		owner.request_door_interaction(door_name)

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
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self , "step")

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

	if _perf_monitor and _perf_monitor.has_method("measure_end"):
		_perf_monitor.measure_end(self , "step")

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
	Override this in subclasses (SlidingObjectV2, RotatingObjectV2, etc.)"""
	pass

# --- HIGHLIGHT API ---

func set_highlighted(enabled: bool, color: Color = Color.cyan) -> void:
	"""Apply or remove the interaction highlight effect."""
	if enabled:
		_apply_highlight(color)
	else:
		_clear_highlight()

func set_proximity_highlight(enabled: bool, color: Color = Color(0.0, 1.0, 1.0, 0.1)) -> void:
	"""Apply or remove the subtle proximity glow."""
	if enabled:
		_apply_proximity(color)
	else:
		_clear_proximity()

func _apply_highlight(color: Color) -> void:
	if _highlight_meshes.size() > 0:
		for overlay in _highlight_meshes:
			if is_instance_valid(overlay) and overlay.material_override:
				overlay.material_override.set_shader_param("highlight_color", color)
		return

	for child in _get_all_meshes(self):
		if not (child is MeshInstance): continue
		var base_mesh := child as MeshInstance
		if base_mesh.mesh == null: continue

		var overlay := MeshInstance.new()
		overlay.name = "_highlight_overlay"
		overlay.mesh = base_mesh.mesh
		overlay.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		# outline shader expands via normals — no scale needed

		var mat := ShaderMaterial.new()
		mat.shader = _HIGHLIGHT_SHADER
		mat.set_shader_param("highlight_color", color)
		overlay.material_override = mat

		base_mesh.add_child(overlay)
		_highlight_meshes.append(overlay)

func _apply_proximity(color: Color) -> void:
	"""Create and apply subtle proximity glow overlays."""
	if _proximity_meshes.size() > 0:
		for overlay in _proximity_meshes:
			if is_instance_valid(overlay) and overlay.material_override:
				overlay.material_override.set_shader_param("glow_color", color)
		return

	var shader = load(PROXIMITY_SHADER_PATH)
	if shader == null: return

	for child in _get_all_meshes(self ):
		if not (child is MeshInstance): continue
		var base_mesh := child as MeshInstance
		if base_mesh.mesh == null: continue

		var overlay := MeshInstance.new()
		overlay.name = "_proximity_overlay"
		overlay.mesh = base_mesh.mesh
		overlay.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		overlay.scale = Vector3(1.01, 1.01, 1.01)

		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_param("glow_color", color)
		overlay.material_override = mat

		base_mesh.add_child(overlay)
		_proximity_meshes.append(overlay)

func _clear_highlight() -> void:
	"""Remove highlight overlays."""
	for overlay in _highlight_meshes:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_highlight_meshes.clear()

func _clear_proximity() -> void:
	"""Remove proximity overlays."""
	for overlay in _proximity_meshes:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_proximity_meshes.clear()

func _get_all_meshes(node: Node) -> Array:
	"""Recursively get all MeshInstance children."""
	var meshes: Array = []
	for child in node.get_children():
		if child is MeshInstance:
			meshes.append(child)
		meshes.append_array(_get_all_meshes(child))
	return meshes

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
