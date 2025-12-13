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

# Target Skeleton node.
var _skeleton = null

# Cache for the latest received bone transforms.
# { "bone_name": Transform, ... }
var _target_transforms = {}

# Time since the last packet was received.
var _last_heartbeat = 0.0

# Flag to control the listening process.
var _is_listening = false


# ----- GODOT LIFECYCLE METHODS -----

func _ready():
    _skeleton = get_node_or_null(skeleton_path)
    if not _skeleton:
        push_warning("RemoteSkeletonUDP: Target Skeleton node not found at path: %s" % skeleton_path)
        return

    if auto_start and not Engine.editor_hint:
        start_listening()

func _process(delta):
    if not _is_listening or not _skeleton:
        return

    # Debug feature for manual reset
    if manual_reset_timer > 0:
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
    for bone_name in bone_data:
        var transform_arr = bone_data[bone_name]

        # Validate the incoming data format
        if not transform_arr is Array or transform_arr.size() != 7:
            push_warning("RemoteSkeletonUDP: Invalid data for bone '%s'. Expected 7-float array." % bone_name)
            continue

        var bone_idx = _skeleton.find_bone(bone_name)
        if bone_idx == -1:
            # Silently ignore bones that don't exist in our skeleton
            continue

        # Construct the Transform from the 7-float array
        var translation = Vector3(transform_arr[0], transform_arr[1], transform_arr[2])
        var quat = Quat(transform_arr[3], transform_arr[4], transform_arr[5], transform_arr[6])
        var basis = Basis(quat)

        # Cache the new transform
        _target_transforms[bone_name] = Transform(basis, translation)

func interpolate_transforms(delta):
    """
    Smoothly interpolates the current bone transforms towards the cached
    target transforms using the 'smoothing' factor and applies it to the skeleton.
    """
    # Inverse of smoothing for lerp weight. 0.0 = instant, 1.0 = static.
    var lerp_weight = 1.0 - smoothing

    for bone_name in _target_transforms:
        var bone_idx = _skeleton.find_bone(bone_name)
        if bone_idx == -1:
            continue

        var current_transform = _skeleton.get_bone_pose(bone_idx)
        var target_transform = _target_transforms[bone_name]

        # Interpolate translation and rotation separately
        var new_origin = current_transform.origin.linear_interpolate(target_transform.origin, lerp_weight)
        var new_basis = current_transform.basis.slerp(target_transform.basis, lerp_weight)

        _skeleton.set_bone_pose(bone_idx, Transform(new_basis, new_origin))


func check_heartbeat(delta):
    """
    Checks for connection timeouts. If no packet has been received for
    'heartbeat_timeout' seconds, triggers a reset to T-pose.
    """
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
            # Note: This resets to identity, not the bone's rest pose.
            # For this mocap use case, an identity T-pose is the desired fallback.
            _skeleton.set_bone_pose(bone_idx, Transform())

    # Now clear the cache so they are no longer considered "controlled".
    _target_transforms.clear()
