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
var _perf_monitor = null

# --- HIGHLIGHT SYSTEM ---
var _highlight_mesh: MeshInstance = null
var _original_materials: Array = []
const HIGHLIGHT_SHADER_PATH = "res://shaders/interactable_highlight.shader"

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

	# Register with Performance Monitor
	if Engine.has_singleton("PerformanceMonitor") or has_node("/root/PerformanceMonitor"):
		_perf_monitor = get_node("/root/PerformanceMonitor")
		if _perf_monitor and _perf_monitor.has_method("register_monitored_node"):
			_perf_monitor.register_monitored_node(self)

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
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self, "step")

	"""Called during fixed physics step. Updates animation progress."""
	if abs(anim_progress - target_progress) < 0.001:
		# Already at target
		if anim_progress != target_progress:
			anim_progress = target_progress
			_on_animation_completed()
		return
	
	print("[InteractableBaseV2] ", name, " step: anim_progress=", anim_progress, " target=", target_progress)
	
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
		_perf_monitor.measure_end(self, "step")

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

func set_highlighted(enabled: bool) -> void:
	"""Apply or remove the interaction highlight effect."""
	if enabled:
		_apply_highlight()
	else:
		_clear_highlight()

func _apply_highlight() -> void:
	"""Create and apply highlight overlay mesh."""
	if _highlight_mesh != null:
		return # Already highlighted
	
	# Store original materials for all mesh children
	_original_materials.clear()
	for child in _get_all_meshes(self):
		if child is MeshInstance:
			_original_materials.append({"mesh": child, "material": child.get_surface_material(0)})
	
	# Create highlight mesh as an outline overlay
	_highlight_mesh = _create_highlight_mesh()
	if _highlight_mesh:
		add_child(_highlight_mesh)

func _clear_highlight() -> void:
	"""Remove highlight overlay and restore original materials."""
	if _highlight_mesh != null:
		_highlight_mesh.queue_free()
		_highlight_mesh = null
	
	# Restore original materials
	for item in _original_materials:
		var mesh: MeshInstance = item.get("mesh")
		var material = item.get("material")
		if mesh and is_instance_valid(mesh):
			mesh.set_surface_material(0, material)
	_original_materials.clear()

func _get_all_meshes(node: Node) -> Array:
	"""Recursively get all MeshInstance children."""
	var meshes: Array = []
	for child in node.get_children():
		if child is MeshInstance:
			meshes.append(child)
		meshes.append_array(_get_all_meshes(child))
	return meshes

func _create_highlight_mesh() -> MeshInstance:
	"""Create a slightly scaled mesh with the highlight shader."""
	# Find the first mesh to use as template
	var template_mesh: Mesh = null
	for child in _get_all_meshes(self):
		if child is MeshInstance and child.mesh != null:
			template_mesh = child.mesh
			break
	
	if template_mesh == null:
		return null
	
	var highlight_instance = MeshInstance.new()
	highlight_instance.name = "_highlight_overlay"
	highlight_instance.mesh = template_mesh
	
	# Load and apply the highlight shader
	var shader = load(HIGHLIGHT_SHADER_PATH)
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_param("highlight_color", Color(1, 1, 0, 0.3))
		highlight_instance.set_surface_material(0, mat)
	
	# Slightly scale up to create outline effect
	highlight_instance.scale = Vector3(1.02, 1.02, 1.02)
	
	return highlight_instance

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
