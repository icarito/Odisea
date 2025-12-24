extends Node

signal playback_started(total_frames)
signal playback_stopped
signal playback_failed
signal playback_paused
signal playback_resumed
signal frame_updated(frame_index, total_frames)

onready var ReplayScript = load("res://scripts/replay/Replay.gd")
const REPLAY_GROUP = "replay_track"
const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]
const DRIFT_THRESHOLD = 0.005 # Maximum allowed position difference before correction
const MAX_CORRECTION_DISTANCE = 0.5 # Max distance to correct per frame, use snapping above this
const RESYNC_INTERVAL = 20 # Frames between drift checks and corrections
const DRIFT_CORRECTION_STRENGTH = 400.0 # Strength for smooth correction interpolation
const MIN_DIVERGENCE_TO_CORRECT = 0.01 # Threshold to avoid insignificant corrections
const FIXED_DELTA = 1.0 / 60.0 # Fixed delta for 60 FPS simulation
const IGNORE_THRESHOLD = 0.001 # Ignore micro-drift to eliminate floating
const FAST_LERP_THRESHOLD = 0.05 # Use ultra-fast LERP if between this and SNAP
const SNAP_THRESHOLD = 0.005 # Instant correction threshold (5mm)
const LERP_STRENGTH_ULTRA_FAST = 200.0 # Ultra-fast LERP strength
# const PILOT_STATE_KEY = "@Pilot@10" # REMOVED: Use dynamic player path instead

var current_replay: Resource = null
var current_replay_filename: String = ""
var total_logical_frames: int = 0
var playback_paused: bool = false
var playback_status: String = "Stopped"  # "Playing", "Paused", "Stopped"

var time_accumulator: float = 0.0
var headless: bool = false
var playback_start_time: int = 0
var frame_count: int = 0

var camera_rig: Node = null
var player: Node = null
var player_path: String
var node_key_map := {}
export(int) var replay_hold_frames := 6 # how many frames to hold a non-zero axis during playback
var _hold_counters := {}
var _held_axes := {}

onready var ReplayUtils = load("res://scripts/replay/ReplayUtils.gd")

func _safe_get_player() -> Node:
	# Return the player from PlayerManager when available, otherwise fallback to scene node named "Pilot"
	if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.has_method("get_player"):
		var p = PlayerManager.get_player()
		if p:
			return p
	if get_tree() and get_tree().current_scene:
		var found = get_tree().current_scene.find_node("Pilot", true, false)
		if found:
			return found
	return null

func _ready() -> void:
	process_priority = -100  # Ensure replay logic runs before player physics
	set_physics_process(false)

func _resolve_node(role_id: String) -> Node:
	if role_id == "player":
		# Prefer autoload PlayerManager if present, otherwise fallback
		if typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.has_method("get_player"):
			return PlayerManager.get_player()
		# Fallback: try to find in current scene (node named Pilot)
		if get_tree() and get_tree().current_scene:
			var found = get_tree().current_scene.find_node("Pilot", true, false)
			if found:
				return found
		return null
	elif role_id == "camera" or role_id == "CameraRig":
		return get_tree().current_scene.find_node("CameraRig", true, false)
	else:
		# For other nodes, try to find by name
		return get_tree().current_scene.find_node(role_id, true, false)

func _debug_log(message: String) -> void:
	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if game_globals and game_globals.replay_debug_mode:
		print("[ReplayPlayback] " + message)

func _physics_process(delta: float) -> void:
	frame_count += 1
	# Guard clause: Do nothing if there's no replay loaded or if it's paused.
	if not current_replay or playback_paused:
		return

	# If we have reached the end of the replay, stop playback.
	if InputState.replay_frame >= total_logical_frames:
		stop_playback()
		return

	var frame_data = current_replay.frames[InputState.replay_frame]
	
	print("Replay frame: ", InputState.replay_frame)
	print("Frame data keys: ", frame_data.keys())
	if frame_data.has("inputs"):
		print("Inputs: ", frame_data.inputs)
	
	# Force player state to recorded state for this frame if available
	var recorded_state = null
	for fs in current_replay.frame_states:
		if fs.has("frame_index") and fs["frame_index"] == InputState.replay_frame:
			recorded_state = fs
			break
	if recorded_state:
		for path in recorded_state:
			if path != "frame_index":
				var node = _resolve_node(path)
				if node and node.has_method("get_replay_state"):
					# For drift correction, compare and correct
					var current_state = node.get_replay_state()
					var recorded_node_state = recorded_state[path]
					if not _compare_states(recorded_node_state, current_state):
						print("DETERMINISM TEST FAILED at frame " + str(InputState.replay_frame) + " for " + path)
						print("Recorded: ", recorded_node_state)
						print("Current: ", current_state)
					else:
						_debug_log("Determinism check passed for frame " + str(InputState.replay_frame) + " " + path)

	
	# Apply inputs (for camera and other non-physics systems)
	_apply_inputs_from_frame(frame_data)

	# Periodically check for drift and correct the pilot position
	if frame_count % RESYNC_INTERVAL == 0:
		check_for_drift(frame_data)

	# Note: frame advancement is handled by InputState
	emit_signal("frame_updated", InputState.replay_frame, total_logical_frames)

