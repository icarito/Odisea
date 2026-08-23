extends GdUnitTestSuite

# test_oys_trigger_once.gd - trigger_once no debe gastarse en una entrada que NO ejecuto
# el script (respawn o replay JSON puro): eso dejaba la cinematica quemada para siempre.

const OYSTriggerScript = preload("res://core_v2/components/OYSTrigger.gd")

const SCRIPT_PATH := "res://core_v2/tests/test_oys_trigger.oys"


func _make_trigger() -> Node:
	var trigger = auto_free(OYSTriggerScript.new())
	trigger.script_file = SCRIPT_PATH
	trigger.trigger_once = true
	add_child(trigger)
	return trigger


func _make_player() -> Node:
	var player: KinematicBody = auto_free(KinematicBody.new())
	player.name = "Pilot_v2"
	player.add_to_group("player")
	add_child(player)
	return player


func test_respawn_entry_does_not_burn_the_trigger() -> void:
	var session = get_node_or_null("/root/SessionManager")
	assert_object(session).is_not_null()

	var trigger = _make_trigger()
	var player = _make_player()

	var was_respawning = session.is_respawning
	session.is_respawning = true
	trigger._on_zone_entered(player)
	session.is_respawning = was_respawning

	# El script no corrio, asi que el disparador sigue armado.
	assert_str(trigger.script_file).is_equal(SCRIPT_PATH)
	assert_object(player.get_node_or_null("OYSComponent")).is_null()


func test_real_entry_runs_the_script_and_burns_the_trigger() -> void:
	var trigger = _make_trigger()
	var player = _make_player()

	trigger._on_zone_entered(player)

	assert_object(player.get_node_or_null("OYSComponent")).is_not_null()
	assert_str(trigger.script_file).is_equal("")
