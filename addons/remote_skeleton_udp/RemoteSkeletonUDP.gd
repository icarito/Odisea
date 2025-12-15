extends Spatial

# RemoteSkeletonUDP: Low-latency motion capture streaming via UDP/JSON.
# Receives pose estimation data from an external source (e.g., Kohai)
# and applies it to a target Skeleton node in real-time.

tool # Allows the script to run in the editor for easier setup.

# ----- EXPORTED VARIABLES (Inspector Panel) -----

# The local UDP port to listen on for incoming data packets.
export(int, 1024, 65535) var udp_port = 5555

# Path to the target Skeleton node in the scene tree.
export(NodePath) var skeleton_path = NodePath("Skeleton3D")

# Linear Interpolation (Lerp) factor applied each frame.
# 0.0 = Instant pose update (max jitter, min latency).
# 1.0 = Maximum smoothing (max latency).
export(float, 0.0, 1.0) var smoothing = 0.1

# If true, the UDP listener starts immediately in _ready().
export var auto_start = true

# Time in seconds. If no packet is received for this duration,
# the skeleton resets to the T-pose (default identity transforms).
export var heartbeat_timeout = 2.0

# Debug feature: If true, prints the raw incoming JSON string to the console.
export var print_packets = false

# Debug feature: Setting this to any value > 0 forces an immediate T-pose reset.
export var manual_reset_timer = 0.0


# ----- PRIVATE VARIABLES -----

# UDP socket handler.
var _udp = PacketPeerUDP.new()
var _save_counter = 0

# Target Skeleton node.
var _skeleton = null

# Cache for the latest received bone transforms.
# { "bone_name": Transform, ... }
var _target_transforms = {}

# Time since the last packet was received.
var _last_heartbeat = 0.0

# Flag to control the listening process.
var _is_listening = false

# Bone name mapping from incoming JSON to Godot skeleton bone names.
var _bone_mapping = {
	"hips": "DEF-hips",
	"chest": "DEF-chest",
	"spine": "DEF-spine",
	"neck": "DEF-neck",
	"head": "DEF-head",
	"shoulder.L": "DEF-shoulderL",
	"elbow.L": "DEF-upper_armL",
	"wrist.L": "DEF-forearmL",
	"shoulder.R": "DEF-shoulderR",
	"elbow.R": "DEF-upper_armR",
	"wrist.R": "DEF-forearmR",
	"upperLeg.L": "DEF-thighL",
	"knee.L": "DEF-shinL",
	"ankle.L": "DEF-footL",
	"upperLeg.R": "DEF-thighR",
	"knee.R": "DEF-shinR",
	"ankle.R": "DEF-footR"
}


# ----- GODOT LIFECYCLE METHODS -----

func _ready():
	print("RemoteSkeletonUDP: _ready() called.")
	set_process_input(true)
	
	_skeleton = get_node_or_null(skeleton_path)
	if not _skeleton:
		push_warning("RemoteSkeletonUDP: Target Skeleton node not found at path: %s" % skeleton_path)
		print("RemoteSkeletonUDP: ABORTING setup. Skeleton node not found at the configured path.")
		return
	
	print("RemoteSkeletonUDP: Skeleton node found: ", _skeleton.name)

	print("running export tpose ****")
	export_tpose_json()

	# Defensively ensure auto_start is not null
	if auto_start == null:
		print("RemoteSkeletonUDP: 'auto_start' is null! Defaulting to true.")
		auto_start = true

	print("RemoteSkeletonUDP: Checking conditions to start listener...")
	print("RemoteSkeletonUDP: auto_start = ", auto_start)
	print("RemoteSkeletonUDP: Engine.editor_hint = ", Engine.editor_hint)

	if auto_start and not Engine.editor_hint:
		print("RemoteSkeletonUDP: Conditions met. Attempting to start listening...")
		start_listening()
	else:
		print("RemoteSkeletonUDP: Conditions not met. Listener will not start automatically.")
		if not auto_start:
			print("RemoteSkeletonUDP: Reason: 'auto_start' is false. Please enable it in the Inspector if you want the listener to start on ready.")
		if Engine.editor_hint:
			print("RemoteSkeletonUDP: Reason: Script is running inside the Godot editor. The listener only starts automatically when the game is played (e.g., by pressing F5).")

