extends BaseZone
class_name SwitchZone

# SwitchZone.gd
# Logic prop that acts as a switch.
# Can be MOMENTARY, TOGGLE, or ONE_SHOT.
# Inherits from BaseZone for detection logic.

enum SwitchMode {
	MOMENTARY,
	TOGGLE,
	ONE_SHOT
}

export(SwitchMode) var switch_mode = SwitchMode.MOMENTARY
export(bool) var is_switched_on = false setget set_is_switched_on

signal switched_on()
signal switched_off()
signal state_changed(is_on)

var _was_requirements_met_last_check = false

func _ready():
	# Register with OYS for scripting access
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		if sm.has_method("register_oys_actor"):
			sm.register_oys_actor(name, self)

	connect("zone_entered", self, "_on_zone_entered_internal")
	connect("zone_exited", self, "_on_zone_exited_internal")
	connect("active_changed", self, "_on_active_changed")

	# Initial state check
	_process_switch_logic()

func _exit_tree():
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		if sm.has_method("unregister_oys_actor"):
			sm.unregister_oys_actor(name)

func set_is_switched_on(value: bool):
	if is_switched_on != value:
		is_switched_on = value
		emit_signal("state_changed", is_switched_on)
		if is_switched_on:
			emit_signal("switched_on")
		else:
			emit_signal("switched_off")

func _on_zone_entered_internal(_body):
	_process_switch_logic()

func _on_zone_exited_internal(_body):
	_process_switch_logic()

func _on_active_changed(_is_active):
	_process_switch_logic()

func _process_switch_logic():
	var req_met = are_requirements_met()

	match switch_mode:
		SwitchMode.MOMENTARY:
			# Direct mapping: requirements met -> ON, else -> OFF
			if req_met and not is_switched_on:
				self.is_switched_on = true
			elif not req_met and is_switched_on:
				self.is_switched_on = false

		SwitchMode.TOGGLE:
			# Edge trigger: transition from NOT met to MET
			if req_met and not _was_requirements_met_last_check:
				self.is_switched_on = not is_switched_on

		SwitchMode.ONE_SHOT:
			# Trigger once -> stay ON -> deactivate zone
			if req_met and not is_switched_on:
				self.is_switched_on = true
				# Disable zone logic to save processing and prevent re-trigger
				self.active = false

	_was_requirements_met_last_check = req_met

# OYS Helper Methods
func get_state() -> bool:
	return is_switched_on

func set_mode(mode_str: String):
	match mode_str.to_upper():
		"MOMENTARY": switch_mode = SwitchMode.MOMENTARY
		"TOGGLE": switch_mode = SwitchMode.TOGGLE
		"ONE_SHOT": switch_mode = SwitchMode.ONE_SHOT
	_process_switch_logic()
