extends ColorRect

signal consent_completed(accepted)

const PRIVACY_URL := "https://odisea.educa.juegos/privacidad"

onready var accept_button: Button = find_node("AcceptButton")
onready var decline_button: Button = find_node("DeclineButton")
onready var privacy_link_button: Button = find_node("PrivacyLinkButton")

func _ready() -> void:
	if accept_button:
		accept_button.connect("pressed", self, "_on_accept_pressed")
		accept_button.grab_focus()
	if decline_button:
		decline_button.connect("pressed", self, "_on_decline_pressed")
	if privacy_link_button:
		privacy_link_button.connect("pressed", self, "_on_privacy_link_pressed")

func _on_accept_pressed() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.telemetry_enabled = true
		sm.error_reports_enabled = true
		sm.consent_asked = true
		sm.save_settings()
		sm.apply_privacy_settings()
	emit_signal("consent_completed", true)
	queue_free()

func _on_decline_pressed() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.telemetry_enabled = false
		sm.error_reports_enabled = false
		sm.consent_asked = true
		sm.save_settings()
		sm.apply_privacy_settings()
	emit_signal("consent_completed", false)
	queue_free()

func _on_privacy_link_pressed() -> void:
	OS.shell_open(PRIVACY_URL)
