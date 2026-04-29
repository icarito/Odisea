extends Node
class_name CircuitTerminalBridge

# CircuitTerminalBridge.gd - Bidirectional bridge between Terminal UI and circuits
# Uses step() pattern from InteractableBaseV2 for deterministic animation

signal terminal_command_executed(command_id, args)
signal circuit_signal_received(node_id, value)
signal bridge_connected()
signal bridge_disconnected()

export(NodePath) var circuit_manager_path := NodePath("")
export(String) var terminal_node_id := "terminal_1"
export(String) var output_node_id := "door_main"
export(bool) var auto_connect := false

var _circuit_manager: LogicCircuitManager = null
var _is_connected := false

var _pending_commands: Array = []
var _command_queue: Array = []

const MAX_PENDING_COMMANDS = 50

func _ready():
	add_to_group("replay_sync")
	
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
		emit_signal("bridge_connected")
		return true
	return false

func disconnect_from_manager() -> void:
	_is_connected = false
	emit_signal("bridge_disconnected")

func is_bridge_connected() -> bool:
	return _is_connected

func connect_output(source_id: String, target_id: String) -> void:
	output_node_id = target_id

func connect_input(circuit_signal: String, callback_name: String) -> void:
	pass

func send_terminal_command(command_id: String, args: Dictionary = {}) -> void:
	if _pending_commands.size() >= MAX_PENDING_COMMANDS:
		_pending_commands.pop_front()
	_pending_commands.append({
		"command": command_id,
		"args": args,
		"time": 0.0
	})
	emit_signal("terminal_command_executed", command_id, args)

func send_to_circuit(value: bool) -> void:
	if not _is_connected or not _circuit_manager or output_node_id == "":
		return
	
	emit_signal("circuit_signal_received", output_node_id, value)
	
	if _circuit_manager.has_method("anna_set_output"):
		_circuit_manager.anna_set_output(output_node_id, value)

func _physics_process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	for cmd in _pending_commands:
		cmd["time"] = float(cmd.get("time", 0.0)) + delta
	
	var ready_commands = []
	var keep_commands = []
	
	for cmd in _pending_commands:
		if float(cmd.get("time", 0.0)) >= 0.016:
			ready_commands.append(cmd)
		else:
			keep_commands.append(cmd)
	
	_pending_commands = keep_commands
	
	for cmd in ready_commands:
		_process_command(String(cmd.get("command", "")), cmd.get("args", {}))

func _process_command(command_id: String, args: Dictionary) -> void:
	match command_id:
		"activate":
			send_to_circuit(true)
		"deactivate":
			send_to_circuit(false)
		"toggle":
			send_to_circuit(true)
			_pending_commands.append({
				"command": "toggle_off",
				"args": {},
				"time": 0.1
			})
		"toggle_off":
			send_to_circuit(false)

func get_snapshot() -> Dictionary:
	var pending_cmds = []
	for cmd in _pending_commands:
		pending_cmds.append({
			"command": String(cmd.get("command", "")),
			"args": cmd.get("args", {}),
			"time": float(cmd.get("time", 0.0))
		})
	return {
		"connected": _is_connected,
		"pending": pending_cmds
	}

func restore_snapshot(data: Dictionary) -> void:
	_is_connected = data.get("connected", false)
	_pending_commands.clear()
	var pending = data.get("pending", [])
	for p in pending:
		_pending_commands.append({
			"command": p.get("command", ""),
			"args": p.get("args", {}),
			"time": p.get("time", 0.0)
		})

func get_manager() -> LogicCircuitManager:
	return _circuit_manager

func get_terminal_node_id() -> String:
	return terminal_node_id

func get_output_node_id() -> String:
	return output_node_id
