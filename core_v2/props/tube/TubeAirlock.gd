extends Area

# TubeAirlock.gd - Automatic airlock for pedestrian tubes
# Detects player and triggers scene transition to another dome/spawn point.

export(String) var target_dome := ""
export(String) var target_spawn := ""
export(bool) var auto_open := true

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if target_dome != "":
		_transition_to_target()

func _transition_to_target() -> void:
	var sm = get_node_or_null("/root/SceneManager")
	if sm:
		var params = {
			"target_spawn_id": target_spawn,
			"fade_out": 0.5,
			"fade_in": 0.5,
			"wait_for_fade_out": true
		}
		sm.goto_scene(target_dome, params)
	else:
		printerr("[TubeAirlock] SceneManager not found")

func open_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(true)

func close_doors() -> void:
	var door = get_node_or_null("IrisDoorV2")
	if door and door.has_method("set_active"):
		door.set_active(false)
