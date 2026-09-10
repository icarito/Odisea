extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

func test_first_run_defaults_are_off():
	var sm = SettingsManager
	assert_bool(sm != null).is_true()
	# Verify helper method
	assert_bool(sm.has_method("needs_privacy_consent")).is_true()

func test_privacy_consent_dialog_accept():
	var dialog_scene = load("res://core_v2/ui/PrivacyConsentDialog.tscn")
	assert_bool(dialog_scene != null).is_true()
	var dialog = dialog_scene.instance()
	add_child(dialog)

	# Call accept
	dialog._on_accept_pressed()

	assert_bool(SettingsManager.telemetry_enabled).is_true()
	assert_bool(SettingsManager.error_reports_enabled).is_true()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()

func test_privacy_consent_dialog_decline():
	var dialog_scene = load("res://core_v2/ui/PrivacyConsentDialog.tscn")
	assert_bool(dialog_scene != null).is_true()
	var dialog = dialog_scene.instance()
	add_child(dialog)

	# Call decline
	dialog._on_decline_pressed()

	assert_bool(SettingsManager.telemetry_enabled).is_false()
	assert_bool(SettingsManager.error_reports_enabled).is_false()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()
