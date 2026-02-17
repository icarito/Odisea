extends Spatial
class_name InteractableBridge
tool

# InteractableBridge.gd - Generic logic to bridge InteractableBaseV2 to other nodes.
# Supports automatic discovery (self or children) and manual configuration.

# --- EXPORTED CONFIG ---
export(NodePath) var source_node: NodePath # If empty, tries self or children
export(NodePath) var target_node: NodePath
export(String) var target_method := "set_active"
export(bool) var debug := false

# --- VISUAL HELPERS (Compatibility with Lever prefab) ---
export(Material) var base_material setget set_base_material
export(Color) var lever_color := Color(1, 0.5, 0.1) setget set_lever_color

var _sources := []
var _targets := []
var _is_syncing := false

func interact() -> void:
	"""Manual interaction trigger (for testing/validation)."""
	print("[%s] interact() called - DEBUG ENABLED." % name)
	if debug:
		print("[%s] Manual interact() called." % name)
	# Simulate a toggle or activation
	# Bridges usually sync state. If we don't have a state, we can try to toggle the target.
	# But usually bridges just forward. Let's assume we want to Activate.
	# Or better, check if we can read the target's state and flip it.

	var current_state = false
	# Best guess logic: Check first target
	if not _targets.empty() and _targets[0].has_method("get_is_active"):
		current_state = _targets[0].get_is_active()
	elif not _targets.empty() and "is_active" in _targets[0]:
		current_state = _targets[0].is_active

	# Bridge logic: Forward the NEW state
	var new_state = not current_state
	if debug:
		print("[InteractableBridge] State from Lever: %s" % new_state)
	if debug:
		print("[%s] Bridge interact: Toggling targets to %s" % [name, new_state])
	_sync_sources(new_state)
	_call_target(new_state)


func _ready():
	_find_and_connect_source()
	_find_and_connect_targets()
	_apply_visuals()

func _find_and_connect_source():
	_sources.clear()
	
	if not source_node.is_empty():
		var manual_source = get_node_or_null(source_node)
		if manual_source:
			_sources.append(manual_source)
	
	# Always attempt recursive discovery to find children/others
	# but avoid duplicates
	var discovered = []
	_find_sources_recursive(self, discovered)
	
	# Check parent
	var parent = get_parent()
	if parent and _is_source(parent):
		discovered.append(parent)
		
	for d in discovered:
		if not _sources.has(d):
			_sources.append(d)
	
	for s in _sources:
		if debug:
			print("[%s] Bridge connected to source: %s" % [name, s.name])
		
		# Connect signals
		if s.has_signal("activated") and not s.is_connected("activated", self, "_on_source_activated"):
			s.connect("activated", self, "_on_source_activated")
		if s.has_signal("deactivated") and not s.is_connected("deactivated", self, "_on_source_deactivated"):
			s.connect("deactivated", self, "_on_source_deactivated")
			
	if _sources.empty() and not Engine.editor_hint:
		push_warning("[%s] No source (trigger) found." % name)

func _find_and_connect_targets():
	_targets.clear()
	if not target_node.is_empty():
		var t = get_node_or_null(target_node)
		if t:
			_targets.append(t)
	else:
		# Automatic discovery of EVERYTHING in children that has target_method
		_find_targets_recursive(self)
	
	if debug:
		print("[%s] Found %d targets" % [name, _targets.size()])

func _find_sources_recursive(node: Node, result: Array):
	for child in node.get_children():
		if _is_source(child):
			result.append(child)
		_find_sources_recursive(child, result)

func _find_targets_recursive(node: Node):
	for child in node.get_children():
		if _sources.has(child): continue
		
		if child.has_method(target_method):
			_targets.append(child)
		
		_find_targets_recursive(child)

func _is_source(node: Node) -> bool:
	# Sources must have signals and usually have 'interact'
	return node and node.has_signal("activated") and node.has_method("interact")

# --- SIGNAL HANDLERS ---

func _on_source_activated():
	if _is_syncing: return
	_sync_sources(true)
	_call_target(true)

func _on_source_deactivated():
	if _is_syncing: return
	_sync_sources(false)
	_call_target(false)

func _sync_sources(value: bool):
	_is_syncing = true
	if debug:
		print("[%s] Syncing %d sources to %s" % [name, _sources.size(), value])
	for s in _sources:
		if s.has_method("set_active"):
			s.set_active(value) # Base class handles redundant calls
	_is_syncing = false

func _call_target(value: bool):
	print("[%s] _call_target(%s) called, _targets.size=%d" % [name, value, _targets.size()])
	if _targets.empty():
		if not Engine.editor_hint and not target_node.is_empty():
			push_error("[%s] target_node not found: %s" % [name, target_node])
		return
		
	for target in _targets:
		print("[%s] Checking target: %s" % [name, target.name])
		if not is_instance_valid(target): continue
		
		if target.has_method(target_method):
			print("[%s] Calling %s(%s) on %s" % [name, target_method, value, target.name])
			target.call(target_method, value)
		else:
			push_error("[%s] Target node %s does not have method %s" % [name, target.name, target_method])

# --- VISUAL HELPERS (Compatibility with Lever.tscn) ---

func set_base_material(mat):
	base_material = mat
	_apply_visuals()

func set_lever_color(c):
	lever_color = c
	_apply_visuals()

func _apply_visuals():
	if not is_inside_tree():
		return
		
	# Try to find LeverBase and RotatingLever (for prefab compatibility)
	var base = get_node_or_null("LeverBase")
	if base and base_material and base is CSGPrimitive:
		base.material = base_material
		
	var lever_node = get_node_or_null("LeverBase/RotatingLever")
	if lever_node:
		var mesh_instance = _find_mesh_instance(lever_node)
		if mesh_instance:
			var mat = mesh_instance.get_surface_material(0)
			if not mat or not mat.resource_local_to_scene:
				mat = SpatialMaterial.new()
				mat.resource_local_to_scene = true
				mesh_instance.set_surface_material(0, mat)
			if mat is SpatialMaterial:
				mat.albedo_color = lever_color

func _find_mesh_instance(node: Node) -> Node:
	if node is MeshInstance:
		return node
	for child in node.get_children():
		var found = _find_mesh_instance(child)
		if found:
			return found
	return null

func _notification(what):
	if what == NOTIFICATION_ENTER_TREE or (Engine.editor_hint and what == NOTIFICATION_READY):
		_apply_visuals()