func start_playback(replay_path: String, is_headless: bool = false) -> void:
	var replay = ReplayScript.new()
	if replay.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		emit_signal("playback_failed")
		return

	current_replay_filename = replay_path.get_file()
	print("Loading replay scene: ", replay.scene_path)
	
	current_replay = replay
	playback_start_time = Time.get_ticks_usec()
	headless = is_headless
	total_logical_frames = len(current_replay.frames)
	if total_logical_frames == 0 and current_replay.frame_states.size() > 0:
		total_logical_frames = current_replay.frame_states.size()
	time_accumulator = 0.0
	
	# Load frames into InputState using its helper to avoid being cleared by set_mode()
	# Optionally preprocess frames to hold short axis pulses so sampling noise
	# from recording doesn't become intermittent during playback.
	var frames_to_load = current_replay.frames
	if replay_hold_frames and replay_hold_frames > 0:
		frames_to_load = _frames_with_hold(current_replay.frames, replay_hold_frames)
		print("[ReplayPlayback] Preprocessed frames with hold=" + str(replay_hold_frames) + ", original=" + str(len(current_replay.frames)) + ", processed=" + str(len(frames_to_load)))
	if InputState.has_method("load_replay"):
		InputState.load_replay(frames_to_load)
	else:
		InputState.recorded_frames = current_replay.frames.duplicate()
		InputState.mode = InputState.Mode.PLAYBACK
		InputState.replay_frame = 0
	InputState.paused = false  # Start playing
	print("Set replay_frame to 0")
	
	# Deterministic setup for regression testing
	Engine.set_physics_jitter_fix(0.0)
	seed(12345)
	
	# Wait for one frame to ensure the entire scene tree is ready.
	# This prevents "node not found" errors when accessing nodes immediately after a scene load.
	if get_tree():
		yield(get_tree(), "idle_frame")

	# Mark global replay state early so deferred spawn/alignment logic
	# in PlayerManager / PlayerController can detect replay mode during spawn.
	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if game_globals:
		game_globals.replay_debug_mode = true
		game_globals.is_replaying = true
	
	# Spawn player if not exists (guard PlayerManager calls)
	var pm_available = (typeof(PlayerManager) != TYPE_NIL and PlayerManager and PlayerManager.has_method("is_spawned"))
	var player_exists = false
	if pm_available:
		player_exists = PlayerManager.is_spawned()
	else:
		if get_tree() and get_tree().current_scene:
			player_exists = get_tree().current_scene.find_node("Pilot", true, false) != null
	if not player_exists:
		var initial_transform = Transform()
		# Find player initial state
		for path in current_replay.initial_states:
			if "Pilot" in path or "Player" in path:
				var state = current_replay.initial_states[path]
				if state.has("global_transform"):
					var gt = state["global_transform"]
					if gt.has("origin"):
						initial_transform.origin = Vector3(gt["origin"]["x"], gt["origin"]["y"], gt["origin"]["z"])
					if gt.has("basis"):
						# Assuming basis is stored as dict with x,y,z vectors
						var basis_dict = gt["basis"]
						var x_vec = Vector3(basis_dict["x"]["x"], basis_dict["x"]["y"], basis_dict["x"]["z"])
						var y_vec = Vector3(basis_dict["y"]["x"], basis_dict["y"]["y"], basis_dict["y"]["z"])
						var z_vec = Vector3(basis_dict["z"]["x"], basis_dict["z"]["y"], basis_dict["z"]["z"])
						initial_transform.basis = Basis(x_vec, y_vec, z_vec)
				break
		if pm_available and PlayerManager.has_method("spawn"):
			PlayerManager.spawn(initial_transform)
		else:
			print("[ReplayPlayback] Warning: PlayerManager unavailable; cannot spawn player. Ensure scene contains player node.")
	
	# Update references after scene change
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		player = _safe_get_player()
		if player:
			player_path = player.name
	
	_prepare_scene_for_playback()
	
	# The playback is loaded and starting to play automatically.
	resume_playback() 
	
	emit_signal("playback_started", total_logical_frames)
	
	# Go to first frame
	seek(0)

