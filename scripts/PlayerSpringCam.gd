extends Spatial

# Godot 3.6 SpringArm-based third person camera controller
# Node layout expected:
# CameraRig (Spatial with this script)
#  └── Yaw (Spatial)
#       └── Pitch (Spatial)
#            └── SpringArm (SpringArm)
#                 └── Camera (Camera)

export(NodePath) var player_path
export(NodePath) var yaw_path
export(NodePath) var pitch_path
export(NodePath) var springarm_path
export(NodePath) var camera_path

export(float) var yaw_sensitivity := 0.015
export(float) var pitch_sensitivity := 0.015
export(float) var yaw_smooth := 12.0
export(float) var pitch_smooth := 12.0
export(float) var pitch_min := -0.9 # ~ -51.6°
export(float) var pitch_max := 0.4   # ~ 22.9°
export(float) var base_length := 3.8
export(float) var max_length := 5.0
export(float) var zoom_speed := 3.0
export(int) var collision_mask := 2

var player
var yaw
var pitch
var springarm
var cam

var target_yaw := 0.0
var target_pitch := 0.0
var _align_time := 0.4
var _t := 0.0

func _ready():
	if player_path: player = get_node(player_path)
	if yaw_path: yaw = get_node(yaw_path)
	if pitch_path: pitch = get_node(pitch_path)
	if springarm_path: springarm = get_node(springarm_path)
	if camera_path: cam = get_node(camera_path)
	if springarm:
		springarm.spring_length = base_length
		springarm.collision_mask = collision_mask
		# In Godot 3 SpringArm uses current transform forward; leave orientation to yaw/pitch
	# Align initial yaw to player mesh forward if available
	if player and yaw:
		var mesh = null
		# Use get() to safely access property, returns null if missing
		mesh = player.get("player_mesh") if player else null
		if mesh:
			# Player faces +Z in Godot commonly; set yaw to match mesh
			target_yaw = mesh.rotation.y
			yaw.rotation.y = target_yaw
	# Set a sensible default pitch
	if pitch:
		target_pitch = clamp(pitch.rotation.x, pitch_min, pitch_max)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		target_yaw -= event.relative.x * yaw_sensitivity
		target_pitch -= event.relative.y * pitch_sensitivity
		target_pitch = clamp(target_pitch, pitch_min, pitch_max)

func _physics_process(delta):
	# Auto-align yaw to mesh for a brief startup window to avoid odd initial angles
	if player and yaw and _t < _align_time:
		_t += delta
		var m = player.get("player_mesh") if player else null
		if m:
			var py = m.rotation.y
			target_yaw = py
			yaw.rotation.y = py
	# Smooth yaw/pitch
	if yaw:
		var y = yaw.rotation.y
		y += (target_yaw - y) * min(1.0, yaw_smooth * delta)
		yaw.rotation.y = y
	if pitch:
		var p = pitch.rotation.x
		p += (target_pitch - p) * min(1.0, pitch_smooth * delta)
		pitch.rotation.x = p
	# Dynamic zoom based on player horizontal speed
	if player and springarm:
		var hv := Vector3.ZERO
		if player.has_method("get_horizontal_velocity"):
			hv = player.get_horizontal_velocity()
		else:
			# Fallback: if player exposes velocity as property
			hv = player.get("horizontal_velocity") if player else Vector3.ZERO
		var speed := hv.length()
		var target_len = lerp(base_length, max_length, clamp(speed / 8.0, 0.0, 1.0))
		springarm.spring_length = lerp(springarm.spring_length, target_len, min(1.0, zoom_speed * delta))
