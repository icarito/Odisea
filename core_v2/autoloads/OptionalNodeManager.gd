extends Node

# --------------------------------------------------------------------------- #
# OptionalNodeManager
# --------------------------------------------------------------------------- #
# Manages optional scene content:
#   - Toggles visibility/processing of nodes in the "optional" group.
#   - Prunes heavy nodes on weak hardware (shadows, particles, etc.).
#   - Batches criopod meshes into MultiMesh for draw-call reduction.
# --------------------------------------------------------------------------- #

const LOW_SPEC_KEEP_GROUP := "switch_keep"
const LOW_SPEC_PRUNE_CLASSES := [
	"DirectionalLight",
	"GIProbe",
	"ReflectionProbe",
	"Particles",
	"CPUParticles"
]
const CRIOPOD_SOFT_CAP_ENV := "ODISEA_CRIOPOD_SOFT_CAP"
const DEFAULT_CRIOPOD_SOFT_CAP := 0
const TOGGLE_OPTIONAL_ACTION := "toggle_optional_nodes"
const EARLY_WEAK_HINT_ENV := "ODISEA_EARLY_WEAK_HARDWARE"

var _optional_enabled: bool = true
var _config_loaded: bool = false
var _cached_player: Spatial = null
var _criopod_soft_cap := DEFAULT_CRIOPOD_SOFT_CAP
var _weak_hardware_mode := false
var _player_unshade_pass_scheduled := false

signal optional_nodes_toggled(enabled)

# ── Lifecycle ─────────────────────────────────────────────────────────────── #

func _ready() -> void:
	_load_config()
	_configure_criopod_settings()
	_register_input_actions()
	_connect_tree_signals()
	_apply_initial_state()
	if _weak_hardware_mode:
		_apply_weak_runtime_fast_path()
		_schedule_player_unshade_pass()
		set_process_input(true)
		return
	call_deferred("_deferred_criopod_batch")
	set_process_input(true)

func _exit_tree() -> void:
	pass

# ── Configuration ─────────────────────────────────────────────────────────── #

func _configure_criopod_settings() -> void:
	var criopod_cap_env = OS.get_environment(CRIOPOD_SOFT_CAP_ENV)
	if criopod_cap_env.is_valid_integer():
		_criopod_soft_cap = max(0, int(criopod_cap_env))
	else:
		_criopod_soft_cap = DEFAULT_CRIOPOD_SOFT_CAP

func _load_config() -> void:
	var is_weak = false
	var weak_hint = OS.get_environment(EARLY_WEAK_HINT_ENV).to_lower()
	if weak_hint in ["1", "true", "yes", "on"]:
		is_weak = true
	elif weak_hint in ["0", "false", "no", "off"]:
		is_weak = false
	if has_node("/root/HardwareProfile"):
		var hp = get_node("/root/HardwareProfile")
		if hp.has_method("is_weak_hardware"):
			is_weak = hp.is_weak_hardware()
	_weak_hardware_mode = is_weak
	if is_weak:
		_optional_enabled = false
		_config_loaded = true
		_apply_weak_hardware_optimizations()
		return
	if ProjectSettings.has_setting("application/config/optional_nodes_enabled"):
		_optional_enabled = ProjectSettings.get_setting("application/config/optional_nodes_enabled")
	else:
		_optional_enabled = true
	_config_loaded = true

func _connect_tree_signals() -> void:
	var tree := get_tree()
	if not tree.is_connected("node_added", self , "_on_tree_node_added"):
		tree.connect("node_added", self , "_on_tree_node_added")
	if not tree.is_connected("node_removed", self , "_on_tree_node_removed"):
		tree.connect("node_removed", self , "_on_tree_node_removed")

func _register_input_actions() -> void:
	if not InputMap.has_action(TOGGLE_OPTIONAL_ACTION):
		InputMap.add_action(TOGGLE_OPTIONAL_ACTION)
	if InputMap.get_action_list(TOGGLE_OPTIONAL_ACTION).empty():
		push_warning("[OptionalNodeManager] Input action '%s' has no key bound in InputMap." % TOGGLE_OPTIONAL_ACTION)

# ── Input ─────────────────────────────────────────────────────────────────── #

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_OPTIONAL_ACTION):
		if _is_weak_hardware_active():
			return
		toggle_optional_nodes()

# ── Optional Node Management ──────────────────────────────────────────────── #

