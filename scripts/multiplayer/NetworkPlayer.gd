extends KinematicBody

onready var player_input = $PlayerInput
onready var player_movement = $PlayerMovement
onready var animation_tree = $AnimationTree

# Network properties
puppet var puppet_transform = Transform.IDENTITY
puppet var puppet_velocity = Vector3.ZERO
puppet var puppet_rotation = Vector3.ZERO
puppet var puppet_is_walking = false
puppet var puppet_is_running = false
puppet var puppet_is_jumping = false
puppet var puppet_is_on_floor = true
var velocity = Vector3.ZERO
var rotation = Vector3.ZERO

# Input buffer
var client_inputs = {}

# Interpolation
export var interpolation_speed = 15.0

func _ready():
    if int(name) != get_tree().get_network_unique_id():
        $CameraRig.queue_free()

func _physics_process(delta):
    if not is_network_master(): return

    # This function only runs on the network master (the server in this case)
    var id = int(name)
    if client_inputs.has(id):
        var inputs = client_inputs[id]
        player_input.set_inputs(inputs) # Assumes PlayerInput has a `set_inputs` method

    # Let the existing components handle movement and physics
    player_movement._physics_process(delta)

    # Replicate state to puppets
    rset_unreliable("puppet_transform", global_transform)
    rset_unreliable("puppet_velocity", player_movement.velocity)
    rset_unreliable("puppet_rotation", player_movement.rotation)
    rset_unreliable("puppet_is_walking", player_movement.is_walking)
    rset_unreliable("puppet_is_running", player_movement.is_running)
    rset_unreliable("puppet_is_on_floor", is_on_floor())

func _process(delta):
    if name == str(get_tree().get_network_unique_id()):
        # Collect and send inputs for the server to process
        var inputs = {
            "forward": Input.is_action_pressed("forward"),
            "backward": Input.is_action_pressed("backward"),
            "left": Input.is_action_pressed("left"),
            "right": Input.is_action_pressed("right"),
            "jump": Input.is_action_just_pressed("jump")
        }
        rpc_unreliable_id(1, "receive_input", get_tree().get_network_unique_id(), inputs)
    else:
        # Interpolate puppets
        global_transform = global_transform.interpolate_with(puppet_transform, delta * interpolation_speed)

        # Update animation tree
        animation_tree.set("parameters/conditions/IsWalking", puppet_is_walking)
        animation_tree.set("parameters/conditions/IsRunning", puppet_is_running)
        animation_tree.set("parameters/conditions/IsInAir", not puppet_is_on_floor)

remote func receive_input(player_id, inputs):
    if get_tree().is_network_server():
        client_inputs[player_id] = inputs