func _prepare_scene_for_playback():
	_set_tracked_nodes_physics_process(false)

	# Stop music
	if get_tree() and get_tree().root.has_node("AudioSystem"):
		get_tree().root.get_node("AudioSystem").stop_bgm()
		
	if get_tree() and get_tree().current_scene:
		var pilot = get_tree().current_scene.get_node("Pilot/PlayerInput")
		var scene = get_tree().current_scene
		for path in current_replay.initial_states:
			var node = _resolve_node(path)
			if node:
				_set_node_state(node, current_replay.initial_states[path])
				# Record mapping from resolved node name to recorded key
				node_key_map[node.name] = path
		print("Done setting initial states")
		# Ensure camera yaw/pitch from initial_states are applied BEFORE computing state hash.
		# Some recordings store camera values at top-level keys (camera_yaw/camera_pitch)
		# or inside a 'camera' entry. Apply them now so the subsequent hash check is accurate.
		var yaw_val = null
		var pitch_val = null
		# Look for camera entries in initials
		for key in current_replay.initial_states.keys():
			var kl = str(key).to_lower()
			if kl.find("camera") != -1:
				var camdict = current_replay.initial_states[key]
				if camdict and typeof(camdict) == TYPE_DICTIONARY:
					yaw_val = camdict.get("yaw", yaw_val)
					pitch_val = camdict.get("pitch", pitch_val)
		# Also check top-level camera_yaw/camera_pitch
		if current_replay.initial_states.has("camera_yaw"):
			yaw_val = current_replay.initial_states.get("camera_yaw", yaw_val)
		if current_replay.initial_states.has("camera_pitch"):
			pitch_val = current_replay.initial_states.get("camera_pitch", pitch_val)
		if yaw_val != null and pitch_val != null:
			var applied_cam = false
			# Prefer scene CameraRig
			if get_tree() and get_tree().current_scene:
				var scene_cam = get_tree().current_scene.find_node("CameraRig", true, false)
				if scene_cam and scene_cam.has_method("set_replay_state"):
					scene_cam.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
					applied_cam = true
			# Try player-local CameraRig
			var player_node = _safe_get_player()
			if not applied_cam and player_node:
				var player_cam = player_node.get_node_or_null("CameraRig")
				if player_cam and player_cam.has_method("set_replay_state"):
					player_cam.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
					applied_cam = true
			# Fallback to direct nodes (h/v)
			if not applied_cam and player_node:
				var camroot = player_node.get_node_or_null("Camroot")
				if not camroot:
					camroot = player_node.find_node("Camroot", true, false)
				if camroot:
					var h = camroot.get_node_or_null("h")
					if h:
						h.rotation.y = float(yaw_val)
						var v = h.get_node_or_null("v")
						if v:
							v.rotation.x = float(pitch_val)
						applied_cam = true
			if applied_cam:
				print("[ReplayPlayback] Applied initial camera yaw/pitch before hash check")
		
		# Verify initial state determinism by per-node approximate comparison.
		# Use per-node comparisons (with a small epsilon) rather than relying
		# solely on the stored hash; this avoids false positives due to
		# representation/type differences (ints vs floats) while preserving
		# meaningful drift detection.
		if current_replay.state_hash != "":
			var drift_found := false
			for path in current_replay.initial_states:
				var node = _resolve_node(path)
				if node and node.has_method("get_replay_state"):
					var recorded_node_state = current_replay.initial_states[path]
					var current_node_state = node.get_replay_state()
					if not _compare_states(recorded_node_state, current_node_state, 0.01):
						print("[REPLAY_ERROR] Initial-state mismatch for path: %s" % str(path))
						print("Recorded: ", recorded_node_state)
						print("Current:  ", current_node_state)
						drift_found = true
			# Fall back to hashed check for overall sanity if nothing flagged
			if drift_found:
				print("[REPLAY_ERROR] Drift detectado en estado inicial. Causa probable: aplicación de estado incompleta.")
			else:
				# Generate a combined hash for informational purposes
				var current_state = {}
				for path in current_replay.initial_states:
					var node = _resolve_node(path)
					if node and node.has_method("get_replay_state"):
						current_state[path] = node.get_replay_state()
				var current_hash = ReplayUtils.generate_state_hash(current_state)
				print("[ReplayPlayback] Initial state verified (per-node): %s" % current_hash)
		
		# DEBUG: Log initial orientations
		print("DEBUG INITIAL STATE: initial_states keys: ", current_replay.initial_states.keys())
		var player = _safe_get_player()
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if player:
			print("DEBUG INITIAL STATE: Recorded Player Yaw: ", current_replay.initial_states.get("player", {}).get("rotation", {}).get("y", "N/A"))
			print("DEBUG INITIAL STATE: Actual Player Yaw: ", player.rotation.y)
		if camera_rig and camera_rig.has_method("get_replay_state"):
			var cam_state = camera_rig.get_replay_state()
			print("DEBUG INITIAL STATE: Recorded Camera Yaw: ", current_replay.initial_states.get("camera", {}).get("yaw", "N/A"))
			print("DEBUG INITIAL STATE: Actual Camera Yaw: ", cam_state.get("yaw", "N/A"))

		# Force camera values specifically before processing first frame
		# Moved to start_loaded_playback after player spawn

func start_loaded_playback() -> void:
	print("[ReplayPlayback] >>>>> start_loaded_playback called")
	frame_count = 0

	# Start from frame 0
	InputState.replay_frame = 0

	# Disable camera input
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_method("set_process_input"):
				camera_rig.set_process_input(false)

	# Disable player input to prevent user interference during playback
	var player = _safe_get_player()
	if player:
		player.set_process_input(false)
		player.set_physics_process(true)  # Enable for deterministic simulation
		if get_tree() and get_tree().current_scene:
			player_path = player.name
		if player.has_node("PlayerInput"):
			var player_input = player.get_node("PlayerInput")
			player_input.is_replay_mode = true

	# Force camera values specifically before processing first frame
	# Moved to resume_playback

	# Asegurar física en todos los nodos del grupo replay_track
	if get_tree():
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			node.set_physics_process(true)
			print("[ReplayPlayback] Node in replay_track physics enabled? ", node, node.is_physics_processing())

	playback_status = "Playing"
	playback_start_time = Time.get_ticks_usec()  # Reset start time when playback actually begins
	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if game_globals:
		game_globals.replay_debug_mode = true
		game_globals.is_replaying = true
	resume_playback()

func stop_playback() -> void:
	print("Stopping playback.")
	playback_paused = true
	playback_status = "Stopped"
	
	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)

	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if game_globals:
		game_globals.is_replaying = false

	# Release mouse/camera control to user, but keep player frozen
	InputState.mode = InputState.Mode.LIVE
	InputState.paused = false

	for action in INPUT_ACTIONS:
		Input.action_release(action)

	var player = _safe_get_player()
	if player:
		# Freeze player by disabling physics
		player.set_physics_process(false)
		# Stop animations
		if player.animation_tree:
			player.animation_tree.active = false

	# Release camera control to user
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_method("set_process_input"):
				camera_rig.set_process_input(true)
			if camera_rig.has_method("set_physics_process"):
				camera_rig.set_physics_process(true)

	# Reset player input mode
	if player and player.has_node("PlayerInput"):
		var player_input = player.get_node("PlayerInput")
		player_input.is_replay_mode = false

	if get_tree() and get_tree().root.has_node("AudioSystem"):
		get_tree().root.get_node("AudioSystem").stop_bgm()

	emit_signal("playback_stopped")

