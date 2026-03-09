extends Node

const LOW_SPEC_KEEP_GROUP := "switch_keep"
const LOW_SPEC_PRUNE_CLASSES := [
	"DirectionalLight",
	"GIProbe",
	"ReflectionProbe",
	"Particles",
	"CPUParticles"
]
const BOX_STACK_MIN_COUNT := 6
const BOX_STACK_GAP := 2.02
const BOX_STACK_WAKE_CHECK_INTERVAL_FRAMES := 12
const BOX_WATCHDOG_INTERVAL_SEC := 2.0
const BOX_WATCHDOG_CHECKS_PER_TICK := 2
const BOX_SUPPORT_RAY_EXTRA := 0.35
const BOX_TILT_MIN_DOT := 0.96
const THREAD_SCATTER_ENV := "ODISEA_THREAD_SCATTER_LAZY"
const DISABLE_SCATTER_ENV := "ODISEA_DISABLE_TERRACE_SCATTER"
const CRIOPOD_SOFT_CAP_ENV := "ODISEA_CRIOPOD_SOFT_CAP"
const CRIOPOD_MULTIMESH_ENV := "ODISEA_CRIOPOD_MULTIMESH"
const DEFAULT_CRIOPOD_SOFT_CAP := 0
const THREAD_SCATTER_BOX_SCENE_PATH := "res://core_v2/components/PushableBoxV2.tscn"
const THREAD_SCATTER_CRIOPOD_SCENE_PATH := "res://core_v2/props/CriopodParallax.tscn"
const THREAD_SCATTER_BATCH_BOXES := 4
const THREAD_SCATTER_BATCH_CRIOPODS := 8
const THREAD_SCATTER_BATCH_DELAY_SEC := 0.03
const THREAD_SCATTER_WAIT_FRAMES := 240
const CRIOPOD_FREE_BATCH_SIZE := 6
const TOGGLE_OPTIONAL_ACTION := "toggle_optional_nodes"
const INTERACT_ACTION := "interact"
const EARLY_WEAK_HINT_ENV := "ODISEA_EARLY_WEAK_HARDWARE"
const PROFILE_LOW := 1
const PROFILE_MEDIUM := 2
const DECOR_RB_CULL_INTERVAL_SEC := 0.15
const DECOR_RB_CULL_BATCH_PER_TICK := 8
const DECOR_RB_FREEZE_RADIUS_LOW := 20.0
const DECOR_RB_FREEZE_RADIUS_MEDIUM := 26.0
const DECOR_RB_FREEZE_RADIUS_HIGH := 34.0
const DECOR_RB_INTERACT_WAKE_RADIUS := 3.5
const META_DISTANCE_FROZEN := "__optional_distance_frozen"

class ScatterPreloadWorker:
	extends Reference

	func run(_unused = null) -> Dictionary:
		# Keep this thread lightweight. In Godot 3, loading PackedScenes from threads
		# can deadlock depending on project/resource cache state.
		# We keep threaded orchestration and lazy-load resources on the main thread.
		return {
			"box_scene": null,
			"criopod_scene": null,
			"threaded_orchestration": true
		}

var _optional_enabled: bool = true
var _config_loaded: bool = false
var _stacked_box_paths := []
var _stacked_boxes_cache := []
var _box_watchdog_running := false
var _box_watchdog_cursor := 0
var _decor_rb_culling_running := false
var _decor_rb_cursor := 0
var _decor_rb_forced_sleep_ids := {}
var _cached_player: Spatial = null
var _thread_scatter_enabled := false
var _scatter_disabled_by_env := false
var _criopod_soft_cap := DEFAULT_CRIOPOD_SOFT_CAP
var _criopod_multimesh_enabled := true
var _criopods_batched := false
var _scatter_preload_thread: Thread = null
var _scatter_preload_worker: Reference = null
var _scatter_preload_done := false
var _scatter_preload_data := {}
var _scatter_box_blueprints := []
var _scatter_criopod_blueprints := []
var _candidate_boxes_cache := []
var _candidate_boxes_dirty := true
var _weak_hardware_mode := false
var _player_unshade_pass_scheduled := false

signal optional_nodes_toggled(enabled)

func _ready() -> void:
	_load_config()
	_configure_scatter_threading()
	_register_input_actions()
	_connect_tree_signals()
	_apply_initial_state()
	if _weak_hardware_mode:
		_apply_weak_runtime_fast_path()
		_schedule_player_unshade_pass()
		set_process_input(true)
		return
	if _thread_scatter_enabled and not _scatter_disabled_by_env:
		_start_threaded_scatter_preload()
	_delayed_scatter_load() # Load scatter later to speed up startup
	if not _scatter_disabled_by_env:
		_start_box_watchdog()
		_start_decorative_rigidbody_culling()
	set_process_input(true)