func _input(event):
	if event is InputEventKey and event.pressed and event.scancode == KEY_ENTER:
		save_current_pose_json()

# --- DEBUG: Guardar la pose recibida como JSON ---
func save_current_pose_json():
	if not _skeleton:
		print("[POSE_EXPORT] No skeleton found.")
		return
	var pose_dict = {}
	for bone_name in _target_transforms:
		var t = _target_transforms[bone_name]
		var pos = t.origin
		var quat = t.basis.get_rotation_quat()
		pose_dict[bone_name] = [pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w]
	var json = JSON.print(pose_dict, "  ")
	var file = File.new()
	var save_path = "res://result%03d.json" % _save_counter
	_save_counter += 1
	if file.open(save_path, File.WRITE) == OK:
		file.store_string(json)
		file.close()
		print("[POSE_EXPORT] Saved pose JSON to: " + save_path)

func _process(delta):
	if not _is_listening or not _skeleton:
		return

	# Debug feature for manual reset
	if manual_reset_timer != null and manual_reset_timer > 0:
		reset_to_t_pose()
		manual_reset_timer = 0.0
		print("RemoteSkeletonUDP: Manual T-pose reset triggered.")

	process_packets()
	interpolate_transforms(delta)
	check_heartbeat(delta)


# ----- CORE LOGIC -----

func start_listening():
	"""Starts the UDP listening process."""
	if _is_listening:
		return

	var err = _udp.listen(udp_port)
	if err != OK:
		push_error("RemoteSkeletonUDP: Error listening on port %d. Is it in use?" % udp_port)
		return

	_is_listening = true
	_last_heartbeat = 0.0 # Reset heartbeat on start
	print("RemoteSkeletonUDP: Listening on port %d" % udp_port)

func stop_listening():
	"""Stops the UDP listening process."""
	if not _is_listening:
		return

	_udp.close()
	_is_listening = false
	print("RemoteSkeletonUDP: Stopped listening on port %d" % udp_port)

func process_packets():
	"""Reads and processes all available UDP packets in the queue."""
	while _udp.get_available_packet_count() > 0:
		var packet = _udp.get_packet()
		var packet_str = packet.get_string_from_utf8()

		if print_packets:
			print("RemoteSkeletonUDP: Received packet: %s" % packet_str)

		var json = JSON.parse(packet_str)
		if json.error != OK:
			push_warning("RemoteSkeletonUDP: JSON Parse Error: %s" % json.error_string)
			continue

		var data = json.result
		if not data.has("bones"):
			push_warning("RemoteSkeletonUDP: Malformed packet, missing 'bones' key.")
			continue

		apply_bone_data(data["bones"])
		_last_heartbeat = 0.0 # Reset heartbeat on successful packet process

func apply_bone_data(bone_data: Dictionary):
	"""
	Parses the bone data from JSON, constructs Godot Transforms,
	and caches them in the _target_transforms dictionary.
	"""
	if bone_data.has("hips"):
		var hip_arr = bone_data["hips"]
		print("--- SKELETON DEBUG (RECIBIDO) ---")
		print("Hips Recibido: " + str(hip_arr))

	if bone_data.has("wrist.R"):
		var hand_arr = bone_data["wrist.R"]
		print("Wrist.R Recibido: " + str(hand_arr))

	for bone_name in bone_data:
		var transform_arr = bone_data[bone_name]

		# Validate the incoming data format
		if not transform_arr is Array or transform_arr.size() != 7:
			push_warning("RemoteSkeletonUDP: Invalid data for bone '%s'. Expected 7-float array." % bone_name)
			continue

		# Map the incoming bone name to the Godot bone name
		var godot_bone_name = _bone_mapping.get(bone_name, bone_name)

		var bone_idx = _skeleton.find_bone(godot_bone_name)
		if bone_idx == -1:
			print("RemoteSkeletonUDP: Bone '%s' mapped to '%s' not found in skeleton." % [bone_name, godot_bone_name])
			continue

		var translation = Vector3(transform_arr[0], transform_arr[1], transform_arr[2])
		var quat = Quat(transform_arr[3], transform_arr[4], transform_arr[5], transform_arr[6])
		var basis = Basis(quat)

		if godot_bone_name == "DEF-hips":
			# Guardar la posición global para el nodo Spatial
			_target_transforms["_SKELETON_ROOT_POS"] = Transform(Basis(), translation)
			# Solo la rotación local para el bone
			_target_transforms[godot_bone_name] = Transform(basis, Vector3.ZERO)
		else:
			_target_transforms[godot_bone_name] = Transform(basis, translation)

