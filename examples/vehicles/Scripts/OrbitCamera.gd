extends Spatial

# Control variables
export var maxPitchDeg : float = 45
export var minPitchDeg : float = -45
export var maxZoom : float = 20
export var minZoom : float = 4
export var zoomStep : float = 2
export var zoomYStep : float = 0.15
export var verticalSensitivity : float = 0.002
export var horizontalSensitivity : float = 0.002
export var zoomControllerSensitivity : float = 5.0
export var camYOffset : float = 4.0
export var camLerpSpeed : float = 16.0
export(NodePath) onready var _camTarget = get_node(_camTarget) as Spatial

# Private variables
onready var _springArm : SpringArm = get_node("SpringArm")
onready var _curZoom : float = maxZoom

var _curYoffset : float = camYOffset

func _ready() -> void:
	# make sure rig transform is independant
	set_as_toplevel(true)

func _input(event) -> void:
	if event is InputEventMouseMotion:
		# Rotate the rig around the target using mouse
		rotation.y -= event.relative.x * horizontalSensitivity
		rotation.y = wrapf(rotation.y,0.0,TAU)
		
		rotation.x -= event.relative.y * verticalSensitivity
		rotation.x = clamp(rotation.x, deg2rad(minPitchDeg), deg2rad(maxPitchDeg))
		
	if event is InputEventMouseButton:
		# Change zoom level on mouse wheel rotation
		if event.is_pressed():
			var zoom_amount = 0.0
			if event.button_index == BUTTON_WHEEL_UP:
				zoom_amount = -1.0
			if event.button_index == BUTTON_WHEEL_DOWN:
				zoom_amount = 1.0
			_curZoom += zoom_amount * zoomStep
			camYOffset += zoom_amount * zoomYStep

func _physics_process(delta) -> void:
	# zoom the camera accordingly
	_springArm.spring_length = lerp(_springArm.spring_length, _curZoom, delta * camLerpSpeed)
	
	# set the position of the rig to follow the target
	_curYoffset = lerp(_curYoffset, camYOffset, delta * camLerpSpeed)
	set_translation(_camTarget.global_transform.origin + Vector3(0,_curYoffset,0))
	
	# Rotar la cámara usando el D-Pad del mando
	var dpad_input : Vector2 = Input.get_vector("left", "right", "backward", "forward")
	rotation.y -= dpad_input.x * horizontalSensitivity * 1000 * delta
	rotation.y = wrapf(rotation.y,0.0,TAU)
	rotation.x += dpad_input.y * verticalSensitivity * 1000 * delta
	rotation.x = clamp(rotation.x, deg2rad(minPitchDeg), deg2rad(maxPitchDeg))
	
	# --- Continuous Zoom Input (Controller/Buttons) ---
	var button_zoom_value : float = 0.0
	if Input.is_action_pressed("zoom_in"):
		button_zoom_value = -1.0
	if Input.is_action_pressed("zoom_out"):
		button_zoom_value = 1.0
	
	_curZoom += button_zoom_value * zoomStep * zoomControllerSensitivity * delta
	camYOffset += button_zoom_value * zoomYStep * zoomControllerSensitivity * delta
	_curZoom = clamp(_curZoom, minZoom, maxZoom)