func _exit_tree() -> void:
	_box_watchdog_running = false
	_decor_rb_culling_running = false
	if _scatter_preload_thread and not _scatter_preload_thread.is_active():
		_scatter_preload_thread.wait_to_finish()
	_scatter_preload_thread = null
	_scatter_preload_worker = null

func _configure_scatter_threading() -> void:
	var disable_value = OS.get_environment(DISABLE_SCATTER_ENV).to_lower()
	_scatter_disabled_by_env = disable_value in ["1", "true", "yes", "on"]
	var multimesh_env = OS.get_environment(CRIOPOD_MULTIMESH_ENV).to_lower()
	if multimesh_env == "":
		_criopod_multimesh_enabled = true
	else:
		_criopod_multimesh_enabled = multimesh_env in ["1", "true", "yes", "on"]
	var criopod_cap_env = OS.get_environment(CRIOPOD_SOFT_CAP_ENV)
	if criopod_cap_env.is_valid_integer():
		_criopod_soft_cap = max(0, int(criopod_cap_env))
	else:
		_criopod_soft_cap = DEFAULT_CRIOPOD_SOFT_CAP
	var env_value = OS.get_environment(THREAD_SCATTER_ENV).to_lower()
	_thread_scatter_enabled = env_value in ["1", "true", "yes", "on"]
	if _scatter_disabled_by_env:
		_thread_scatter_enabled = false
		print("[OptionalNodeManager] Scatter disabled by env: ", DISABLE_SCATTER_ENV)
	if _thread_scatter_enabled:
		print("[OptionalNodeManager] Threaded scatter lazy load enabled")

func _delayed_scatter_load() -> void:
	# Defer scatter loading to speed up initial startup
	call_deferred("_hide_scatter_always")

func _apply_weak_runtime_fast_path() -> void:
	# Weak devices should skip any deferred scatter reconstruction/background watchdogs.
	_scatter_disabled_by_env = true
	_thread_scatter_enabled = false
	_box_watchdog_running = false
	_decor_rb_culling_running = false
	call_deferred("_hide_scatter_objects")

func _load_config() -> void:
	# Check for weak hardware or Linux ARM handheld
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
	
	# Also force LOW for Linux ARM devices (Anbernic, etc)
	if OS.get_name() in ["Linux", "X11", "Server"]:
		if _is_linux_arm_device():
			is_weak = true
		elif _is_linux_low_memory_device():
			is_weak = true

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

func _is_linux_arm_device() -> bool:
	if not OS.get_name() in ["Linux", "X11", "Server"]:
		return false
	# Check for ARM architecture
	var file = File.new()
	if file.file_exists("/proc/cpuinfo"):
		if file.open("/proc/cpuinfo", File.READ) == OK:
			var content := ""
			var guard := 0
			var max_bytes := 65536
			while not file.eof_reached() and guard < max_bytes:
				var b = int(file.get_8())
				if b == 0:
					content += " "
				else:
					content += char(b)
				guard += 1
			file.close()
			content = content.to_lower()
			return "arm" in content or "aarch64" in content
	return false

func _is_linux_low_memory_device() -> bool:
	if not OS.get_name() in ["Linux", "X11", "Server"]:
		return false
	var file = File.new()
	if not file.file_exists("/proc/meminfo"):
		return false
	if file.open("/proc/meminfo", File.READ) != OK:
		return false
	var meminfo := ""
	var guard := 0
	var max_bytes := 32768
	while not file.eof_reached() and guard < max_bytes:
		var b = int(file.get_8())
		if b == 0:
			meminfo += " "
		else:
			meminfo += char(b)
		guard += 1
	file.close()
	for raw_line in meminfo.split("\n"):
		var line = String(raw_line).strip_edges()
		if not line.begins_with("MemTotal"):
			continue
		var parts = line.split(":")
		if parts.size() < 2:
			continue
		var kb = _parse_first_int(parts[1])
		if kb <= 0:
			return false
		var total_gb = float(kb) / 1024.0 / 1024.0
		return total_gb <= 1.05
	return false

func _parse_first_int(raw: String) -> int:
	var digits := ""
	for i in range(raw.length()):
		var ch = raw.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	if digits == "":
		return 0
	return int(digits)

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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_OPTIONAL_ACTION):
		if _is_weak_hardware_active():
			return
		toggle_optional_nodes()
	if event.is_action_pressed(INTERACT_ACTION):
		_wake_nearest_distance_frozen_box()

func _is_weak_hardware_active() -> bool:
	if _weak_hardware_mode:
		return true
	if has_node("/root/HardwareProfile"):
		var hp = get_node("/root/HardwareProfile")
		if hp and hp.has_method("is_weak_hardware"):
			_weak_hardware_mode = bool(hp.is_weak_hardware())
			return _weak_hardware_mode
	return false

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
	_candidate_boxes_dirty = true
	call_deferred("_apply_node_policy", node)

