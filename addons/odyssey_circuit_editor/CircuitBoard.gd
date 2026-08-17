tool
extends VBoxContainer

var target_manager: LogicCircuitManager
var graph_edit: GraphEdit
var status_label: Label
var gate_popup: PopupMenu

# Inspector UI references
var side_panel: VBoxContainer
var inspector_container: VBoxContainer
var form: VBoxContainer
var no_selection_label: Label
var id_edit: LineEdit
var type_val_label: Label
var gate_type_row: HBoxContainer
var gate_option: OptionButton
var delay_row: HBoxContainer
var delay_spin: SpinBox
var scene_path_row: VBoxContainer
var path_edit: LineEdit
var pick_btn: Button
var validation_text: TextEdit
var validate_btn: Button
var scene_picker_dialog: ConfirmationDialog
var scene_picker_tree: Tree

# Selected state
var selected_node_id: String = ""

# Store node positions to preserve on refresh
var _node_positions: Dictionary = {}

const COLOR_INPUT := Color(0.2, 0.6, 1.0)
const COLOR_OUTPUT := Color(0.2, 0.9, 0.4)

func _ready():
	graph_edit = $MainSplit/GraphEdit
	status_label = $Toolbar/StatusLabel
	
	side_panel = $MainSplit/SidePanel
	inspector_container = $MainSplit/SidePanel/InspectorContainer
	no_selection_label = $MainSplit/SidePanel/InspectorContainer/NoSelectionLabel
	form = $MainSplit/SidePanel/InspectorContainer/Form
	id_edit = $MainSplit/SidePanel/InspectorContainer/Form/IdRow/IdEdit
	type_val_label = $MainSplit/SidePanel/InspectorContainer/Form/TypeRow/ValLabel
	gate_type_row = $MainSplit/SidePanel/InspectorContainer/Form/GateTypeRow
	gate_option = $MainSplit/SidePanel/InspectorContainer/Form/GateTypeRow/GateOption
	delay_row = $MainSplit/SidePanel/InspectorContainer/Form/DelayRow
	delay_spin = $MainSplit/SidePanel/InspectorContainer/Form/DelayRow/DelaySpin
	scene_path_row = $MainSplit/SidePanel/InspectorContainer/Form/ScenePathRow
	path_edit = $MainSplit/SidePanel/InspectorContainer/Form/ScenePathRow/PathEdit
	pick_btn = $MainSplit/SidePanel/InspectorContainer/Form/ScenePathRow/PickBtn
	validation_text = $MainSplit/SidePanel/ValidationText

	scene_picker_dialog = $ScenePickerDialog
	scene_picker_tree = $ScenePickerDialog/Tree

	# GraphEdit signals
	graph_edit.connect("connection_request", self, "_on_connection_request")
	graph_edit.connect("disconnection_request", self, "_on_disconnection_request")
	graph_edit.connect("node_selected", self, "_on_node_selected")
	graph_edit.connect("node_unselected", self, "_on_node_unselected")
	
	# Toolbar buttons
	$Toolbar/AddPropBtn.connect("pressed", self, "_on_add_prop_pressed")
	$Toolbar/RefreshBtn.connect("pressed", self, "_on_refresh_pressed")
	$Toolbar/ClearBtn.connect("pressed", self, "_on_clear_pressed")
	
	validate_btn = $Toolbar/ValidateBtn
	validate_btn.connect("pressed", self, "run_validation")

	# Gate dropdown menu
	gate_popup = $Toolbar/GateMenu.get_popup()
	gate_popup.connect("id_pressed", self, "_on_gate_selected")
	
	# Gate option setup in form
	gate_option.clear()
	var gate_types = ["AND", "OR", "XOR", "NOT", "DELAY"]
	for gt in gate_types:
		gate_option.add_item(gt)

	# Inspector signals
	id_edit.connect("text_entered", self, "_on_id_edited")
	id_edit.connect("focus_exited", self, "_on_id_focus_exited")
	gate_option.connect("item_selected", self, "_on_gate_type_changed")
	delay_spin.connect("value_changed", self, "_on_delay_changed")
	path_edit.connect("text_entered", self, "_on_path_edited")
	path_edit.connect("focus_exited", self, "_on_path_focus_exited")
	pick_btn.connect("pressed", self, "_on_pick_btn_pressed")
	scene_picker_dialog.connect("confirmed", self, "_on_scene_picker_confirmed")

	# Initial state
	_clear_inspector()
	if status_label:
		status_label.text = "Select a LogicCircuitManager to edit"

