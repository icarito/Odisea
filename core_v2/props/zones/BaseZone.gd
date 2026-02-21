extends Area
class_name BaseZone

# BaseZone.gd
# Base class for interactive zones.
# Tracks bodies entering and exiting the area, filtering by target groups.

export(Array, String) var target_groups = []
export(bool) var require_all_groups = false
export(bool) var active = true setget set_active

signal zone_entered(body)
signal zone_exited(body)
signal active_changed(is_active)

var _bodies_inside = []

func _ready():
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

	# Initial scan if active start
	if active:
		call_deferred("_initial_scan")

func _initial_scan():
	if not active: return
	var bodies = get_overlapping_bodies()
	for b in bodies:
		_on_body_entered(b)

func set_active(value: bool):
	if active == value:
		return

	active = value
	emit_signal("active_changed", active)

	if active:
		# Re-scan for bodies already inside that might have entered while inactive
		var bodies = get_overlapping_bodies()
		for b in bodies:
			_on_body_entered(b)
	else:
		# When deactivating, we don't necessarily clear bodies,
		# because physically they are still there.
		# But logic relying on 'are_requirements_met' will return false.
		pass

func _on_body_entered(body: Node):
	if not active:
		return

	if not _is_valid_body(body):
		return

	if not body in _bodies_inside:
		_bodies_inside.append(body)
		emit_signal("zone_entered", body)

func _on_body_exited(body: Node):
	# We remove from list regardless of active state to keep list consistent with physics
	# BUT, we only added to list if active was true (or during scan).
	# So if entered while inactive (not added), exit will do nothing (not in list).
	# If entered while active (added), then deactivated, then exit:
	# It is in list. Remove it.

	if body in _bodies_inside:
		_bodies_inside.erase(body)
		if active:
			emit_signal("zone_exited", body)

func _is_valid_body(body: Node) -> bool:
	if target_groups.empty():
		return true

	for group in target_groups:
		if body.is_in_group(group):
			return true

	return false

func are_requirements_met() -> bool:
	if not active:
		return false

	if _bodies_inside.empty():
		return false

	if target_groups.empty() or not require_all_groups:
		return true

	# Check if all required groups are present
	for group in target_groups:
		var group_present = false
		for body in _bodies_inside:
			if body.is_in_group(group):
				group_present = true
				break
		if not group_present:
			return false

	return true