func _on_tree_node_removed(_node: Node) -> void:
	_candidate_boxes_dirty = true

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
		# Never disable the player or camera even if they are under an optional parent
		if node.is_in_group("player") or node.is_in_group("camera") or node is Camera or node is Listener or node is InterpolatedCamera:
			return
		_set_node_optional_state(node, _optional_enabled)

func _should_prune_on_low_spec(node: Node) -> bool:
	if node.is_in_group(LOW_SPEC_KEEP_GROUP):
		return false
	if node.is_in_group("scatter"):
		return true
	var node_name = String(node.name)
	if node_name == "Scatter3D" or node_name == "Scatter3D2":
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
	# Player meshes in LOW should not cast dynamic shadows to avoid mobile depth artifacts.
	if _is_player_or_descendant(mesh_node):
		mesh_node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF

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
			# Never disable collision or processing for the player or camera
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
		# Re-apply low-spec pruning when hardware profile drops at runtime.
		_update_all_optional_nodes()

func is_optional_enabled() -> bool:
	return _optional_enabled

func get_optional_node_count() -> int:
	return get_tree().get_nodes_in_group("optional").size()

func _apply_weak_hardware_optimizations() -> void:
	# Hide Scatter3D objects - they are too heavy for weak hardware
	call_deferred("_hide_scatter_objects")
	print("[OptionalNodeManager] Applied weak hardware optimizations")

func _hide_scatter_always() -> void:
	if _scatter_disabled_by_env:
		call_deferred("_hide_scatter_objects")
		return
	# Lazy load scatter objects - load them after initial scene loads
	# This speeds up startup while still showing them eventually
	call_deferred("_lazy_load_scatter")

func _get_scatter_node(node_name: String) -> Node:
	var by_path = get_node_or_null("/root/Terrace/%s" % node_name)
	if by_path:
		return by_path
	return get_tree().get_root().find_node(node_name, true, false)

func _wait_for_scatter_nodes(max_wait_frames: int = THREAD_SCATTER_WAIT_FRAMES):
	# Always yield one frame so callers can safely yield on this method.
	yield (get_tree(), "idle_frame")
	var waited := 0
	while waited < max_wait_frames:
		if _get_scatter_node("Scatter3D") or _get_scatter_node("Scatter3D2"):
			return
		yield (get_tree(), "idle_frame")
		waited += 1

func _lazy_load_scatter() -> void:
	if _thread_scatter_enabled:
		yield (_lazy_load_scatter_threaded(), "completed")
		return

	# Wait for initial load
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	yield (_wait_for_scatter_nodes(), "completed")
	_apply_scatter_soft_caps()
	yield (_batch_criopods_to_multimesh(), "completed")
	
	# Load Criopods first (they're simpler)
	var scatter2 = _get_scatter_node("Scatter3D2")
	if scatter2:
		scatter2.visible = true
		print("[OptionalNodeManager] Loaded Scatter3D2 (Criopods)")
	
	# Then arrange and load boxes after 3 more seconds
	yield (get_tree().create_timer(3.0), "timeout")
	_arrange_boxes_in_stacks()
	var scatter = _get_scatter_node("Scatter3D")
	if scatter:
		scatter.visible = true
		print("[OptionalNodeManager] Loaded Scatter3D (Boxes)")
	
	# Keep boxes stacked and sleeping/kinematic by default.
	# They will wake up on interaction via PushableBoxV2 wake logic.
	_wake_misplaced_boxes()

func _lazy_load_scatter_threaded():
	# Wait for initial load
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	yield (_wait_for_scatter_nodes(), "completed")
	_apply_scatter_soft_caps()
	yield (_batch_criopods_to_multimesh(), "completed")

	if _scatter_box_blueprints.empty() and _scatter_criopod_blueprints.empty():
		_prepare_threaded_scatter_blueprints()

	yield (_wait_for_scatter_preload(), "completed")

	var criopod_scene = _scatter_preload_data.get("criopod_scene", null)
	yield (_spawn_scatter_blueprints("Scatter3D2", _scatter_criopod_blueprints, criopod_scene, THREAD_SCATTER_BATCH_CRIOPODS), "completed")
	print("[OptionalNodeManager] Loaded Scatter3D2 (Criopods)")

	# Then arrange and load boxes after 3 more seconds
	yield (get_tree().create_timer(3.0), "timeout")
	var box_scene = _scatter_preload_data.get("box_scene", null)
	yield (_spawn_scatter_blueprints("Scatter3D", _scatter_box_blueprints, box_scene, THREAD_SCATTER_BATCH_BOXES), "completed")
	_arrange_boxes_in_stacks()
	print("[OptionalNodeManager] Loaded Scatter3D (Boxes)")

	# Keep boxes stacked and sleeping/kinematic by default.
	# They will wake up on interaction via PushableBoxV2 wake logic.
	_wake_misplaced_boxes()

