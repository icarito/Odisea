extends Node

# GhostManager.gd
# Handles Ghost Recording, Playback, and Sync Analysis.

const GhostDummyScene = preload("res://core_v2/ghost/GhostDummy.tscn")

var is_ghost_recording := false
var is_playing_ghost := false
var ghost_name := ""
var ghost_buffer := []
var ghost_dummy: Spatial = null
var current_playback_index := 0
var playback_accum_time := 0.0
var loop_playback := false
var _session_recording_owned := false
var _start_buffer_index := 0

# Sync Analysis State
var diff_threshold := 0.5
var last_diff_distance := 0.0
var last_checksum_match := true
var diverging_vars := []
var _ghost_batch := []
const GHOST_BATCH_SIZE := 10

func _ready():
	name = "GhostManager"
	# Register as OYS Actor and survive registry resets during replay/load cycles.
	var session = get_node_or_null("/root/SessionManager")
	if session:
		if session.has_method("register_oys_actor"):
			session.register_oys_actor("GhostManager", self)
		if session.has_signal("oys_registry_reset"):
			session.connect("oys_registry_reset", self, "_on_oys_registry_reset")

func _on_oys_registry_reset() -> void:
	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("register_oys_actor"):
		session.register_oys_actor("GhostManager", self)

# --- CONSOLE COMMANDS (OYS) ---

func ghost_record(name_str: String):
	var session = get_node_or_null("/root/SessionManager")
	if not session:
		printerr("[GhostManager] SessionManager not found!")
		return
	# In replay mode, avoid starting nested recordings that interfere with determinism runner.
	if "is_replaying" in session and session.is_replaying:
		print("[GhostManager] ghost_record ignored during replay mode.")
		return

	ghost_name = name_str
	is_ghost_recording = true
	is_playing_ghost = false
	_start_buffer_index = int(session.buffer.size()) if "buffer" in session else 0

	# If SessionManager is already recording (e.g. determinism runner), piggyback on it.
	# Otherwise start/own a dedicated recording session.
	if session.is_recording:
		_session_recording_owned = false
	else:
		_session_recording_owned = true
		session.start_recording()
	print("[GhostManager] Started recording ghost: ", ghost_name)

func ghost_play(name_str: String):
	loop_playback = false
	_play_ghost_internal(name_str)

func ghost_play_loop(name_str: String):
	loop_playback = true
	_play_ghost_internal(name_str)

func _play_ghost_internal(name_str: String):
	ghost_name = name_str
	var path = "user://captures/" + ghost_name + ".ghost"

	var file = File.new()
	if not file.file_exists(path):
		printerr("[GhostManager] Ghost file not found: ", path)
		return

	file.open(path, File.READ)
	var content = file.get_as_text()
	file.close()

	var parse_result = JSON.parse(content)
	if parse_result.error != OK:
		printerr("[GhostManager] Failed to parse ghost file!")
		return

	var data = parse_result.result
	if not data.has("buffer"):
		printerr("[GhostManager] Invalid ghost file format (missing buffer).")
		return

	ghost_buffer = data["buffer"]
	current_playback_index = 0
	playback_accum_time = 0.0
	is_playing_ghost = true
	is_ghost_recording = false

	_spawn_dummy()
	if loop_playback:
		print("[GhostManager] Started LOOP playback ghost: ", ghost_name)
	else:
		print("[GhostManager] Started playing ghost: ", ghost_name)

func ghost_stop():
	if not is_ghost_recording and not is_playing_ghost:
		return

	var session = get_node_or_null("/root/SessionManager")
	if session:
		if _session_recording_owned:
			if session.is_recording:
				# Keep is_ghost_recording=true until SessionManager save path runs,
				# so save_recording_override() writes user://captures/<name>.ghost.
				session.stop_and_save_recording()
			is_ghost_recording = false
		else:
			# Piggyback mode: save only the segment recorded between ghost_record/ghost_stop.
			if session.is_recording and "buffer" in session and "replay_meta" in session:
				var full_buffer: Array = session.buffer
				var segment := []
				for i in range(_start_buffer_index, full_buffer.size()):
					segment.append(full_buffer[i])
				is_ghost_recording = false
				save_recording_override(segment, session.replay_meta)
			else:
				is_ghost_recording = false
	_session_recording_owned = false
	is_playing_ghost = false
	loop_playback = false

	if is_instance_valid(ghost_dummy):
		ghost_dummy.queue_free()
		ghost_dummy = null
	print("[GhostManager] Stopped.")

func ghost_diff():
	# Explicit diff check request
	if not is_playing_ghost:
		print("[GhostManager] Not playing ghost.")
		return

	print("[GhostManager] Diff Status: Dist=%.4f ChecksumMatch=%s" % [last_diff_distance, last_checksum_match])
	if not last_checksum_match:
		print("  Diverging Vars: ", diverging_vars)
		print("[GhostManager] PAUSING GAME due to diff.")
		get_tree().paused = true

# --- INTEGRATION HOOKS ---

func capture_frame(player: Node) -> Dictionary:
	if not is_ghost_recording:
		return {}
	if not is_instance_valid(player):
		return {}

	var snapshot = {}
	if player.has_method("get_full_snapshot"):
		snapshot = player.get_full_snapshot()

	var checksum = _generate_checksum(snapshot)

	var frame_data = {
		"pos": var2str(player.global_transform.origin),
		"rot": var2str(player.rotation), # Euler or Quat? Using rotation property for simplicity
		"checksum": checksum,
		"snapshot_subset": {
			# Store key vars for debug diff
			"hp": player.get("hp") if "hp" in player else 100,
			"energy": player.get("energy") if "energy" in player else 100,
			"pos": player.global_transform.origin
		}
	}

	# Telemetry Batching for ANNA V2
	_ghost_batch.append(frame_data)
	if _ghost_batch.size() >= GHOST_BATCH_SIZE:
		_flush_ghost_batch()

	return frame_data