func pause_playback() -> void:
	if playback_paused:
		return
	playback_paused = true
	playback_status = "Paused"
	
	# Use a check to prevent error if trying to remove from a group it's not in.
	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)
	InputState.paused = true
	emit_signal("playback_paused")
	set_physics_process(false)

func resume_playback() -> void:
	print("[ReplayPlayback] >>>>> resume_playback called")
	# Allow resume_playback to be called both for resuming from pause
	# and for initial start. Do not early-return when not paused.
	if not is_in_group("playback_active"): # Add to group when playback actually resumes
		add_to_group("playback_active")

	playback_paused = false
	playback_status = "Playing"
	set_physics_process(true)
	InputState.paused = false
	
	# Asegurar física del player activada para playback
	var player = _safe_get_player()
	if player:
		player.set_physics_process(true)  # Always enable physics for input-driven playback with correction
		print("[ReplayPlayback] Player physics enabled for playback")
		# Detect player path dynamically for drift correction
		player_path = player.name
		print("[ReplayPlayback] Detected player path for drift correction: ", player_path)
		# Ensure all physics bodies and collision shapes in the scene are enabled
		_enable_all_physics_and_collisions()
		# Ensure PlayerController does not use debug direct-move mode during normal playback
		if player.has_method("set"):
			player.set("debug_force_direct_move", false)
		
		# Configurar estado inicial una sola vez
		if current_replay.initial_states.has(player_path):
			var initial_data = current_replay.initial_states[player_path]
			
			# 1. RESTAURAR TRANSFORMACIÓN COMPLETA (CRÍTICO) - USE FIXED-POINT FOR DETERMINISM
			if initial_data.has("player_position_fixed"):
				var pos_fixed = initial_data["player_position_fixed"]
				player.global_transform.origin = ReplayUtils.fixed_dict_to_vector3(pos_fixed)
			elif initial_data.has("global_transform"):
				var initial_transform = ReplayUtils.from_json_safe(initial_data["global_transform"])
				player.global_transform = initial_transform
			
			# 2. RESTAURAR BASIS FROM FIXED-POINT
			if initial_data.has("basis_fixed"):
				var basis_fixed = initial_data["basis_fixed"]
				player.global_transform.basis = ReplayUtils.fixed_dict_to_basis(basis_fixed)
			
			# 3. RESTAURAR VELOCIDAD FROM FIXED-POINT
			if initial_data.has("velocity_fixed"):
				var vel_fixed = initial_data["velocity_fixed"]
				player.velocity = ReplayUtils.fixed_dict_to_vector3(vel_fixed)
			elif initial_data.has("velocity"):
				player.velocity = ReplayUtils.from_json_safe(initial_data["velocity"])
			
			# --- AGREGAR ESTA LÍNEA DE DEBUG ---
			print("[ReplayPlayback] INITIAL POS APPLIED: %s" % player.global_transform.origin)
	
	# Force camera values specifically before processing first frame.
	# Be robust: try multiple common camera nodes under the player and scene.
	if player and current_replay.initial_states.has("camera_yaw"):
		var yaw_val = current_replay.initial_states.get("camera_yaw", null)
		var pitch_val = current_replay.initial_states.get("camera_pitch", null)
		if yaw_val != null and pitch_val != null:
			var applied := false
			# 1) Prefer CameraRig under player
			var camnode = player.get_node_or_null("CameraRig")
			if not camnode:
				camnode = player.find_node("CameraRig", true, false)
			if camnode and camnode.has_method("set_replay_state"):
				camnode.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
				applied = true
			# 2) Try generic CameraOrbit/Camroot structures
			if not applied:
				var camroot = player.get_node_or_null("Camroot")
				if not camroot:
					camroot = player.find_node("Camroot", true, false)
				if camroot:
					var h = camroot.get_node_or_null("h")
					if h:
						# h is yaw node, its child v is pitch
						var v = h.get_node_or_null("v") if h else null
						if h:
							h.rotation.y = float(yaw_val)
							if v:
								v.rotation.x = float(pitch_val)
							applied = true
			# 3) Search scene for CameraRig as fallback
			if not applied and get_tree() and get_tree().current_scene:
				var scene_cam = get_tree().current_scene.find_node("CameraRig", true, false)
				if scene_cam and scene_cam.has_method("set_replay_state"):
					scene_cam.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
					applied = true
			if applied:
				print("[ReplayPlayback] Forced camera yaw/pitch from initial_states")
			else:
				print("[ReplayPlayback] WARNING: could not find camera node to apply camera_yaw/camera_pitch")
			# Also schedule a deferred re-apply a couple frames later to beat any late camera initialization
			if get_tree():
				call_deferred("_deferred_reapply_camera_from_initials")

		# Additionally, apply any full camera initial state dictionaries that may
		# include transforms or extra parameters. This ensures the camera starts
		# exactly at the recorded snapshot rather than relying only on mouse deltas
		# or yaw/pitch values.
		for key in current_replay.initial_states.keys():
			var kl = str(key).to_lower()
			if kl.find("camera") != -1:
				var node = _resolve_node(key)
				if node:
					# Use the generic setter which handles transforms/yaw/pitch etc.
					_set_node_state(node, current_replay.initial_states[key])
					print("[ReplayPlayback] Applied full initial camera state for key: %s" % str(key))
	
	emit_signal("playback_resumed")

