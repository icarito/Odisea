tool
extends EditorPlugin

var panel_instance

func _enter_tree():
	panel_instance = preload("res://addons/odyssey_circuit_editor/CircuitBoard.tscn").instance()
	add_control_to_bottom_panel(panel_instance, "Circuit Board")
	# Start hidden, show when LogicCircuitManager is selected
	panel_instance.hide()

func _exit_tree():
	if panel_instance:
		remove_control_from_bottom_panel(panel_instance)
		panel_instance.queue_free()

func handles(object):
	return object is LogicCircuitManager

func make_visible(visible):
	if visible:
		panel_instance.show()
		# Make sure the bottom panel is visible
		make_bottom_panel_item_visible(panel_instance)
	else:
		panel_instance.hide()

func edit(object):
	if object is LogicCircuitManager:
		panel_instance.set_target_manager(object)
		panel_instance.show()
		make_bottom_panel_item_visible(panel_instance)