func _flush_ghost_batch():
	if _ghost_batch.empty():
		return
	var annav2 = get_node_or_null("/root/ANNAV2")
	if annav2 and annav2.has_method("add_telemetry_data"):
		annav2.add_telemetry_data("ghost_batch", _ghost_batch.duplicate(true))
	_ghost_batch.clear()

func step(_dt: float):
	if not is_playing_ghost:
		return

	if current_playback_index >= ghost_buffer.size():
		if loop_playback and ghost_buffer.size() > 0:
			current_playback_index = 0
		else:
			print("[GhostManager] Ghost playback finished.")
			is_playing_ghost = false
		return

	var frame_data = ghost_buffer[current_playback_index]
	current_playback_index += 1

	if frame_data.has("ghost_data"):
		var g_data = frame_data["ghost_data"]
		_update_dummy(g_data)
		_check_sync(g_data)

func save_recording_override(buffer: Array, meta: Dictionary):
	# Called by SessionManager when saving, if we intercepted the save path logic
	# But simpler: we just let SessionManager save to its path, and we define our own save logic
	# ACTUALLY, SessionManager saves to user://replay_... .
	# We want to save to user://captures/name.ghost.

	var path = "user://captures/" + ghost_name + ".ghost"
	var dir = Directory.new()
	if not dir.dir_exists("user://captures"):
		dir.make_dir_recursive("user://captures")

	var out_data = {
		"meta": meta,
		"buffer": buffer # Contains ghost_data in each frame
	}

	var file = File.new()
	file.open(path, File.WRITE)
	file.store_string(JSON.print(out_data))
	file.close()
	print("[GhostManager] Saved ghost recording to: ", path)

# --- INTERNAL LOGIC ---

func _spawn_dummy():
	if is_instance_valid(ghost_dummy):
		ghost_dummy.queue_free()

	var scene = GhostDummyScene.instance()
	var parent = get_tree().current_scene
	if parent == null:
		parent = get_tree().get_root()
	parent.add_child(scene)
	ghost_dummy = scene

func _update_dummy(data: Dictionary):
	if not is_instance_valid(ghost_dummy):
		return

	var pos = str2var(data.get("pos", "Vector3(0,0,0)"))
	var rot = str2var(data.get("rot", "Vector3(0,0,0)"))

	ghost_dummy.global_transform.origin = pos
	ghost_dummy.rotation = rot

func _check_sync(recorded_data: Dictionary):
	var session = get_node_or_null("/root/SessionManager")
	if not session or not is_instance_valid(session.player):
		return

	var player = session.player
	var current_pos = player.global_transform.origin
	var recorded_pos = str2var(recorded_data.get("pos", "Vector3(0,0,0)"))

	var dist = current_pos.distance_to(recorded_pos)
	last_diff_distance = dist

	# Checksum
	var current_snapshot = {}
	if player.has_method("get_full_snapshot"):
		current_snapshot = player.get_full_snapshot()
	var current_checksum = _generate_checksum(current_snapshot)
	var recorded_checksum = recorded_data.get("checksum", "")

	last_checksum_match = (current_checksum == recorded_checksum)

	# Visual Feedback
	_update_dummy_visuals(dist > diff_threshold or not last_checksum_match)

	if not last_checksum_match:
		# Compare snapshot subsets if available
		var rec_subset = recorded_data.get("snapshot_subset", {})
		diverging_vars.clear()
		for k in rec_subset:
			var rec_val = rec_subset[k]
			var cur_val = null
			if k == "pos": cur_val = player.global_transform.origin
			elif k == "hp": cur_val = player.get("hp") if "hp" in player else null
			elif k == "energy": cur_val = player.get("energy") if "energy" in player else null

			# Simple string compare for diff
			if str(rec_val) != str(cur_val):
				diverging_vars.append("%s: %s vs %s" % [k, str(cur_val), str(rec_val)])

func _update_dummy_visuals(is_desync: bool):
	if not is_instance_valid(ghost_dummy):
		return

	var mesh_inst = ghost_dummy.get_node("GhostDummy")
	if mesh_inst:
		var mat = mesh_inst.get_surface_material(0)
		if not mat:
			mat = mesh_inst.material_override

		if mat and mat is SpatialMaterial:
			if is_desync:
				mat.albedo_color = Color(1, 0, 0, 0.5) # RED
				# Optionally add a flare or particle effect here
			else:
				mat.albedo_color = Color(0, 1, 0, 0.5) # GREEN

func _generate_checksum(state: Dictionary) -> String:
	# Deterministic string representation
	# We rely on JSON print to be somewhat stable, but key order might vary.
	# Better to hash specific keys sorted.
	var keys = state.keys()
	keys.sort()
	var s = ""
	for k in keys:
		var v = state[k]
		if typeof(v) == TYPE_VECTOR3:
			# Round to avoid float jitter
			s += "%s:%.2f,%.2f,%.2f;" % [k, v.x, v.y, v.z]
		elif typeof(v) == TYPE_REAL:
			s += "%s:%.3f;" % [k, v]
		else:
			s += "%s:%s;" % [k, str(v)]

	return s.md5_text()

func _exit_tree() -> void:
	if is_instance_valid(ghost_dummy):
		ghost_dummy.queue_free()
		ghost_dummy = null
