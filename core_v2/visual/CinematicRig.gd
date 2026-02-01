tool
extends Spatial
class_name CinematicRigV2

# CinematicRig.gd - Specialized camera node for cinematic sequences
# Se registra automáticamente en el grupo "cinematic_rigs" y crea una Camera hija si falta.

export(bool) var auto_play_animation := true
export(String) var animation_name := "intro"

# Transition settings
export(float) var transition_time := 0.5 # 0.0 for cut

var camera: Camera = null
var anim_player: AnimationPlayer = null

func _ready():
	# Siempre registrarse en el grupo (útil para búsquedas legacy)
	if not is_in_group("cinematic_rigs"):
		add_to_group("cinematic_rigs")
	
	_ensure_camera()
	_find_anim_player()

func _ensure_camera():
	"""Busca o crea una Camera hija automáticamente."""
	# Primero buscar en $Camera
	camera = get_node_or_null("Camera") as Camera
	if camera:
		return
	
	# Buscar cualquier Camera hija
	for child in get_children():
		if child is Camera:
			camera = child
			return
	
	# No hay cámara: crear una automáticamente
	camera = Camera.new()
	camera.name = "Camera"
	add_child(camera)
	if Engine.editor_hint:
		camera.owner = get_tree().edited_scene_root

func _find_anim_player():
	"""Busca un AnimationPlayer hijo."""
	anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player:
		return
	
	for child in get_children():
		if child is AnimationPlayer:
			anim_player = child
			return

func activate(force_current: bool = true):
	if not camera:
		_ensure_camera()
	
	if camera and force_current:
		camera.current = true

	if anim_player and auto_play_animation and animation_name != "":
		if anim_player.has_animation(animation_name):
			anim_player.play(animation_name)

func deactivate():
	if anim_player:
		anim_player.stop()

func get_camera() -> Camera:
	if not camera:
		_ensure_camera()
	return camera