func set_target_manager(manager: LogicCircuitManager):
	target_manager = manager
	_node_positions.clear()
	_clear_inspector()
	if status_label:
		if target_manager and target_manager.circuit_data:
			var res_name = target_manager.circuit_data.resource_name
			status_label.text = "Circuit: " + str(res_name if res_name != "" else "Unnamed")
		elif target_manager:
			status_label.text = "Assign a CircuitGraphResource"
		else:
			status_label.text = "No manager selected"
	_refresh_graph()
	run_validation()

func _mark_dirty():
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.emit_changed()
		if target_manager.circuit_data.has_method("property_list_changed_notify"):
			target_manager.circuit_data.property_list_changed_notify()

func _refresh_graph():
	# Save current positions from GraphEdit nodes before clearing
	for child in graph_edit.get_children():
		if child is GraphNode:
			_node_positions[child.name] = child.offset
	
	graph_edit.clear_connections()
	for child in graph_edit.get_children():
		if child is GraphNode:
			graph_edit.remove_child(child)
			child.queue_free()

	if not target_manager or not target_manager.circuit_data:
		return

	var data = target_manager.circuit_data

	# Add Nodes
	for id in data.nodes:
		var n_data = data.nodes[id].duplicate()
		if _node_positions.has(id):
			n_data["position"] = _node_positions[id]
		_create_graph_node(id, n_data)

	# Add Connections
	for conn in data.connections:
		var from_id = conn.get("from", "")
		var to_id = conn.get("to", "")
		var from_port = conn.get("from_port", 0)
		var to_port = conn.get("to_port", 0)
		if from_id != "" and to_id != "" and data.nodes.has(from_id) and data.nodes.has(to_id):
			if graph_edit.has_node(from_id) and graph_edit.has_node(to_id):
				graph_edit.connect_node(from_id, from_port, to_id, to_port)

func _create_graph_node(id: String, data: Dictionary):
	var node = GraphNode.new()
	node.name = id
	node.title = id
	node.offset = data.get("position", Vector2.ZERO)
	node.show_close = true
	node.connect("close_request", self, "_on_node_close_request", [id])
	node.connect("dragged", self, "_on_node_dragged", [id])
	node.rect_min_size = Vector2(140, 50)

	var type = data.get("type", "PROP")
	
	if type == "PROP":
		var scene_path = str(data.get("scene_path", ""))
		var info_label = Label.new()
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		node.title = id
		if scene_path == "":
			info_label.text = "(unassigned)"
			info_label.modulate = Color(1.0, 0.4, 0.4)
		else:
			var display_name = scene_path
			if display_name.begins_with("../"):
				display_name = display_name.substr(3)

			var target_node = null
			if target_manager and target_manager.is_inside_tree():
				target_node = target_manager.get_node_or_null(scene_path)

			if target_manager and target_manager.is_inside_tree() and not target_node:
				info_label.text = display_name + " (!)"
				info_label.modulate = Color(1.0, 0.3, 0.3)
			else:
				info_label.text = display_name
				info_label.modulate = Color(0.8, 1.0, 0.8)

		node.add_child(info_label)
		graph_edit.add_child(node)

		# Slot 0: Input (Left) for set_active, Output (Right) for activated
		node.set_slot(0, true, 0, COLOR_INPUT, true, 0, COLOR_OUTPUT)

	elif type == "GATE":
		var gate_type = data.get("gate_type", "AND")
		node.title = id + " [" + gate_type + "]"

		if gate_type == "DELAY":
			var info_label = Label.new()
			info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_label.text = "Delay: " + str(data.get("delay_time", 1.0)) + "s"
			node.add_child(info_label)
			graph_edit.add_child(node)
			# 1 Input (Left), 1 Output (Right)
			node.set_slot(0, true, 0, COLOR_INPUT, true, 0, COLOR_OUTPUT)
		elif gate_type == "NOT":
			var info_label = Label.new()
			info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_label.text = "Invert"
			node.add_child(info_label)
			graph_edit.add_child(node)
			# 1 Input (Left), 1 Output (Right)
			node.set_slot(0, true, 0, COLOR_INPUT, true, 0, COLOR_OUTPUT)
		else: # AND, OR, XOR
			var lbl1 = Label.new()
			lbl1.text = "In 1 / Out"
			lbl1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			node.add_child(lbl1)

			var lbl2 = Label.new()
			lbl2.text = "In 2"
			lbl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			node.add_child(lbl2)

			graph_edit.add_child(node)
			# Slot 0: Input 0 (Left), Output (Right)
			node.set_slot(0, true, 0, COLOR_INPUT, true, 0, COLOR_OUTPUT)
			# Slot 1: Input 1 (Left), No Output
			node.set_slot(1, true, 0, COLOR_INPUT, false, 0, COLOR_OUTPUT)

