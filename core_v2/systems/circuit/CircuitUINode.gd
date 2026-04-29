extends Control
class_name CircuitUINode

# CircuitUINode.gd - Connects UI events to the circuit system
# Allows UI elements (buttons, toggles) to send signals to LogicCircuitManager

signal circuit_output(node_id, value)
signal circuit_input_received(node_id, input_id, value)

export(NodePath) var circuit_manager_path := NodePath("")
export(String) var node_id := ""
export(bool) var auto_connect := false

var _circuit_manager: LogicCircuitManager = null
var _is_connected := false

func _ready():
	if not circuit_manager_path.is_empty():
		_circuit_manager = get_node(circuit_manager_path) as LogicCircuitManager
		if _circuit_manager:
			_connect_to_manager()
	
	if auto_connect:
		_auto_find_manager()

func _auto_find_manager() -> void:
	var managers = get_tree().get_nodes_in_group("olcs_manager")
	if managers.size() > 0:
		_circuit_manager = managers[0] as LogicCircuitManager
		if _circuit_manager:
			_connect_to_manager()

func connect_to_circuit_manager(manager: LogicCircuitManager) -> bool:
	_circuit_manager = manager
	return _connect_to_manager()

func _connect_to_manager() -> bool:
	if not _circuit_manager:
		return false
	if _is_connected:
		return true
	
	if _circuit_manager.has_method("anna_inject_input"):
		_is_connected = true
		return true
	return false

func is_circuit_connected() -> bool:
	return _is_connected

func send_output(value: bool) -> void:
	if not _is_connected or not _circuit_manager or node_id == "":
		return
	
	emit_signal("circuit_output", node_id, value)
	
	if _circuit_manager.has_method("anna_set_output"):
		_circuit_manager.anna_set_output(node_id, value)

func send_input(input_id: String, value: bool) -> void:
	if not _is_connected or not _circuit_manager or node_id == "":
		return
	
	emit_signal("circuit_input_received", node_id, input_id, value)
	
	if _circuit_manager.has_method("anna_inject_input"):
		_circuit_manager.anna_inject_input(node_id, input_id, value)

func set_node_id(new_id: String) -> void:
	node_id = new_id

func get_manager() -> LogicCircuitManager:
	return _circuit_manager
