extends Spatial

# CinematicRig.gd - Specialized camera node for cinematic sequences

export(String) var rig_id := ""
export(bool) var auto_play_animation := true
export(String) var animation_name := "intro"

# Transition settings
export(float) var transition_time := 0.5 # 0.0 for cut

onready var camera: Camera = $Camera
onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")

func _ready():
	add_to_group("cinematic_rigs")
	if not camera:
		# Search for camera if not in $Camera
		for child in get_children():
			if child is Camera:
				camera = child
				break

func activate(force_current: bool = true):
	if camera and force_current:
		camera.current = true

	if anim_player and auto_play_animation and animation_name != "":
		if anim_player.has_animation(animation_name):
			anim_player.play(animation_name)

func deactivate():
	if anim_player:
		anim_player.stop()

func get_camera() -> Camera:
	return camera
