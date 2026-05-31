extends Spatial
class_name TransitPod

# TransitPod.gd
# The pneumatic capsule that transports the player.

export(float) var travel_time := 5.0
export(String) var destination_name := "Centro de la Espiral"

onready var _door = get_node_or_null("Visual/Door")
onready var _tween = get_node_or_null("Tween")
onready var camera_anchor = get_node_or_null("CameraAnchor")

var is_door_open := false

func _ready():
	add_to_group("transit_pod")
	if _door:
		_door.transform.origin = Vector3(0, 0, 1.4) # Starting point for door

	# Close door by default
	set_door_open(false, true)

func set_door_open(open: bool, immediate: bool = false):
	is_door_open = open
	var target_pos = Vector3(1.2, 1.2, 1.4) if open else Vector3(0, 1.2, 1.4)

	if immediate:
		if _door: _door.transform.origin = target_pos
		return

	if _door and _tween:
		_tween.interpolate_property(_door, "transform:origin",
			_door.transform.origin, target_pos, 1.0,
			Tween.TRANS_SINE, Tween.EASE_IN_OUT)
		_tween.start()

func animate_arrival():
	# Simple arrival animation: slide into the station from the tunnel
	var final_transform = global_transform
	global_transform.origin += global_transform.basis.z * 10.0

	if _tween:
		_tween.interpolate_property(self, "global_transform:origin",
			global_transform.origin, final_transform.origin, 2.0,
			Tween.TRANS_SINE, Tween.EASE_OUT)
		_tween.start()
		yield(_tween, "tween_all_completed")
		set_door_open(true)
