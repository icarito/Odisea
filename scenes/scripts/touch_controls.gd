extends CanvasLayer
## Touch Controls Manager
## Manages virtual joysticks for mobile/tablet input

@onready var left_joystick = %LeftJoystick
@onready var right_joystick = %RightJoystick

# Camera sensitivity for the right joystick
@export var camera_sensitivity: float = 2.0

# Reference to the player's camera/head for rotation
var player_head: Node3D = null
var player_neck: Node3D = null
var player: CharacterBody3D = null

func _ready():
	# Hide on desktop by default (will show on touchscreen)
	if not DisplayServer.is_touchscreen_available():
		visible = false
	
	# Wait for parent (player) to be ready
	await get_parent().ready
	
	# Get reference to player and camera
	player = get_parent()
	if player:
		# Try to find the neck and head nodes
		var body = player.get_node_or_null("Body")
		if body:
			player_neck = body.get_node_or_null("Neck")
			if player_neck:
				player_head = player_neck.get_node_or_null("Head")

func _process(delta):
	# Handle camera rotation with right joystick
	if right_joystick and right_joystick.is_pressed and player_head and player_neck:
		var joystick_output = right_joystick.output
		
		# Rotate neck (yaw)
		player_neck.rotate_y(deg_to_rad(-joystick_output.x * camera_sensitivity))
		
		# Rotate head (pitch)
		player_head.rotate_x(deg_to_rad(-joystick_output.y * camera_sensitivity))
		
		# Clamp head rotation
		player_head.rotation.x = clamp(player_head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