func _prepare_threaded_scatter_blueprints() -> void:
	_scatter_box_blueprints = []
	_scatter_criopod_blueprints = []

	var scatter = _get_scatter_node("Scatter3D")
	if scatter:
		_scatter_box_blueprints = _capture_scatter_blueprints(scatter, true)
		for child in scatter.get_children():
			if child is Spatial and "PushableBox" in child.name:
				child.queue_free()
		scatter.visible = false

	var scatter2 = _get_scatter_node("Scatter3D2")
	if scatter2:
		_scatter_criopod_blueprints = _capture_scatter_blueprints(scatter2, false)
		if _criopod_soft_cap > 0 and _scatter_criopod_blueprints.size() > _criopod_soft_cap:
			_scatter_criopod_blueprints = _scatter_criopod_blueprints.slice(0, _criopod_soft_cap)
		for child in scatter2.get_children():
			if child is Spatial and not _is_criopod_batch_node(child):
				child.queue_free()
		scatter2.visible = false

	print(
		"[OptionalNodeManager] Captured threaded scatter blueprints: boxes=",
		_scatter_box_blueprints.size(),
		" criopods=",
		_scatter_criopod_blueprints.size()
	)

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

func _batch_criopods_to_multimesh() -> void:
	# Always yield at least one frame so callers can safely yield on this method.
	yield (get_tree(), "idle_frame")

	if not _criopod_multimesh_enabled:
		return
	if _criopods_batched:
		return

	var scatter2 = _get_scatter_node("Scatter3D2")
	if not scatter2:
		return
	if scatter2.get_node_or_null("CriopodBatchRoot"):
		_criopods_batched = true
		return

	var criopods := []
	for child in scatter2.get_children():
		if _is_criopod_instance_node(child):
			criopods.append(child)
	if criopods.empty():
		return

	var batch_root := Spatial.new()
	batch_root.name = "CriopodBatchRoot"
	scatter2.add_child(batch_root)

	var main_count = _build_criopod_multimesh(batch_root, criopods, "Criopod", "CriopodMeshBatch")
	var glass_count = _build_criopod_multimesh(batch_root, criopods, "RotatingObjectV2/Glass", "CriopodGlassBatch")
	var pilot_count = _build_criopod_multimesh(batch_root, criopods, "PersonCard2", "CriopodPilotBatch")

	# Hide visual meshes on ALL criopods but keep collision bodies for full collision coverage
	# The multimesh provides visual rendering, original nodes provide collision
	for pod in criopods:
		if not is_instance_valid(pod):
			continue
		_hide_criopod_visuals(pod)
		# Note: NOT calling queue_free() - keeping collision bodies

	_criopods_batched = true
	print(
		"[OptionalNodeManager] Criopods batched to MultiMesh: pods=",
		criopods.size(),
		" main=",
		main_count,
		" glass=",
		glass_count,
		" pilot=",
		pilot_count
	)

func _build_criopod_multimesh(batch_root: Spatial, criopods: Array, mesh_path: String, batch_name: String) -> int:
	var transforms := []
	var source_mesh: MeshInstance = null

	for pod in criopods:
		if not is_instance_valid(pod):
			continue
		var mesh_node = null
		if mesh_path == "Criopod" and pod is MeshInstance:
			mesh_node = pod
		else:
			mesh_node = pod.get_node_or_null(mesh_path)
		if not (mesh_node and mesh_node is MeshInstance):
			continue
		if mesh_node.mesh == null:
			continue
		if source_mesh == null:
			source_mesh = mesh_node

		var local_xform = batch_root.global_transform.affine_inverse() * mesh_node.global_transform
		transforms.append(local_xform)

	if source_mesh == null or transforms.empty():
		return 0

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source_mesh.mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance.new()
	mmi.name = batch_name
	mmi.multimesh = mm
	if source_mesh.material_override:
		mmi.material_override = source_mesh.material_override
	elif source_mesh.get_surface_material(0):
		mmi.material_override = source_mesh.get_surface_material(0)
	batch_root.add_child(mmi)

	return transforms.size()

func _hide_criopod_visuals(pod: Node) -> void:
	"""Free visual meshes on a criopod but keep collision bodies."""
	if pod.has_node("Criopod"):
		var mesh = pod.get_node("Criopod")
		if mesh is MeshInstance:
			mesh.queue_free()
	if pod.has_node("RotatingObjectV2/Glass"):
		var glass = pod.get_node("RotatingObjectV2/Glass")
		if glass is MeshInstance:
			glass.queue_free()
	if pod.has_node("PersonCard2"):
		var pilot = pod.get_node("PersonCard2")
		if pilot is MeshInstance:
			pilot.queue_free()
	# Note: RotatingObjectV2 (KinematicBody) and StaticBody collision shapes are preserved

func _is_criopod_batch_node(node: Node) -> bool:
	return node and String(node.name).begins_with("CriopodBatch")

