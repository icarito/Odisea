extends Spatial

# DDCSpawner.gd
# Manages progressive waves of DDC Containment drones spawning from level gates.

# --- EXPORTED CONFIGURATION ---
export(PackedScene) var ddc_scene = preload("res://core_v2/actors/DDCContainmentV1.tscn")
export(Array, NodePath) var spawn_gate_paths := []
export(float) var spawn_interval := 15.0
export(int) var max_simultaneous_ddc := 2
export(bool) var active := true
export(bool) var progressive_limit := true
export(float) var progressive_escalation_interval := 30.0

# --- STATE VARIABLES ---
var _gates := []
var _active_ddcs := []
var _spawn_timer := 0.0
var _progressive_timer := 0.0
var _current_limit := 1

func _ready() -> void:
	for path in spawn_gate_paths:
		var gate = get_node_or_null(path)
		if gate:
			_gates.append(gate)
			
	# If no gates configured, use children as gates if they are Spatials
	if _gates.size() == 0:
		for child in get_children():
			if child is Spatial:
				_gates.append(child)
				
	# Fallback to this spawner's transform as a single gate
	if _gates.size() == 0:
		_gates.append(self)

func _physics_process(delta: float) -> void:
	if not active:
		return
		
	# Clean up any freed DDC instances
	var alive_ddcs = []
	for ddc in _active_ddcs:
		if is_instance_valid(ddc) and not ddc.is_queued_for_deletion():
			alive_ddcs.append(ddc)
	_active_ddcs = alive_ddcs
	
	# Handle progressive limits over time
	if progressive_limit and _current_limit < max_simultaneous_ddc:
		_progressive_timer += delta
		if _progressive_timer >= progressive_escalation_interval:
			_progressive_timer = 0.0
			_current_limit = min(_current_limit + 1, max_simultaneous_ddc)
			
	var current_max = _current_limit if progressive_limit else max_simultaneous_ddc
	
	if _active_ddcs.size() >= current_max:
		return
		
	_spawn_timer += delta
	# Spawn immediately if there are 0 active DDCs and the spawner is active, 
	# or when spawn_timer finishes.
	if _spawn_timer >= spawn_interval or _active_ddcs.size() == 0:
		_spawn_timer = 0.0
		spawn_ddc()

func spawn_ddc() -> Node:
	if _gates.size() == 0 or not ddc_scene:
		return null
		
	# Select a gate
	var gate = _gates[randi() % _gates.size()]
	var ddc = ddc_scene.instance()
	
	# Add to scene first so global_transform setter resolves correctly
	get_parent().add_child(ddc)
	
	# Position at gate second
	ddc.global_transform = gate.global_transform
	
	_active_ddcs.append(ddc)

	# Play activation scale animation
	if ddc.has_method("play_spawn_animation"):
		ddc.play_spawn_animation()

	# Wire up capture: DDCContainmentV1 emits player_contained when it catches
	# the player, but nothing listens to it by default (CaptureSystem.trigger_capture
	# is otherwise only called by the older DDCDroneV2).
	if ddc.has_signal("player_contained"):
		var capture_system = get_node_or_null("/root/CaptureSystem")
		if capture_system and capture_system.has_method("trigger_capture"):
			ddc.connect("player_contained", capture_system, "trigger_capture", [ddc])

	return ddc

func get_active_ddcs() -> Array:
	return _active_ddcs