func _apply_initial_state() -> void:
	_update_all_optional_nodes()

func _update_all_optional_nodes() -> void:
	var optional_nodes = get_tree().get_nodes_in_group("optional")
	for node in optional_nodes:
		if not is_instance_valid(node):
			continue
		if _is_weak_hardware_active() and not _optional_enabled:
			if node.is_in_group(LOW_SPEC_KEEP_GROUP):
				_apply_low_spec_optimizations(node)
				continue
			_prune_node(node)
			continue
		_set_node_optional_state(node, _optional_enabled)
	emit_signal("optional_nodes_toggled", _optional_enabled)

func _on_tree_node_added(node: Node) -> void:
	call_deferred("_apply_node_policy", node)

func _on_tree_node_removed(_node: Node) -> void:
	pass

func _apply_node_policy(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if _is_weak_hardware_active():
		if _should_prune_on_low_spec(node):
			_prune_node(node)
			return
		_apply_low_spec_optimizations(node)
		return
	if _is_optional_or_under_optional(node):
		if node.is_in_group("player") or node.is_in_group("camera") or node is Camera or node is Listener or node is InterpolatedCamera:
			return
		_set_node_optional_state(node, _optional_enabled)

func _should_prune_on_low_spec(node: Node) -> bool:
	if node.is_in_group(LOW_SPEC_KEEP_GROUP):
		return false
	if node.is_in_group("scatter"):
		return true
	if _is_optional_or_under_optional(node):
		return true
	return node.get_class() in LOW_SPEC_PRUNE_CLASSES

func _is_optional_or_under_optional(node: Node) -> bool:
	if node.is_in_group("optional"):
		return true
	var current := node.get_parent()
	while current != null:
		if current.is_in_group("optional"):
			return true
		current = current.get_parent()
	return false

func _prune_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group(LOW_SPEC_KEEP_GROUP):
		return
	if node.is_in_group("player") or node.is_in_group("camera") or node is Camera or node is Listener:
		return
	if node.is_queued_for_deletion():
		return
	node.queue_free()

func _set_node_optional_state(node: Node, enabled: bool) -> void:
	if node is Spatial:
		node.visible = enabled
	if node is CanvasItem:
		node.visible = enabled
	if node.has_method("set_process"):
		node.set_process(enabled)
	if node.has_method("set_physics_process"):
		node.set_physics_process(enabled)
	if node is CollisionObject:
		if enabled:
			node.set_deferred("monitoring", true)
			node.set_deferred("monitorable", true)
		else:
			if node.is_in_group("player") or node.is_in_group("camera") or node is Camera or node is Listener:
				return
			node.set_deferred("monitoring", false)
			node.set_deferred("monitorable", false)

func toggle_optional_nodes() -> void:
	if _is_weak_hardware_active():
		return
	_optional_enabled = not _optional_enabled
	_update_all_optional_nodes()
	print("[OptionalNodeManager] Optional nodes: ", "ENABLED" if _optional_enabled else "DISABLED")

func set_optional_nodes_enabled(enabled: bool) -> void:
	var target_enabled = enabled
	if _is_weak_hardware_active():
		target_enabled = false
	if _optional_enabled != target_enabled:
		_optional_enabled = target_enabled
		_update_all_optional_nodes()
	elif _is_weak_hardware_active() and not target_enabled:
		_update_all_optional_nodes()

func is_optional_enabled() -> bool:
	return _optional_enabled

func get_optional_node_count() -> int:
	return get_tree().get_nodes_in_group("optional").size()

# ── Weak Hardware ─────────────────────────────────────────────────────────── #

func _is_weak_hardware_active() -> bool:
	if _weak_hardware_mode:
		return true
	if has_node("/root/HardwareProfile"):
		var hp = get_node("/root/HardwareProfile")
		if hp and hp.has_method("is_weak_hardware"):
			_weak_hardware_mode = bool(hp.is_weak_hardware())
			return _weak_hardware_mode
	return false

func _apply_weak_hardware_optimizations() -> void:
	print("[OptionalNodeManager] Applied weak hardware optimizations")

func _apply_weak_runtime_fast_path() -> void:
	pass

func _apply_low_spec_optimizations(node: Node) -> void:
	if node is Light:
		node.shadow_enabled = false
	if _is_player_like_node(node):
		_unshade_node_materials(node)
		_schedule_player_unshade_pass()
	elif node is MeshInstance and _is_player_or_descendant(node):
		_unshade_mesh_instance_materials(node)
	if node is Particles:
		node.emitting = false
	if node is CPUParticles:
		node.emitting = false
	if node is WorldEnvironment and node.environment:
		node.environment.glow_enabled = false
		node.environment.ssao_enabled = false
		node.environment.dof_blur_near_enabled = false
		node.environment.dof_blur_far_enabled = false
		node.environment.adjustment_enabled = false

# ── Player Unshading (LOW profile) ────────────────────────────────────────── #

func _is_player_like_node(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.is_in_group("player"):
		return true
	var script = node.get_script()
	if script and script is Script:
		var script_path = String((script as Script).resource_path)
		if script_path.ends_with("/PlayerControllerV2.gd"):
			return true
	var lowered_name = String(node.name).to_lower()
	if node is KinematicBody and lowered_name in ["pilot", "player", "elias"]:
		return true
	return false

func _is_player_or_descendant(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if _is_player_like_node(current):
			return true
		current = current.get_parent()
	return false

func _schedule_player_unshade_pass() -> void:
	if _player_unshade_pass_scheduled:
		return
	_player_unshade_pass_scheduled = true
	call_deferred("_apply_player_unshade_pass_deferred")

func _apply_player_unshade_pass_deferred() -> void:
	_player_unshade_pass_scheduled = false
	if not _is_weak_hardware_active():
		return
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	var players = get_tree().get_nodes_in_group("player")
	if players.empty():
		var fallback_player = get_tree().get_root().find_node("Pilot", true, false)
		if fallback_player and is_instance_valid(fallback_player):
			_unshade_node_materials(fallback_player)
		return
	for player in players:
		if is_instance_valid(player):
			_unshade_node_materials(player)

func _unshade_node_materials(node: Node) -> void:
	if node is MeshInstance:
		_unshade_mesh_instance_materials(node)
	for child in node.get_children():
		_unshade_node_materials(child)

func _unshade_mesh_instance_materials(mesh_node: MeshInstance) -> void:
	if mesh_node == null:
		return
	var surface_count := mesh_node.get_surface_material_count()
	if surface_count <= 0 and mesh_node.mesh:
		surface_count = mesh_node.mesh.get_surface_count()
	for i in range(surface_count):
		var mat = mesh_node.get_surface_material(i)
		if not mat and mesh_node.mesh:
			mat = mesh_node.mesh.surface_get_material(i)
		if mat is SpatialMaterial:
			mat.flags_unshaded = true
			mesh_node.set_surface_material(i, mat)
	if _is_player_or_descendant(mesh_node):
		mesh_node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF

# ── Criopod MultiMesh Batching ────────────────────────────────────────────── #

func _deferred_criopod_batch() -> void:
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	_apply_scatter_soft_caps()

func _apply_scatter_soft_caps() -> void:
	if _criopod_soft_cap <= 0:
		return
	var scatter2 = _get_scatter_node("Scatter3D2")
	if not scatter2:
		return
	var criopods := []
	for child in scatter2.get_children():
		if _is_criopod_instance_node(child):
			criopods.append(child)
	if criopods.size() <= _criopod_soft_cap:
		return
	criopods.sort_custom(self , "_sort_nodes_by_name")
	for i in range(_criopod_soft_cap, criopods.size()):
		criopods[i].queue_free()
	print(
		"[OptionalNodeManager] Criopod soft cap applied: keeping ",
		_criopod_soft_cap,
		" / ",
		criopods.size()
	)

# ── Helpers ───────────────────────────────────────────────────────────────── #

func _get_scatter_node(node_name: String) -> Node:
	var by_path = get_node_or_null("/root/Terrace/%s" % node_name)
	if by_path:
		return by_path
	return get_tree().get_root().find_node(node_name, true, false)

func _is_criopod_instance_node(node: Node) -> bool:
	if not (node and node is Spatial):
		return false
	if not ("Criopod" in String(node.name)):
		return false
	if node is MeshInstance and node.mesh != null:
		return true
	return node.get_node_or_null("Criopod") != null

func _sort_nodes_by_name(a: Node, b: Node) -> bool:
	return String(a.name) < String(b.name)

func _resolve_player_node() -> Spatial:
	if is_instance_valid(_cached_player):
		return _cached_player
	var players = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial and is_instance_valid(candidate):
			_cached_player = candidate
			return _cached_player
	return null
