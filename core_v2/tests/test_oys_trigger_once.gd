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

	# Autoload compartido entre suites: se fija el escenario exacto y se restaura.
	var previous := {
		"respawning": session.is_respawning,
		"replaying": session.is_replaying,
		"recording": session.is_recording
	}
	session.is_respawning = true
	session.is_replaying = false
	session.is_recording = false
	trigger._on_zone_entered(player)
	session.is_respawning = bool(previous["respawning"])
	session.is_replaying = bool(previous["replaying"])
	session.is_recording = bool(previous["recording"])

	# El script no corrio, asi que el disparador sigue armado.
	assert_str(trigger.script_file).is_equal(SCRIPT_PATH)
	assert_object(player.get_node_or_null("OYSComponent")).is_null()