func _is_criopod_instance_node(node: Node) -> bool:
	if not (node and node is Spatial):
		return false
	if _is_criopod_batch_node(node):
		return false
	if not ("Criopod" in String(node.name)):
		return false
	if node is MeshInstance and node.mesh != null:
		return true
	return node.get_node_or_null("Criopod") != null

func _sort_nodes_by_name(a: Node, b: Node) -> bool:
	return String(a.name) < String(b.name)

func _capture_scatter_blueprints(parent: Node, only_pushable_boxes: bool) -> Array:
	var blueprints := []
	for child in parent.get_children():
		if not (child is Spatial):
			continue
		if _is_criopod_batch_node(child):
			continue
		if only_pushable_boxes and not ("PushableBox" in child.name):
			continue
		var entry = {
			"name": child.name,
			"transform": child.transform,
			"groups": child.get_groups()
		}
		blueprints.append(entry)
	return blueprints

func _start_threaded_scatter_preload() -> void:
	if _scatter_preload_thread != null:
		return
	_scatter_preload_done = false
	_scatter_preload_data = {}
	_scatter_preload_thread = Thread.new()
	_scatter_preload_worker = ScatterPreloadWorker.new()
	var err = _scatter_preload_thread.start(_scatter_preload_worker, "run")
	if err != OK:
		printerr("[OptionalNodeManager] Failed to start scatter preload thread: ", err)
		_scatter_preload_thread = null
		_scatter_preload_worker = null
		_scatter_preload_done = true

func _wait_for_scatter_preload():
	# Always yield at least one frame so callers can safely yield on this method.
	yield (get_tree(), "idle_frame")

	if _scatter_preload_done:
		return

	if _scatter_preload_thread != null:
		_scatter_preload_data = _scatter_preload_thread.wait_to_finish()
		_scatter_preload_thread = null
	_scatter_preload_worker = null
	_scatter_preload_done = true

func _spawn_scatter_blueprints(parent_name: String, blueprints: Array, packed_scene: Resource, batch_size: int):
	# Always yield at least one frame so callers can safely yield on this method.
	yield (get_tree(), "idle_frame")

	var parent = _get_scatter_node(parent_name)
	if not parent:
		printerr("[OptionalNodeManager] Missing scatter parent: ", parent_name)
		return

	parent.visible = true

	if packed_scene == null:
		# Fallback to sync load if thread was disabled/failed.
		var fallback_path = THREAD_SCATTER_BOX_SCENE_PATH
		if parent_name == "Scatter3D2":
			fallback_path = THREAD_SCATTER_CRIOPOD_SCENE_PATH
		packed_scene = ResourceLoader.load(fallback_path)
		if packed_scene == null:
			printerr("[OptionalNodeManager] Missing packed scene for ", parent_name, ". Skipping threaded spawn.")
			return

	var per_batch = max(1, batch_size)
	var spawned = 0
	for blueprint in blueprints:
		var inst = packed_scene.instance()
		if inst == null:
			continue

		inst.name = String(blueprint.get("name", inst.name))
		parent.add_child(inst)
		if inst is Spatial:
			inst.transform = blueprint.get("transform", Transform.IDENTITY)
		for group_name in blueprint.get("groups", []):
			if not inst.is_in_group(group_name):
				inst.add_to_group(group_name)

		spawned += 1
		if spawned % per_batch == 0:
			yield (get_tree(), "idle_frame")
			if THREAD_SCATTER_BATCH_DELAY_SEC > 0.0:
				yield (get_tree().create_timer(THREAD_SCATTER_BATCH_DELAY_SEC), "timeout")

	if spawned == 0 and not blueprints.empty():
		printerr("[OptionalNodeManager] Failed to spawn blueprints for ", parent_name)

func _activate_boxes_gradually() -> void:
	var boxes = _get_stack_candidate_boxes()
	
	# Sort by Y position (bottom first)
	boxes.sort_custom(self , "_sort_boxes_by_height")
	
	print("[OptionalNodeManager] Activating ", boxes.size(), " boxes gradually...")
	
	# Activate one by one, waiting for settle
	for i in range(boxes.size()):
		var box = boxes[i]
		if box and is_instance_valid(box):
			# Wake up the box (enable physics)
			box.sleeping = false
			box.mode = RigidBody.MODE_RIGID
			print("[OptionalNodeManager] Activated box ", i + 1, "/", boxes.size())
			
			# Wait for this box to settle before activating next
			# Check if velocity is near zero
			var settled_frames = 0
			var max_wait = 60 # Max 60 frames (~1 second)
			while settled_frames < 15 and max_wait > 0:
				yield (get_tree(), "idle_frame")
				if box.get_linear_velocity().length() < 0.1:
					settled_frames += 1
				else:
					settled_frames = 0
				max_wait -= 1
	
	print("[OptionalNodeManager] All boxes activated!")

