extends Spatial
class_name CircuitTestScene
# CircuitTestScene.gd
# Wrapper script to expose interact() method for OYS validation
# Delegates to the Lever child node

func interact() -> void:
	"""OYS INTERACT command target - delegates to Lever child"""
	var lever = get_node_or_null("Lever")
	if lever and lever.has_method("interact"):
		lever.interact()
	else:
		push_warning("[CircuitTestScene] No Lever with interact() method found")
