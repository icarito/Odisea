extends GdUnitTestSuite

# test_discord_presence.gd
# Tests for Discord Rich Presence Manager and SDK (FD-315)

const DiscordPresenceScript = preload("res://core_v2/autoloads/DiscordPresence.gd")
const DiscordPresenceSDKScript = preload("res://core_v2/autoloads/DiscordPresenceSDK.gd")

var _presence_manager: Node = null

func before_test():
	_presence_manager = DiscordPresenceScript.new()
	add_child(_presence_manager)
	_presence_manager.enable_mock_mode(true)

func after_test():
	if is_instance_valid(_presence_manager):
		_presence_manager.queue_free()

func test_sdk_mock_activity_payload():
	var sdk = _presence_manager.get_sdk()
	assert_object(sdk).is_not_null()

	var activity = {
		"details": "Explorando Domo de Introducción",
		"state": "Sesión #1234 · 60 FPS",
		"timestamps": {"start": 1000}
	}

	var res = sdk.set_activity(activity)
	assert_bool(res).is_true()

	var last_activity = sdk.get_last_mock_activity()
	assert_str(last_activity.get("details")).is_equal("Explorando Domo de Introducción")
	assert_str(last_activity.get("state")).is_equal("Sesión #1234 · 60 FPS")

func test_privacy_gate_without_consent():
	var sm = get_node_or_null("/root/SettingsManager")
	var old_asked = sm.consent_asked if sm else false
	var old_telemetry = sm.telemetry_enabled if sm else false

	if sm:
		sm.consent_asked = false
		sm.telemetry_enabled = false

	assert_bool(_presence_manager.is_presence_allowed()).is_false()

	if sm:
		sm.consent_asked = old_asked
		sm.telemetry_enabled = old_telemetry

func test_presence_allowed_with_consent():
	var sm = get_node_or_null("/root/SettingsManager")
	var old_asked = sm.consent_asked if sm else false
	var old_telemetry = sm.telemetry_enabled if sm else false
	var old_discord = sm.discord_presence_enabled if sm else true

	if sm:
		sm.consent_asked = true
		sm.telemetry_enabled = true
		sm.discord_presence_enabled = true

	assert_bool(_presence_manager.is_presence_allowed()).is_true()

	if sm:
		sm.discord_presence_enabled = false
	assert_bool(_presence_manager.is_presence_allowed()).is_false()

	if sm:
		sm.consent_asked = old_asked
		sm.telemetry_enabled = old_telemetry
		sm.discord_presence_enabled = old_discord

func test_presence_update_formatting():
	var sm = get_node_or_null("/root/SettingsManager")
	var old_asked = sm.consent_asked if sm else false
	var old_telemetry = sm.telemetry_enabled if sm else false
	var old_discord = sm.discord_presence_enabled if sm else true

	if sm:
		sm.consent_asked = true
		sm.telemetry_enabled = true
		sm.discord_presence_enabled = true

	_presence_manager._update_presence()

	var sdk = _presence_manager.get_sdk()
	var last_act = sdk.get_last_mock_activity()

	assert_str(last_act.get("details", "")).is_not_empty()
	assert_str(last_act.get("state", "")).is_not_empty()

	if sm:
		sm.consent_asked = old_asked
		sm.telemetry_enabled = old_telemetry
		sm.discord_presence_enabled = old_discord

func test_clear_presence():
	var sdk = _presence_manager.get_sdk()
	sdk.set_activity({"details": "Test"})
	assert_str(sdk.get_last_mock_activity().get("details", "")).is_equal("Test")

	_presence_manager.clear_presence()
	assert_bool(sdk.get_last_mock_activity().empty()).is_true()
