tool
extends EditorPlugin

var panel_instance

func _enter_tree():
	panel_instance = preload("res://core_v2/tools/circuit_editor/CircuitBoard.tscn").instance()
	add_control_to_bottom_panel(panel_instance, "Circuit Board")
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
	else:
		panel_instance.hide()

func edit(object):
	if object is LogicCircuitManager:
		panel_instance.set_target_manager(object)
