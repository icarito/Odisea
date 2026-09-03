extends InteractableBaseV2
class_name FreeAirlockDoor

# FreeAirlockDoor.gd - Compuerta de esclusa de dos hojas (modelo importado).
#
# El .glb trae la animacion de apertura horneada ("Take 001"): pestillos, pistones
# hidraulicos y hojas. En vez de reimplementarla, el AnimationPlayer se pone en modo
# MANUAL y se posiciona con seek() desde anim_progress. Asi la animacion sigue siendo
# funcion pura del estado del interactable (determinismo/replay) y no consume proceso
# cuando la puerta esta en reposo.

export(NodePath) var animation_player_path := NodePath("AirlockDoorModel/AnimationPlayer")
export(String) var animation_name := "Take 001"
export(NodePath) var blocker_path := NodePath("DoorBlocker/CollisionShape")
# La animacion mantiene las hojas quietas hasta ~0.62 del recorrido (primero los
# pestillos). Recien pasado este umbral el hueco es transitable.
export(float) var blocker_open_threshold := 0.8

var _anim: AnimationPlayer = null
var _anim_length := 1.0
var _blocker: CollisionShape = null

func _ready() -> void:
	_anim = get_node_or_null(animation_player_path) as AnimationPlayer
	if _anim != null and _anim.has_animation(animation_name):
		_anim_length = _anim.get_animation(animation_name).length
		_anim.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
		_anim.play(animation_name)
	else:
		_anim = null
	_blocker = get_node_or_null(blocker_path) as CollisionShape
	._ready()

func _update_visuals() -> void:
	if _anim != null:
		_anim.seek(clamp(anim_progress, 0.0, 1.0) * _anim_length, true)
	if is_instance_valid(_blocker):
		_blocker.disabled = anim_progress > blocker_open_threshold