func _enable_all_physics_and_collisions() -> void:
	# Walk the current scene and make sure physics processing is enabled
	if not get_tree() or not get_tree().current_scene:
		return
	var root = get_tree().current_scene
	# Recursive traversal
	var stack = [root]
	while stack.size() > 0:
		var node = stack.pop_back()
		# Enable physics processing when available
		if node.has_method("set_physics_process"):
			node.set_physics_process(true)
		# If the node is a CollisionShape, ensure it's enabled
		if node.get_class() == "CollisionShape" or node.get_class() == "CollisionShape2D":
			if node.has_method("set_disabled"):
				node.set_disabled(false)
		# For legacy property name 'disabled' that might be direct
		if node.has_meta("disabled"):
			node.set_meta("disabled", false)
		# Push children
		for c in node.get_children():
			if c:
				stack.push_back(c)

func rewind_playback() -> void:
	seek(0)

func seek(frame_idx: int) -> void:
	if not current_replay or frame_idx < 0 or frame_idx >= total_logical_frames:
		return
		
	InputState.replay_frame = frame_idx
	
	time_accumulator = 0.0
	# In a pure input-based system, we can't instantly jump to an arbitrary frame's state.
	# We can only restore the initial state when seeking to the beginning.
	if InputState.replay_frame == 0:
		if get_tree() and get_tree().current_scene:
			for path in current_replay.initial_states:
				var node_name = path.trim_prefix("@")
				var node = get_tree().current_scene.find_node(node_name, true, false)
				if node:
					_set_node_state(node, current_replay.initial_states[path])

	emit_signal("frame_updated", InputState.replay_frame, total_logical_frames)

func step_frame() -> void:
	if InputState.replay_frame < total_logical_frames - 1:
		seek(InputState.replay_frame + 1)

func step_back_frame() -> void:
	if InputState.replay_frame > 0:
		seek(InputState.replay_frame - 1)

func _apply_inputs_from_frame(frame_data: Dictionary) -> void:
	# --- INYECCIÓN DE ESTADO DE STRAFING ---
	if frame_data.has("strafing_active"):
		InputState.is_strafing_mode_active = frame_data.get("strafing_active", false)
	if frame_data.has("strafing_timer"):
		InputState.strafing_timer = frame_data.get("strafing_timer", 0.0)

	# --- CORRECCIÓN FALTANTE: INYECCIÓN DE MOUSE DELTA ---
	if frame_data.has("mouse_delta"):
		var md = frame_data["mouse_delta"]
		if md is Dictionary:
			# Es vital convertir el Diccionario {x, y} a Vector2
			InputState.mouse_delta = Vector2(FixedPoint.from_fixed(md.get("x", 0)), FixedPoint.from_fixed(md.get("y", 0)))
		elif md is Vector2:
			InputState.mouse_delta = md
		else:
			# Handle other cases, like String
			_debug_log("Unexpected mouse_delta type: " + str(typeof(md)) + " value: " + str(md))
			# Don't set InputState.mouse_delta to avoid changing it unexpectedly

	_debug_log("Applying inputs: " + str(frame_data["inputs"]))
	_debug_log("Sprint pressed: " + str(frame_data["inputs"].get("sprint", false)))
	
	# Set InputState actions and axes from frame_data["inputs"]
	if frame_data.has("inputs"):
		var inputs = frame_data["inputs"]
		# AXES: apply hold-smoothing if enabled
		var axes_vals := {"move_x": 0.0, "move_y": 0.0}
		if inputs.has("move_vec") and inputs["move_vec"] is Vector2:
			axes_vals["move_x"] = inputs["move_vec"].x
			axes_vals["move_y"] = inputs["move_vec"].y
		# For compatibility with older recordings that stored axes separately
		if frame_data.has("axes") and frame_data["axes"] is Dictionary:
			axes_vals["move_x"] = float(frame_data["axes"].get("move_x", axes_vals["move_x"]))
			axes_vals["move_y"] = float(frame_data["axes"].get("move_y", axes_vals["move_y"]))

		# Apply hold counters: if axis is non-zero, set hold counter; if zero but counter>0, reuse held value and decrement
		for a in ["move_x", "move_y"]:
			var v = axes_vals.get(a, 0.0)
			if abs(v) > 0.0001:
				_hold_counters[a] = replay_hold_frames
				_held_axes[a] = v
				InputState.axes[a] = v
			else:
				var cnt = int(_hold_counters.get(a, 0))
				if cnt > 0 and _held_axes.has(a):
					InputState.axes[a] = _held_axes[a]
					_hold_counters[a] = cnt - 1
				else:
					InputState.axes[a] = 0.0
		if inputs.has("jump"):
			InputState.actions["jump"] = inputs["jump"]
		if inputs.has("sprint"):
			InputState.actions["run"] = inputs["sprint"]
		if inputs.has("roll"):
			InputState.actions["roll"] = inputs["roll"]
		if inputs.has("attack"):
			InputState.actions["attack"] = inputs["attack"]
		# Add other actions if needed
	
	var player = _safe_get_player()
	if player and player.has_node("PlayerInput"):
		var player_input = player.get_node("PlayerInput")
		player_input.inject_input(frame_data["inputs"])
	else:
		# Fallback to old method if not available
		for action in frame_data["inputs"]:
			if action == "mouse_motion":
				continue
			var value = frame_data["inputs"][action]
			if value is bool:
				if value:
					Input.action_press(action)
				else:
					Input.action_release(action)

	if frame_data["inputs"].has("mouse_motion"):
		var mouse_motion = frame_data["inputs"]["mouse_motion"]
		if mouse_motion is Vector2 and mouse_motion.length_squared() > 0:
			if get_tree() and get_tree().current_scene:
				var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
				if camera_rig and camera_rig.has_method("process_camera_rotation"):
					camera_rig.process_camera_rotation(mouse_motion)
	elif frame_data.has("mouse_delta"):
		var md_dict = frame_data["mouse_delta"]
		if md_dict is Dictionary:
			var mouse_motion = Vector2(FixedPoint.from_fixed(md_dict.get("x", 0)), FixedPoint.from_fixed(md_dict.get("y", 0)))
			if mouse_motion.length_squared() > 0:
				if get_tree() and get_tree().current_scene:
					var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
					if camera_rig and camera_rig.has_method("process_camera_rotation"):
						camera_rig.process_camera_rotation(mouse_motion)
		elif md_dict is Vector2:
			if md_dict.length_squared() > 0:
				if get_tree() and get_tree().current_scene:
					var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
					if camera_rig and camera_rig.has_method("process_camera_rotation"):
						camera_rig.process_camera_rotation(md_dict)
		else:
			_debug_log("Unexpected mouse_delta type in camera processing: " + str(typeof(md_dict)) + " value: " + str(md_dict))

	# --- APLICAR ESTADOS DE FÍSICA NO INPUTABLES ---
	if player and player.external_velocity and frame_data.has("player_external_velocity"):
		player.external_velocity.velocity = ReplayUtils.dict_to_vector3(frame_data["player_external_velocity"])

	if player and frame_data.has("player_gravity_override"):
		player.set("gravity_override", ReplayUtils.dict_to_vector3(frame_data["player_gravity_override"]))

	# --- INYECCIÓN CRÍTICA DE LA VELOCIDAD DE FÍSICA ---
	# REMOVED: Direct velocity injection to allow physics to process inputs naturally
	# The position correction in _sync_pilot_to_frame will keep the player in sync

