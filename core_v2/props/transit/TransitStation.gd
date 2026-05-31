extends InteractableBaseV2
class_name TransitStation

# TransitStation.gd
# Boarding station for the pneumatic transit system.

export(String) var destination_id := "spiral_center"
export(String) var destination_name := "Centro de la Espiral"

signal capsule_requested(destination_id)

func _ready():
	interaction_text = "Solicitar Cápsula"

	# Try to find and connect to child PedestalButton
	var button = get_node_or_null("PedestalButton")
	if button:
		button.connect("activated", self, "_on_button_activated")

func _on_button_activated():
	emit_signal("capsule_requested", destination_id)
	_request_capsule()

func _request_capsule():
	if debug:
		print("Capsule requested for: ", destination_name)

	# Find a nearby pod and tell it to arrive
	var pods = get_tree().get_nodes_in_group("transit_pod")
	for pod in pods:
		# Simple heuristic: find the closest pod or one already assigned
		if pod.has_method("animate_arrival"):
			pod.animate_arrival()
			break

func interact():
	# If we have a child button, it handles the interaction.
	# Otherwise, we handle it directly.
	if not has_node("PedestalButton"):
		_on_button_activated()
	.interact()
