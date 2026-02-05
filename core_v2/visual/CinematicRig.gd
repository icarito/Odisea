tool
extends Spatial
class_name CinematicRigV2

# CinematicRig.gd - Specialized camera node for cinematic sequences
# Transitions are handled by CinematicManager, this rig just manages its camera.

signal activated
signal deactivated

export(bool) var auto_play_animation := true
export(String) var animation_name := "intro"

# Transition time hint for CinematicManager
export(float) var transition_time := 0.5

var camera: Camera = null
var anim_player: AnimationPlayer = null
var _is_active := false

# Design-time camera position (captured once at _ready, never modified)
var _design_transform: Transform = Transform()
var _design_fov: float = 70.0

func _ready():
	# Register in group for zone lookups
	if not is_in_group("cinematic_rigs"):
		add_to_group("cinematic_rigs")
	
	_ensure_camera()
	_find_anim_player()
	
	# Capture design-time camera position ONCE at ready
	if camera:
		_design_transform = camera.global_transform
		_design_fov = camera.fov


func _ensure_camera():
	"""Find or create a Camera child."""
	camera = get_node_or_null("Camera") as Camera
	if camera:
		return
	
	for child in get_children():
		if child is Camera:
			camera = child
			return
	
	# No camera: create one
	camera = Camera.new()
	camera.name = "Camera"
	add_child(camera)
	if Engine.editor_hint:
		camera.owner = get_tree().edited_scene_root


func _find_anim_player():
	"""Find an AnimationPlayer child."""
	anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player:
		return
	
	for child in get_children():
		if child is AnimationPlayer:
			anim_player = child
			return


func activate(set_current: bool = true):
	"""Activate this rig. Transitions are handled by CinematicManager."""
	if not camera:
		_ensure_camera()
	
	_is_active = true
	
	# Restore design-time position before activation
	camera.global_transform = _design_transform
	camera.fov = _design_fov
	
	if set_current:
		camera.current = true
	
	# Play animation if configured
	if anim_player and auto_play_animation and animation_name != "":
		if anim_player.has_animation(animation_name):
			anim_player.play(animation_name)
	
	emit_signal("activated")


func deactivate(_restore_camera: bool = true):
	"""Deactivate this rig. Exit transitions are handled by CinematicManager."""
	_is_active = false
	
	if anim_player:
		anim_player.stop()
	
	emit_signal("deactivated")


func get_camera() -> Camera:
	if not camera:
		_ensure_camera()
	return camera


func is_active() -> bool:
	return _is_active