func _frames_with_hold(orig_frames: Array, hold_frames: int) -> Array:
	# Returns a new frames array where brief axis pulses are expanded (held)
	# for up to `hold_frames` frames to avoid sampling jitter during playback.
	if not orig_frames:
		return orig_frames
	var result := []
	var hold_counters := {"move_x": 0, "move_y": 0}
	var held_axes := {}
	for f in orig_frames:
		var copy = {}
		# duplicate shallowly all keys except we'll replace/ensure `axes` dict
		for k in f.keys():
			copy[k] = f[k]
		# Resolve source axes: prefer explicit `axes`, else try `inputs.move_vec`
		var axes_dict := {"move_x": 0.0, "move_y": 0.0}
		if f.has("axes") and f["axes"] is Dictionary:
			axes_dict["move_x"] = float(f["axes"].get("move_x", 0.0))
			axes_dict["move_y"] = float(f["axes"].get("move_y", 0.0))
		elif f.has("inputs") and f["inputs"].has("move_vec") and f["inputs"]["move_vec"] is Vector2:
			axes_dict["move_x"] = f["inputs"]["move_vec"].x
			axes_dict["move_y"] = f["inputs"]["move_vec"].y
		# Apply hold logic per axis
		for a in ["move_x", "move_y"]:
			var v = axes_dict.get(a, 0.0)
			if abs(v) > 0.0001:
				hold_counters[a] = int(hold_frames)
				held_axes[a] = v
				axes_dict[a] = v
			else:
				var cnt = int(hold_counters.get(a, 0))
				if cnt > 0 and held_axes.has(a):
					axes_dict[a] = held_axes[a]
					hold_counters[a] = cnt - 1
				else:
					axes_dict[a] = 0.0
		# Ensure copy has `axes` replaced with our processed dict
		copy["axes"] = axes_dict
		result.append(copy)
	return result

func check_for_drift(frame_data: Dictionary) -> void:
	print("[DRIFT_DEBUG] check_for_drift called for frame ", InputState.replay_frame)
	if not player:
		print("[DRIFT_DEBUG] No player")
		return
	# Calculate state_index based on snapshot interval
	var state_index = int(InputState.replay_frame / 10.0)
	if state_index < 0:
		state_index = 0
	if state_index >= current_replay.frame_states.size():
		print("[DRIFT_DEBUG] state_index out of range: ", state_index)
		return
	var recorded_state = current_replay.frame_states[state_index]

	# Resolve which key in recorded_state corresponds to the current player node.
	var player_key = node_key_map.get(player.name, null)
	if player_key == null:
		# Try to discover by comparing resolved nodes for keys in the snapshot
		for k in recorded_state.keys():
			if k == "frame_index":
				continue
			var resolved = _resolve_node(k)
			if resolved == player:
				player_key = k
				node_key_map[player.name] = k
				break

	if player_key == null or not recorded_state.has(player_key):
		print("[DRIFT_DEBUG] recorded_state does not have player_path: ", player_path, " mapped_key:", player_key)
		return
	
	var expected_transform_dict = recorded_state[player_key]["global_transform"]
	var expected_transform = ReplayUtils.dict_to_transform(expected_transform_dict)
	if not expected_transform is Transform:
		print("[DRIFT_DEBUG] dict_to_transform failed")
		return
	
	var expected_origin = expected_transform.origin
	var current_origin = player.global_transform.origin
	var divergence = current_origin.distance_to(expected_origin)
	var current_pos = current_origin
	var target_pos = expected_origin
	
	# Detailed logging for debugging
	print("[DRIFT_DEBUG] Frame %s | Divergence: %s | Current Pos: %s | Target Pos: %s" % [InputState.replay_frame, divergence, current_pos, target_pos])
	print("[Drift] Frame: %s | Nodo: %s | Distancia: %s" % [InputState.replay_frame, player.name, divergence])
	
	if divergence <= IGNORE_THRESHOLD:
		# Ignore micro-drift to eliminate floating
		print("[DRIFT_DEBUG] Correction Applied: NONE")
		return
	
	if divergence > MAX_CORRECTION_DISTANCE:
		# Instant snap for large divergences
		player.global_transform = expected_transform
		print("[DRIFT_DEBUG] Correction Applied: SNAP")
	else:
		# Smooth LERP for smaller divergences
		var t = 1.0 - exp(-FIXED_DELTA * LERP_STRENGTH_ULTRA_FAST)
		player.global_transform.origin = player.global_transform.origin.linear_interpolate(expected_transform.origin, t)
		player.global_transform.basis = player.global_transform.basis.slerp(expected_transform.basis, t)
		print("[DRIFT_DEBUG] Correction Applied: LERP")
	
	# Always correct velocity smoothly if position was corrected
	# Use the mapped player key (player_key) rather than the generic player_path
	# and guard against missing entries to avoid invalid dictionary index errors.
	var player_data = null
	if player_key != null and recorded_state.has(player_key):
		player_data = recorded_state[player_key]
	if player_data and typeof(player_data) == TYPE_DICTIONARY and player_data.has("velocity"):
		var expected_velocity = ReplayUtils.dict_to_vector3(player_data["velocity"])
		player.velocity = player.velocity.linear_interpolate(expected_velocity, LERP_STRENGTH_ULTRA_FAST)
	
	# Correct camera/state for non-player nodes
	for path in recorded_state:
		if path == "frame_index":
			continue
		if path == player_key:
			continue
		var node = _resolve_node(path)
		if node and node.has_method("set_replay_state"):
			var recorded_node_state = recorded_state[path]
			node.set_replay_state(recorded_node_state)
			print("[DRIFT_DEBUG] Corrected " + path)

