extends Spatial

# test_camera_inversion_path_runner.gd
# Specialized test runner for CinematicPathRig scenarios

const PlayerController = preload("res://core_v2/player/PlayerControllerV2.gd")
const CinematicManagerScript = preload("res://core_v2/autoloads/CinematicManager.gd")

onready var CM = get_node("/root/CinematicManager")

onready var player = $Pilot_v2
onready var zone = $CameraZone
onready var rig = $CameraZone/CinematicPathRig
onready var camera = $CameraZone/CinematicPathRig/PathFollow/Camera

func _ready():
	# Wait for physics initialization
	yield (get_tree().create_timer(0.5), "timeout")
	
	print("\nStarting Camera Inversion Path Test (BaseTerrace Transform)...")
	
	# Validate setup
	print("Zone configured with Rig: ", zone.cinematic_rig_path)
	
	# Simulate entering the zone
	print("Simulating Zone Entry...")
	# Allow physics to process the entry
	yield (get_tree().create_timer(0.2), "timeout")
	
	# Ensure rig is active
	rig.activate(true)
	
	# Force control mode
	CM.current_control_mode = CinematicManagerScript.ControlMode.LOCKED_VIEW
	print("Control Mode forced to LOCKED_VIEW")
	
	# For BaseTerrace, Camera looks West-ish (-X) and slightly North (-Z)
	# Right should point North-ish (-Z).
	
	# Check Camera Basis
	var cam_fwd = - camera.global_transform.basis.z
	var cam_right = camera.global_transform.basis.x
	print("Camera Forward: ", cam_fwd)
	print("Camera Right (Screen Right): ", cam_right)
	
	# Inject Input: RIGHT on Stick (1, 0)
	# User says this moves LEFT on screen (Inverted)
	print("Injecting Input RIGHT (1, 0)...")
	
	var input_vec = Vector2(1, 0)
	var move_dir = player._get_move_direction(input_vec, CinematicManagerScript.ControlMode.LOCKED_VIEW, camera)
	print("Calculated Move Direction: ", move_dir)
	
	# Verify alignment with Camera Right
	var dot = move_dir.dot(cam_right)
	print("Dot(MoveDir, CamRight): ", dot)
	
	if dot > 0.1:
		print("PASS: Movement direction aligns with Camera Right.")
	elif dot < -0.1:
		print("FAIL: Movement is INVERTED (Opposite to Camera Right).")
	else:
		print("FAIL: Movement is Perpendicular or Zero.")

	print("\n--- TEST CASE: UP on Stick (0, 1) ---")
	input_vec = Vector2(0, 1) # Generally "Into Background"
	move_dir = player._get_move_direction(input_vec, CinematicManagerScript.ControlMode.LOCKED_VIEW, camera)
	print("Calculated Move Direction (UP): ", move_dir)
	# Check against Camera Forward (-Z)
	var fwd_dot = move_dir.dot(cam_fwd)
	print("Dot(MoveDir, CamFwd): ", fwd_dot)
	
	if fwd_dot > 0.1:
		print("PASS: Movement (UP) aligns with Camera Forward (Into Screen).")
	elif fwd_dot < -0.1:
		print("FAIL: Movement (UP) is INVERTED (Towards Camera).")
	else:
		print("FAIL: Movement (UP) is weird.")

	get_tree().quit()