func _on_connection_request(from: String, from_slot: int, to: String, to_slot: int):
	if not target_manager or not target_manager.circuit_data:
		return

	var data = target_manager.circuit_data
	if not data.nodes.has(from) or not data.nodes.has(to):
		return

	# Validate connection direction:
	# `from` node must have output at `from_slot`
	# `to` node must have input at `to_slot`
	var from_node_data = data.nodes[from]
	var to_node_data = data.nodes[to]

	if not _node_has_output_slot(from_node_data, from_slot):
		status_label.text = "Invalid connection: source slot is not an output"
		return

	if not _node_has_input_slot(to_node_data, to_slot):
		status_label.text = "Invalid connection: target slot is not an input"
		return

	# Avoid duplicate connection
	for conn in data.connections:
		if conn.get("from", "") == from and conn.get("from_port", 0) == from_slot and conn.get("to", "") == to and conn.get("to_port", 0) == to_slot:
			return

	data.connect_nodes(from, from_slot, to, to_slot)
	_mark_dirty()
	graph_edit.connect_node(from, from_slot, to, to_slot)
	run_validation()

func _node_has_output_slot(n_data: Dictionary, slot: int) -> bool:
	var type = n_data.get("type", "PROP")
	if type == "PROP":
		return slot == 0
	elif type == "GATE":
		return slot == 0 # All gates output on slot 0
	return false

func _node_has_input_slot(n_data: Dictionary, slot: int) -> bool:
	var type = n_data.get("type", "PROP")
	if type == "PROP":
		return slot == 0
	elif type == "GATE":
		var gate_type = n_data.get("gate_type", "AND")
		if gate_type in ["NOT", "DELAY"]:
			return slot == 0
		else: # AND, OR, XOR
			return slot == 0 or slot == 1
	return false

func _on_disconnection_request(from: String, from_slot: int, to: String, to_slot: int):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.disconnect_nodes(from, from_slot, to, to_slot)
		_mark_dirty()
		graph_edit.disconnect_node(from, from_slot, to, to_slot)
		run_validation()

func _on_node_dragged(from: Vector2, to: Vector2, id: String):
	_node_positions[id] = to
	if target_manager and target_manager.circuit_data:
		if target_manager.circuit_data.nodes.has(id):
			target_manager.circuit_data.nodes[id]["position"] = to
			_mark_dirty()

func _on_node_close_request(id: String):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.remove_node(id)
		_node_positions.erase(id)
		_mark_dirty()
		var node = graph_edit.get_node_or_null(id)
		if node:
			node.queue_free()
		if selected_node_id == id:
			_clear_inspector()
		run_validation()

# --- Inspector Logic ---

func _on_node_selected(node: Node):
	selected_node_id = node.name
	_update_inspector()

func _on_node_unselected(node: Node):
	if node and node.name == selected_node_id:
		_clear_inspector()

func _clear_inspector():
	selected_node_id = ""
	no_selection_label.show()
	form.hide()

func _update_inspector():
	if selected_node_id == "" or not target_manager or not target_manager.circuit_data:
		_clear_inspector()
		return

	var data = target_manager.circuit_data.nodes.get(selected_node_id, {})
	if data.empty():
		_clear_inspector()
		return

	no_selection_label.hide()
	form.show()

	id_edit.text = selected_node_id
	var type = data.get("type", "PROP")
	type_val_label.text = type

	if type == "PROP":
		gate_type_row.hide()
		delay_row.hide()
		scene_path_row.show()
		path_edit.text = str(data.get("scene_path", ""))
	elif type == "GATE":
		gate_type_row.show()
		scene_path_row.show()
		path_edit.text = str(data.get("scene_path", ""))

		var gate_type = data.get("gate_type", "AND")
		var idx = 0
		for i in range(gate_option.get_item_count()):
			if gate_option.get_item_text(i) == gate_type:
				idx = i
				break
		gate_option.selected = idx

		if gate_type == "DELAY":
			delay_row.show()
			delay_spin.value = float(data.get("delay_time", 1.0))
		else:
			delay_row.hide()