func _apply_smooth_correction(node: Spatial, expected_transform: Transform, lerp_factor: float) -> void:
	var t: float
	if lerp_factor == 1.0:
		t = 1.0  # Snap
	else:
		t = 1.0 - exp(-FIXED_DELTA * lerp_factor)
	node.global_transform.origin = node.global_transform.origin.linear_interpolate(expected_transform.origin, t)
	node.global_transform.basis = node.global_transform.basis.slerp(expected_transform.basis, t)

func _sync_pilot_to_frame(frame_data_state: Dictionary) -> void:
	"""Apply soft drift correction to keep player in sync with recorded state."""
	if not player:
		return
	
	# Get recorded position
	var recorded_transform = frame_data_state.get("global_transform")
	if recorded_transform:
		var recorded_pos = recorded_transform.origin
		var current_pos = player.global_transform.origin
		var divergence = current_pos.distance_to(recorded_pos)
		
		if divergence > MIN_DIVERGENCE_TO_CORRECT:
			if divergence > MAX_CORRECTION_DISTANCE:
				# Snap to position if too far
				player.global_transform.origin = recorded_pos
				_debug_log("Snapped player position due to high divergence: " + str(divergence))
			else:
				# Smooth correction
				var correction_strength = DRIFT_CORRECTION_STRENGTH
				if divergence < FAST_LERP_THRESHOLD:
					correction_strength = LERP_STRENGTH_ULTRA_FAST
				var correction_vector = (recorded_pos - current_pos).normalized() * correction_strength * FIXED_DELTA
				player.global_transform.origin += correction_vector
				_debug_log("Applied drift correction: " + str(correction_vector.length()))
	
	# Optional: Correct rotation if needed
	if frame_data_state.has("rotation"):
		var recorded_rot = frame_data_state["rotation"]
		var current_rot = player.rotation
		var rot_divergence = abs(recorded_rot.y - current_rot.y)
		if rot_divergence > 0.01:  # Small threshold for rotation
			player.rotation.y = lerp(current_rot.y, recorded_rot.y, 0.1)  # Gentle rotation correction

func _set_tracked_nodes_physics_process(enabled: bool) -> void:
	"""Helper function to enable or disable physics for all tracked nodes."""
	var player = _safe_get_player()
	if player:
		player.set_physics_process(enabled)
		print("[ReplayPlayback] _set_tracked_nodes_physics_process: Player physics enabled? ", enabled, player.is_physics_processing())
	if get_tree():
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			node.set_physics_process(enabled)
			print("[ReplayPlayback] _set_tracked_nodes_physics_process: Node ", node, " physics enabled? ", enabled, node.is_physics_processing())