func _sort_boxes_by_height(a, b) -> bool:
	return a.global_transform.origin.y < b.global_transform.origin.y

func _arrange_boxes_in_stacks() -> void:
	# Arrange boxes in neat stacks so they don't fall
	# And start them in sleeping state
	# Target only optional/scatter pushable boxes to avoid touching gameplay-critical tests.
	var boxes = _get_stack_candidate_boxes()
	
	if boxes.size() < BOX_STACK_MIN_COUNT:
		_stacked_box_paths.clear()
		_stacked_boxes_cache.clear()
		_box_watchdog_cursor = 0
		return
	
	# Sort by original Z, then X
	boxes.sort_custom(self , "_sort_boxes_original")
	
	# Stack configuration - boxes are 2x2x2m
	var stack_x = 5.0
	var stack_z = -25.0
	var stack_spacing = 3.0
	var boxes_per_stack = 3
	var box_gap = BOX_STACK_GAP
	
	_stacked_box_paths.clear()
	_stacked_boxes_cache.clear()
	_box_watchdog_cursor = 0
	var idx = 0
	for box in boxes:
		if not is_instance_valid(box):
			continue
		var stack_idx = idx / boxes_per_stack
		var height_idx = idx % boxes_per_stack
		
		var x = stack_x + (stack_idx * stack_spacing)
		var y = 1.0 + (height_idx * box_gap) # Box center at y=1 when on ground
		var z = stack_z
		
		box.global_transform.origin = Vector3(x, y, z)
		box.rotation = Vector3.ZERO
		box.rotation_degrees = Vector3.ZERO
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		
		# Start fully settled: kinematic (no physics integration) until explicit wake-up.
		box.sleeping = true
		box.mode = RigidBody.MODE_KINEMATIC
		if "wake_check_interval_frames" in box:
			box.wake_check_interval_frames = max(int(box.wake_check_interval_frames), BOX_STACK_WAKE_CHECK_INTERVAL_FRAMES)
		_stacked_box_paths.append(box.get_path())
		_stacked_boxes_cache.append(box)
		
		idx += 1
	
	print("[OptionalNodeManager] Arranged ", boxes.size(), " boxes in stacks (sleeping/kinematic)")

func _sort_boxes_original(a, b) -> bool:
	return (a.global_transform.origin.z < b.global_transform.origin.z or
		(a.global_transform.origin.z == b.global_transform.origin.z and
		 a.global_transform.origin.x < b.global_transform.origin.x))

func _start_box_watchdog() -> void:
	if _box_watchdog_running:
		return
	_box_watchdog_running = true
	call_deferred("_box_watchdog_loop")

func _box_watchdog_loop() -> void:
	while _box_watchdog_running and is_inside_tree():
		yield (get_tree().create_timer(BOX_WATCHDOG_INTERVAL_SEC), "timeout")
		_wake_misplaced_boxes_incremental(BOX_WATCHDOG_CHECKS_PER_TICK)

func _start_decorative_rigidbody_culling() -> void:
	if _decor_rb_culling_running:
		return
	_decor_rb_culling_running = true
	call_deferred("_decorative_rigidbody_culling_loop")

func _decorative_rigidbody_culling_loop() -> void:
	while _decor_rb_culling_running and is_inside_tree():
		yield (get_tree().create_timer(DECOR_RB_CULL_INTERVAL_SEC), "timeout")
		_apply_decorative_rigidbody_distance_culling(DECOR_RB_CULL_BATCH_PER_TICK)

func _wake_misplaced_boxes_incremental(max_checks: int) -> int:
	var boxes = _get_stacked_boxes()
	if boxes.empty():
		_box_watchdog_cursor = 0
		return 0

	var player = _resolve_player_node()
	var culling_enabled = _is_decorative_rigidbody_culling_enabled() and is_instance_valid(player)
	var freeze_radius = _get_decorative_rigidbody_freeze_radius()
	var checks = boxes.size()
	if max_checks > 0:
		checks = min(checks, max_checks)

	var woken := 0
	for i in range(checks):
		var idx = (_box_watchdog_cursor + i) % boxes.size()
		var box = boxes[idx]
		if not is_instance_valid(box):
			continue
		if culling_enabled and _should_freeze_box_for_distance(box, player, freeze_radius):
			_set_decorative_box_forced_sleep(box, true)
			continue
		_set_decorative_box_forced_sleep(box, false)
		if box.mode != RigidBody.MODE_KINEMATIC:
			continue
		if _box_needs_wakeup(box):
			box.mode = RigidBody.MODE_RIGID
			box.sleeping = false
			woken += 1

	_box_watchdog_cursor = (_box_watchdog_cursor + checks) % boxes.size()
	if woken > 0:
		print("[OptionalNodeManager] Auto-woke ", woken, " misplaced stacked boxes (incremental)")
	return woken