func _on_id_edited(new_text: String):
	_apply_id_change(new_text)

func _on_id_focus_exited():
	if selected_node_id != "" and id_edit.text != selected_node_id:
		_apply_id_change(id_edit.text)

func _apply_id_change(new_id: String):
	new_id = new_id.strip_edges()
	if new_id == "" or new_id == selected_node_id or not target_manager or not target_manager.circuit_data:
		id_edit.text = selected_node_id
		return

	var data = target_manager.circuit_data
	if data.nodes.has(new_id):
		status_label.text = "Error: Node ID '%s' already exists" % new_id
		id_edit.text = selected_node_id
		return

	# Update node dict
	var node_data = data.nodes[selected_node_id]
	data.nodes.erase(selected_node_id)
	data.nodes[new_id] = node_data

	# Update connections
	for conn in data.connections:
		if conn.get("from", "") == selected_node_id:
			conn["from"] = new_id
		if conn.get("to", "") == selected_node_id:
			conn["to"] = new_id

	# Update position cache
	if _node_positions.has(selected_node_id):
		_node_positions[new_id] = _node_positions[selected_node_id]
		_node_positions.erase(selected_node_id)

	selected_node_id = new_id
	_mark_dirty()
	_refresh_graph()
	run_validation()

func _on_gate_type_changed(index: int):
	if selected_node_id == "" or not target_manager or not target_manager.circuit_data:
		return
	var gate_type = gate_option.get_item_text(index)
	var data = target_manager.circuit_data
	if data.nodes.has(selected_node_id):
		data.nodes[selected_node_id]["gate_type"] = gate_type
		if gate_type == "DELAY" and not data.nodes[selected_node_id].has("delay_time"):
			data.nodes[selected_node_id]["delay_time"] = 1.0
		_mark_dirty()
		_update_inspector()
		_refresh_graph()
		run_validation()

func _on_delay_changed(value: float):
	if selected_node_id == "" or not target_manager or not target_manager.circuit_data:
		return
	var data = target_manager.circuit_data
	if data.nodes.has(selected_node_id):
		data.nodes[selected_node_id]["delay_time"] = value
		_mark_dirty()
		_refresh_graph()
		run_validation()

func _on_path_edited(new_text: String):
	_apply_path_change(new_text)

func _on_path_focus_exited():
	_apply_path_change(path_edit.text)

func _apply_path_change(new_path_str: String):
	if selected_node_id == "" or not target_manager or not target_manager.circuit_data:
		return
	var data = target_manager.circuit_data
	if data.nodes.has(selected_node_id):
		data.nodes[selected_node_id]["scene_path"] = NodePath(new_path_str.strip_edges())
		_mark_dirty()
		_refresh_graph()
		run_validation()

# --- Scene Picker ---

func _on_pick_btn_pressed():
	if not target_manager:
		status_label.text = "Error: No LogicCircuitManager target"
		return

	scene_picker_tree.clear()
	var root_node = _get_scene_root()
	if not root_node:
		status_label.text = "Error: Could not locate scene root"
		return

	var root_item = scene_picker_tree.create_item()
	_populate_tree_item(root_item, root_node)
	scene_picker_dialog.popup_centered()

func _get_scene_root() -> Node:
	if not target_manager:
		return null
	if Engine.editor_hint and target_manager.is_inside_tree():
		var edited_root = target_manager.get_tree().edited_scene_root
		if edited_root:
			return edited_root
	if target_manager.is_inside_tree():
		var current = target_manager.get_tree().current_scene
		if current:
			return current
	return target_manager.get_owner()

func _populate_tree_item(parent_item: TreeItem, scene_node: Node):
	parent_item.set_text(0, scene_node.name)
	parent_item.set_metadata(0, scene_node)
	
	if scene_node is InteractableBaseV2 or scene_node is PropBaseV2:
		parent_item.set_custom_color(0, Color(0.4, 0.9, 0.5))

	for child in scene_node.get_children():
		if child is Node:
			if child.name.begins_with("@") or child.name.begins_with("_"):
				continue
			var child_item = parent_item.create_child(parent_item)
			_populate_tree_item(child_item, child)