func _set_node_state(node: Node, state: Dictionary) -> void:
	if node.has_method("set_replay_state"):
		node.set_replay_state(state)
		# Force immediate update if available
		if node.has_method("update_camera_transform"):
			node.update_camera_transform()
		_debug_log("[ReplayPlayback] _set_node_state: used set_replay_state on %s" % str(node.name))
		return
	state = ReplayUtils.from_json_safe(state) # Convert the entire state dictionary from JSON-safe types to Godot types
	for key in state:
		if key == "global_transform" and node is Spatial:
			var transform_val = state[key]
			if transform_val is String:
				# Attempt to parse as a standard Godot Transform string (e.g., Transform(1,0,0,...))
				var parsed_val = str2var(transform_val)
				if parsed_val is Transform:
					node.global_transform = parsed_val # Legacy support for old string formats
			elif transform_val is Transform:
				node.global_transform = transform_val
			elif transform_val is Dictionary:
				node.global_transform = ReplayUtils.dict_to_transform(transform_val)
		elif key == "linear_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.linear_velocity = state[key]
			elif state[key] is Dictionary:
				node.linear_velocity = ReplayUtils.dict_to_vector3(state[key])
		elif key == "angular_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.angular_velocity = state[key]
			elif state[key] is Dictionary:
				node.angular_velocity = ReplayUtils.dict_to_vector3(state[key])
		# Support explicit camera yaw/pitch entries stored in initial_states or node states
		elif key == "camera_yaw" and node is Spatial:
			var yaw_val = state.get("camera_yaw", null)
			var pitch_val = state.get("camera_pitch", null)
			if yaw_val != null and pitch_val != null:
				# Prefer high-level API if camera rig provides it
				if node.has_method("set_replay_state"):
					node.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
					_debug_log("[ReplayPlayback] _set_node_state: applied camera yaw/pitch via set_replay_state on %s yaw=%s pitch=%s" % [str(node.name), str(yaw_val), str(pitch_val)])
					return
				# Common explicit CameraOrbit child node (most rigs use a single orbit controller)
				var cam_orbit = node.get_node_or_null("CameraOrbit")
				if cam_orbit:
					# Some CameraOrbit implementations expose yaw/pitch properties
					if cam_orbit.has_variable("yaw"):
						cam_orbit.yaw = float(yaw_val)
					if cam_orbit.has_variable("pitch"):
						cam_orbit.pitch = float(pitch_val)
					# Force an update if method exists
					if cam_orbit.has_method("update_camera_transform"):
						cam_orbit.update_camera_transform()
					_debug_log("[ReplayPlayback] _set_node_state: applied camera yaw/pitch to CameraOrbit on %s yaw=%s pitch=%s" % [str(node.name), str(yaw_val), str(pitch_val)])
					return
				# Fallback to Yaw/Pitch or h/v node layout
				var yaw_node = node.get_node_or_null("Yaw")
				if not yaw_node:
					yaw_node = node.get_node_or_null("h")
				if yaw_node:
					yaw_node.rotation.y = float(yaw_val)
					var pitch_node = yaw_node.get_node_or_null("Pitch")
					if not pitch_node:
						pitch_node = yaw_node.get_node_or_null("v")
					if pitch_node:
						pitch_node.rotation.x = float(pitch_val)
					_debug_log("[ReplayPlayback] _set_node_state: applied camera yaw/pitch via yaw_node on %s yaw=%s pitch=%s" % [str(node.name), str(yaw_val), str(pitch_val)])
		elif key == "camera_pitch" and node is Spatial:
			# handled above when camera_yaw is present; ignore single-key here
			pass

func _compare_states(a, b, epsilon = 0.001):
	# Allow numeric type differences (int vs float) by normalizing here.
	if typeof(a) in [TYPE_REAL, TYPE_INT] and typeof(b) in [TYPE_REAL, TYPE_INT]:
		return abs(float(a) - float(b)) < epsilon

	if typeof(a) != typeof(b):
		# Allow Vector3 represented as Dictionary to compare to Vector3, and vice-versa
		if a is Vector3 and typeof(b) == TYPE_DICTIONARY:
			return _compare_states(ReplayUtils.vector3_to_dict(a), b, epsilon)
		if b is Vector3 and typeof(a) == TYPE_DICTIONARY:
			return _compare_states(a, ReplayUtils.vector3_to_dict(b), epsilon)
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key):
				return false
			if not _compare_states(a[key], b[key], epsilon):
				return false
		return true
	elif a is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _compare_states(a[i], b[i], epsilon):
				return false
		return true
	elif a is Vector3:
		return (a - b).length() < epsilon
	elif a is float:
		return abs(a - b) < epsilon
	else:
		return a == b

func _deferred_reapply_camera_from_initials() -> void:
	# Called deferred to ensure camera rigs initialized, tries multiple fallbacks.
	if not current_replay:
		return
	if not get_tree() or not get_tree().current_scene:
		return
	var yaw_val = null
	var pitch_val = null
	# Search for camera entries in initial_states
	for key in current_replay.initial_states.keys():
		var kl = str(key).to_lower()
		if kl.find("camera") != -1:
			var camdict = current_replay.initial_states[key]
			if camdict and typeof(camdict) == TYPE_DICTIONARY:
				yaw_val = camdict.get("yaw", yaw_val)
				pitch_val = camdict.get("pitch", pitch_val)
	# Also check top-level camera_yaw/camera_pitch
	if current_replay.initial_states.has("camera_yaw"):
		yaw_val = current_replay.initial_states.get("camera_yaw", yaw_val)
	if current_replay.initial_states.has("camera_pitch"):
		pitch_val = current_replay.initial_states.get("camera_pitch", pitch_val)
	if yaw_val == null or pitch_val == null:
		_debug_log("[ReplayPlayback] _deferred_reapply_camera_from_initials: no camera yaw/pitch found in initials")
		return
	var applied = false
	# Try scene CameraRig
	var scene_cam = get_tree().current_scene.find_node("CameraRig", true, false)
	if scene_cam and scene_cam.has_method("set_replay_state"):
		scene_cam.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
		applied = true
	# Try player-local CameraRig
	var player_node = _safe_get_player()
	if player_node:
		var player_cam = player_node.get_node_or_null("CameraRig")
		if player_cam and player_cam.has_method("set_replay_state"):
			player_cam.set_replay_state({"yaw": yaw_val, "pitch": pitch_val})
			applied = true
	# Try direct CameraOrbit fallback
	if not applied and player_node:
		var orbit = player_node.find_node("CameraOrbit", true, false)
		if orbit:
			if orbit.has_variable("yaw"): orbit.yaw = float(yaw_val)
			if orbit.has_variable("pitch"): orbit.pitch = float(pitch_val)
			if orbit.has_method("update_camera_transform"): orbit.update_camera_transform()
			applied = true
	if applied:
		print("[ReplayPlayback] Deferred re-applied camera yaw/pitch: ", yaw_val, pitch_val)
	else:
		print("[ReplayPlayback] Deferred re-apply failed: no suitable camera node found")