func _wake_misplaced_boxes() -> int:
	var player = _resolve_player_node()
	var culling_enabled = _is_decorative_rigidbody_culling_enabled() and is_instance_valid(player)
	var freeze_radius = _get_decorative_rigidbody_freeze_radius()
	var woken := 0
	for box in _get_stacked_boxes():
		if not is_instance_valid(box):
			continue
		if culling_enabled and _should_freeze_box_for_distance(box, player, freeze_radius):
			_set_decorative_box_forced_sleep(box, true)
			continue
		_set_decorative_box_forced_sleep(box, false)
		if box.mode != RigidBody.MODE_KINEMATIC:
			continue
		if _box_needs_wakeup(box):
			box.mode = RigidBody.MODE_RIGID
			box.sleeping = false
			woken += 1
	if woken > 0:
		print("[OptionalNodeManager] Auto-woke ", woken, " misplaced stacked boxes")
	return woken

func _get_stacked_boxes() -> Array:
	var boxes_from_cache := []
	for box in _stacked_boxes_cache:
		if box and is_instance_valid(box):
			boxes_from_cache.append(box)
	if not boxes_from_cache.empty():
		if boxes_from_cache.size() != _stacked_boxes_cache.size():
			_stacked_boxes_cache = boxes_from_cache.duplicate()
		return boxes_from_cache

	var boxes := []
	for path in _stacked_box_paths:
		var node = get_node_or_null(path)
		if node and node is RigidBody:
			boxes.append(node)
	_stacked_boxes_cache = boxes.duplicate()
	return boxes

func _box_needs_wakeup(box: RigidBody) -> bool:
	var up_dot = abs(box.global_transform.basis.y.normalized().dot(Vector3.UP))
	if up_dot < BOX_TILT_MIN_DOT:
		return true
	
	var half_height := 1.0
	var shape_node = box.get_node_or_null("CollisionShape")
	if shape_node and shape_node is CollisionShape and shape_node.shape and shape_node.shape is BoxShape:
		half_height = shape_node.shape.extents.y
	
	var from = box.global_transform.origin
	var to = from + Vector3.DOWN * (half_height + BOX_SUPPORT_RAY_EXTRA)
	var hit = box.get_world().direct_space_state.intersect_ray(from, to, [box], box.collision_mask, true, false)
	return hit.empty()

func _get_stack_candidate_boxes() -> Array:
	if not _candidate_boxes_dirty and not _candidate_boxes_cache.empty():
		return _candidate_boxes_cache
		
	var boxes := []
	var seen := {}
	
	for node in get_tree().get_nodes_in_group("pushable_box"):
		_try_add_stack_candidate(node, boxes, seen)
	
	for node in get_tree().get_nodes_in_group("scatter"):
		if node:
			_collect_stack_candidates(node, boxes, seen)
	
	_candidate_boxes_cache = boxes
	_candidate_boxes_dirty = false
	return boxes

func _collect_stack_candidates(node: Node, boxes: Array, seen: Dictionary) -> void:
	if not node:
		return
	_try_add_stack_candidate(node, boxes, seen)
	for child in node.get_children():
		_collect_stack_candidates(child, boxes, seen)

