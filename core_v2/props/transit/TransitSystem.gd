extends Node

# TransitSystem.gd
# Global coordinator for the pneumatic capsule transit system.

signal travel_started(destination_id, destination_name)
signal travel_completed(destination_id)

var _is_traveling := false

func _ready():
	if not name == "TransitSystem":
		name = "TransitSystem"

func request_travel(destination_id: String, destination_name: String) -> void:
	if _is_traveling:
		return

	_run_travel_sequence(destination_id, destination_name)

func _run_travel_sequence(destination_id: String, destination_name: String) -> void:
	_is_traveling = true
	emit_signal("travel_started", destination_id, destination_name)

	# 1. Get Player and disable input
	var session = get_node_or_null("/root/SessionManager")
	var player = null
	if session:
		player = session.player

	if player and player.has_node("Logic/Movement"):
		player.get_node("Logic/Movement").set_process(false)
		player.get_node("Logic/Movement").set_physics_process(false)

	# 2. Find the pod in the current scene
	var pods = get_tree().get_nodes_in_group("transit_pod")
	var pod = pods[0] if pods.size() > 0 else null

	if pod and player:
		# Cinematic: Camera moves to pod interior
		var tween = Tween.new()
		add_child(tween)

		var cam_rig = player.get_node_or_null("CameraRig")
		if cam_rig:
			var target_transform = pod.camera_anchor.global_transform
			tween.interpolate_property(cam_rig, "global_transform",
				cam_rig.global_transform, target_transform, 1.5,
				Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			tween.start()
			yield(tween, "tween_all_completed")

		# Close pod door
		pod.set_door_open(false)
		yield(get_tree().create_timer(1.0), "timeout")

		tween.queue_free()

	# 3. Cinematic transition (Fade out and Travel time)
	var scene_manager = get_node_or_null("/root/SceneManager")
	var travel_duration = pod.travel_time if pod else 5.0

	if scene_manager:
		var params = {
			"fade_out": 1.0,
			"fade_in": 1.0,
			"loading_message": "VIAJANDO A " + destination_name.to_upper(),
			"show_progress": false,
			"wait_for_fade_out": true,
			"target_spawn_id": "transit_arrival_" + destination_id
		}

		var scene_path = _get_scene_path_for_destination(destination_id)

		# Start scene transition but wait for travel duration first
		# In Godot 3, goto_scene usually handles the fade itself.
		# To simulate travel duration, we can either call it after the timer,
		# or pass it to the transition system if it supports it.
		# Given current SceneManager, we'll wait then call goto_scene.
		yield(get_tree().create_timer(travel_duration), "timeout")
		scene_manager.goto_scene(scene_path, params)

	_is_traveling = false
	emit_signal("travel_completed", destination_id)

func _get_scene_path_for_destination(id: String) -> String:
	match id:
		"spiral_center":
			return "res://scenes/SpiralCenter.tscn"
		"engineering_bay":
			return "res://scenes/EngineeringBay.tscn"
		"north_dome":
			return "res://scenes/NorthDome.tscn"
		_:
			return get_tree().current_scene.filename