func interpolate_transforms(delta):
	"""
	Smoothly interpolates the current bone transforms towards the cached
	target transforms using the 'smoothing' factor and applies it to the skeleton.
	"""
	# Defensively check for null in case the exported var fails to initialize
	if smoothing == null:
		smoothing = 0.1

	var lerp_weight = 1.0 - smoothing

	# 1. Interpolar y aplicar la posición global del esqueleto (solo si existe)
	if _target_transforms.has("_SKELETON_ROOT_POS"):
		var target_pos = _target_transforms["_SKELETON_ROOT_POS"].origin
		var current_pos = global_transform.origin
		global_transform.origin = current_pos.linear_interpolate(target_pos, lerp_weight)

	# 2. Aplicar poses a los huesos (excepto _SKELETON_ROOT_POS)
	for bone_name in _target_transforms:
		if bone_name == "_SKELETON_ROOT_POS":
			continue
		var bone_idx = _skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
		var current_transform = _skeleton.get_bone_pose(bone_idx)
		var target_transform = _target_transforms[bone_name]
		var new_origin = current_transform.origin.linear_interpolate(target_transform.origin, lerp_weight)
		var new_basis = current_transform.basis.slerp(target_transform.basis, lerp_weight)
		print_debug("BONE_FINAL: %s Rot: %s" % [bone_name, new_basis.get_rotation_quat()])
		_skeleton.set_bone_pose(bone_idx, Transform(new_basis, new_origin))


func check_heartbeat(delta):
	"""
	Checks for connection timeouts. If no packet has been received for
	'heartbeat_timeout' seconds, triggers a reset to T-pose.
	"""
	# Defensively check for null in case the exported var fails to initialize
	if heartbeat_timeout == null:
		heartbeat_timeout = 2.0
		
	_last_heartbeat += delta
	if _last_heartbeat > heartbeat_timeout:
		print("RemoteSkeletonUDP: Heartbeat timeout. Resetting to T-pose.")
		reset_to_t_pose()
		_last_heartbeat = 0.0 # Prevent continuous resetting

func reset_to_t_pose():
	"""
	Resets only the controlled bones to the default T-pose (identity transforms)
	by clearing the target transforms and setting their bone poses to identity.
	"""
	# Iterate over the bones we are currently controlling.
	for bone_name in _target_transforms:
		var bone_idx = _skeleton.find_bone(bone_name)
		if bone_idx != -1:
			# Reset the bone to its defined rest pose, which is the visually correct T-pose.
			_skeleton.set_bone_pose(bone_idx, _skeleton.get_bone_rest(bone_idx))

	# Now clear the cache so they are no longer considered "controlled".
	_target_transforms.clear()

# --- DEBUG: Exportar T-Pose actual del esqueleto en formato JSON ---
func export_tpose_json():
	if not _skeleton:
		print("[TPOSE_EXPORT] No skeleton found.")
		return
	var tpose_dict = {}
	for i in range(_skeleton.get_bone_count()):
		var bone_name = _skeleton.get_bone_name(i)
		var rest = _skeleton.get_bone_rest(i)
		var pos = rest.origin
		var quat = rest.basis.get_rotation_quat()
		tpose_dict[bone_name] = [pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w]
	var json = JSON.print(tpose_dict, "  ")
	print("[TPOSE_EXPORT] JSON (Godot order, Vector3+Quat):\n" + json)
	# Save to file
	var file = File.new()
	var save_path = "res://tpose_export.json"
	if file.open(save_path, File.WRITE) == OK:
		file.store_string(json)
		file.close()
		print("[TPOSE_EXPORT] Saved T-pose JSON to: " + save_path)
		