func _try_add_stack_candidate(node: Node, boxes: Array, seen: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	if not (node is RigidBody):
		return
	if not _is_pushable_box_node(node):
		return
	if not (_is_optional_or_under_optional(node) or _is_under_group(node, "scatter") or _is_under_named_ancestor(node, ["Scatter3D", "Scatter3D2"])):
		return
	var instance_id = node.get_instance_id()
	if seen.has(instance_id):
		return
	seen[instance_id] = true
	boxes.append(node)

func _is_pushable_box_node(node: Node) -> bool:
	return node.is_in_group("pushable_box") or "PushableBox" in node.name

func _is_under_group(node: Node, group_name: String) -> bool:
	var current: Node = node
	while current != null:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false

func _is_under_named_ancestor(node: Node, ancestor_names: Array) -> bool:
	var current: Node = node
	while current != null:
		if ancestor_names.has(String(current.name)):
			return true
		current = current.get_parent()
	return false

func _resolve_player_node() -> Spatial:
	if is_instance_valid(_cached_player):
		return _cached_player
	var players = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if candidate is Spatial and is_instance_valid(candidate):
			_cached_player = candidate
			return _cached_player
	return null

func _is_decorative_rigidbody_culling_enabled() -> bool:
	var env_value = OS.get_environment("ODISEA_DECOR_RB_CULL").to_lower().strip_edges()
	if env_value in ["0", "false", "no", "off"]:
		return false
	if env_value in ["1", "true", "yes", "on"]:
		return true
	var profile = _get_hardware_profile_value()
	return profile <= PROFILE_MEDIUM or _is_weak_hardware_active()

func _get_hardware_profile_value() -> int:
	var hp = get_node_or_null("/root/HardwareProfile")
	if hp and hp.has_method("get_profile"):
		return int(hp.get_profile())
	return 3

func _get_decorative_rigidbody_freeze_radius() -> float:
	var profile = _get_hardware_profile_value()
	if profile <= PROFILE_LOW:
		return DECOR_RB_FREEZE_RADIUS_LOW
	if profile <= PROFILE_MEDIUM:
		return DECOR_RB_FREEZE_RADIUS_MEDIUM
	return DECOR_RB_FREEZE_RADIUS_HIGH

func _apply_decorative_rigidbody_distance_culling(max_checks: int = DECOR_RB_CULL_BATCH_PER_TICK) -> int:
	if not _is_decorative_rigidbody_culling_enabled():
		return 0
	var player = _resolve_player_node()
	if not is_instance_valid(player):
		return 0
	var boxes = _get_stack_candidate_boxes()
	if boxes.empty():
		_decor_rb_cursor = 0
		return 0

	var checks = boxes.size()
	if max_checks > 0:
		checks = min(checks, max_checks)

	var freeze_radius = _get_decorative_rigidbody_freeze_radius()
	var frozen := 0
	for i in range(checks):
		var idx = (_decor_rb_cursor + i) % boxes.size()
		var box = boxes[idx]
		if not is_instance_valid(box):
			continue
		var should_freeze = _should_freeze_box_for_distance(box, player, freeze_radius)
		_set_decorative_box_forced_sleep(box, should_freeze)
		if should_freeze:
			frozen += 1

	_decor_rb_cursor = (_decor_rb_cursor + checks) % boxes.size()
	return frozen

func _should_freeze_box_for_distance(box: RigidBody, player: Spatial, freeze_radius: float) -> bool:
	if not is_instance_valid(box) or not is_instance_valid(player):
		return false
	return box.global_transform.origin.distance_to(player.global_transform.origin) > freeze_radius

func _set_decorative_box_forced_sleep(box: RigidBody, should_freeze: bool) -> void:
	if not is_instance_valid(box):
		return
	var instance_id = box.get_instance_id()
	if should_freeze:
		var already_frozen = _decor_rb_forced_sleep_ids.has(instance_id)
		if already_frozen and box.mode == RigidBody.MODE_KINEMATIC and box.sleeping:
			return
		if not _decor_rb_forced_sleep_ids.has(instance_id):
			_decor_rb_forced_sleep_ids[instance_id] = true
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.mode = RigidBody.MODE_KINEMATIC
		box.sleeping = true
		box.set_meta(META_DISTANCE_FROZEN, true)
		return
	_decor_rb_forced_sleep_ids.erase(instance_id)
	if box.has_meta(META_DISTANCE_FROZEN):
		box.remove_meta(META_DISTANCE_FROZEN)

func _wake_nearest_distance_frozen_box() -> bool:
	if not _is_decorative_rigidbody_culling_enabled():
		return false
	var player = _resolve_player_node()
	if not is_instance_valid(player):
		return false
	var max_dist_sq = DECOR_RB_INTERACT_WAKE_RADIUS * DECOR_RB_INTERACT_WAKE_RADIUS
	var nearest_box: RigidBody = null
	var nearest_dist_sq = INF
	for box in _get_stack_candidate_boxes():
		if not is_instance_valid(box):
			continue
		if not _decor_rb_forced_sleep_ids.has(box.get_instance_id()):
			continue
		var dist_sq = box.global_transform.origin.distance_squared_to(player.global_transform.origin)
		if dist_sq > max_dist_sq:
			continue
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest_box = box
	if not is_instance_valid(nearest_box):
		return false
	var instance_id = nearest_box.get_instance_id()
	_decor_rb_forced_sleep_ids.erase(instance_id)
	if nearest_box.has_meta(META_DISTANCE_FROZEN):
		nearest_box.remove_meta(META_DISTANCE_FROZEN)
	if nearest_box.has_method("wake_up"):
		nearest_box.call("wake_up")
	else:
		nearest_box.mode = RigidBody.MODE_RIGID
		nearest_box.sleeping = false
	return true

func _hide_scatter_objects() -> void:
	# Wait for scene to load
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	
	# Hide Scatter3D (PushableBoxes)
	var scatter = _get_scatter_node("Scatter3D")
	if scatter:
		scatter.visible = false
		print("[OptionalNodeManager] Hidden Scatter3D")
	
	# Hide Scatter3D2 (Criopods)
	var scatter2 = _get_scatter_node("Scatter3D2")
	if scatter2:
		scatter2.visible = false
		print("[OptionalNodeManager] Hidden Scatter3D2 (Criopods)")
	
	# Also hide zylann scatter
	var zylann_nodes = get_tree().get_nodes_in_group("scatter")
	for node in zylann_nodes:
		if node is Spatial:
			node.visible = false
	if zylann_nodes.size() > 0:
		print("[OptionalNodeManager] Hidden ", zylann_nodes.size(), " scatter nodes")