func _on_scene_picker_confirmed():
	var selected_item = scene_picker_tree.get_selected()
	if not selected_item:
		return
	var selected_node = selected_item.get_metadata(0)
	if not selected_node or not is_instance_valid(selected_node) or not target_manager:
		return

	var rel_path = target_manager.get_path_to(selected_node)
	if selected_node_id != "" and target_manager.circuit_data and target_manager.circuit_data.nodes.has(selected_node_id):
		target_manager.circuit_data.nodes[selected_node_id]["scene_path"] = rel_path
		path_edit.text = str(rel_path)
		_mark_dirty()
		_refresh_graph()
		run_validation()

# --- Toolbar Handlers ---

func _on_add_prop_pressed():
	if not target_manager or not target_manager.circuit_data:
		status_label.text = "Error: Select a manager with CircuitGraphResource"
		return

	var data = target_manager.circuit_data
	var idx = 1
	var node_id = "Prop_%d" % idx
	while data.nodes.has(node_id):
		idx += 1
		node_id = "Prop_%d" % idx

	var node_data = {
		"type": "PROP",
		"position": Vector2(100 + (data.nodes.size() * 20), 100),
		"scene_path": NodePath("")
	}

	data.add_node(node_id, node_data)
	_mark_dirty()
	_create_graph_node(node_id, node_data)
	status_label.text = "Added: " + node_id
	run_validation()

func _on_gate_selected(id: int):
	if not target_manager or not target_manager.circuit_data:
		status_label.text = "Error: Select a manager with CircuitGraphResource"
		return

	var gate_types = ["AND", "OR", "XOR", "NOT", "DELAY"]
	var gate_type = gate_types[id]
	var data = target_manager.circuit_data

	var idx = 1
	var node_id = "%s_%d" % [gate_type, idx]
	while data.nodes.has(node_id):
		idx += 1
		node_id = "%s_%d" % [gate_type, idx]

	var node_data = {
		"type": "GATE",
		"gate_type": gate_type,
		"position": Vector2(200 + (data.nodes.size() * 20), 100),
		"delay_time": 1.0 if gate_type == "DELAY" else 0.0,
		"scene_path": NodePath("")
	}

	data.add_node(node_id, node_data)
	_mark_dirty()
	_create_graph_node(node_id, node_data)
	status_label.text = "Added: " + node_id
	run_validation()

func _on_refresh_pressed():
	_refresh_graph()
	run_validation()
	status_label.text = "Graph refreshed"

func _on_clear_pressed():
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.clear()
		_node_positions.clear()
		_clear_inspector()
		_mark_dirty()
		_refresh_graph()
		run_validation()
		status_label.text = "Circuit cleared"

# --- Validation ---

func run_validation():
	if not validation_text:
		return
	if not target_manager or not target_manager.circuit_data:
		validation_text.text = "No CircuitGraphResource loaded."
		return

	var result = target_manager.circuit_data.validate()
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])

	# Check scene_path resolutions
	var data = target_manager.circuit_data
	for id in data.nodes:
		var n_data = data.nodes[id]
		var sp = n_data.get("scene_path", NodePath())
		if sp and not sp.is_empty():
			if target_manager.is_inside_tree():
				var resolved = target_manager.get_node_or_null(sp)
				if not resolved:
					warnings.append("Node '%s' scene_path '%s' cannot be resolved in current scene" % [id, str(sp)])

	var output = "VALIDATION RESULT:\n"
	output += "Status: " + ("VALID" if errors.empty() else "INVALID") + "\n"
	output += "Nodes: %d, Connections: %d\n\n" % [result.get("node_count", 0), result.get("connection_count", 0)]

	if not errors.empty():
		output += "ERRORS (%d):\n" % errors.size()
		for err in errors:
			output += " - " + str(err) + "\n"
		output += "\n"

	if not warnings.empty():
		output += "WARNINGS (%d):\n" % warnings.size()
		for warn in warnings:
			output += " - " + str(warn) + "\n"

	if errors.empty() and warnings.empty():
		output += "No issues found."

	validation_text.text = output
