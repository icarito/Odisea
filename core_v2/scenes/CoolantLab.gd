extends Spatial
class_name CoolantLab

# CoolantLab.gd - Root controller for grey-box coolant laboratory (FD-265).
# Tracks system stabilization win condition across West and East coolant branches.

export(NodePath) var flow_adapter_west_path: NodePath
export(NodePath) var flow_adapter_east_path: NodePath
export(NodePath) var leak_west_patch_path: NodePath
export(NodePath) var leak_east_patch_path: NodePath
export(NodePath) var manometer_west_path: NodePath
export(NodePath) var manometer_east_path: NodePath
export(NodePath) var status_label_path: NodePath

var _adapter_west = null
var _adapter_east = null
var _patch_west = null
var _patch_east = null
var _manometer_west = null
var _manometer_east = null
var _status_label = null

var _is_stabilized: bool = false

signal lab_stabilized()


func _ready() -> void:
	add_to_group("replay_sync")
	_resolve_references()
	_update_status()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_update_status()


func _resolve_references() -> void:
	if flow_adapter_west_path != null and not flow_adapter_west_path.is_empty():
		_adapter_west = get_node_or_null(flow_adapter_west_path)
	if flow_adapter_east_path != null and not flow_adapter_east_path.is_empty():
		_adapter_east = get_node_or_null(flow_adapter_east_path)
	if leak_west_patch_path != null and not leak_west_patch_path.is_empty():
		_patch_west = get_node_or_null(leak_west_patch_path)
	if leak_east_patch_path != null and not leak_east_patch_path.is_empty():
		_patch_east = get_node_or_null(leak_east_patch_path)
	if manometer_west_path != null and not manometer_west_path.is_empty():
		_manometer_west = get_node_or_null(manometer_west_path)
	if manometer_east_path != null and not manometer_east_path.is_empty():
		_manometer_east = get_node_or_null(manometer_east_path)
	if status_label_path != null and not status_label_path.is_empty():
		_status_label = get_node_or_null(status_label_path)


func _update_status() -> void:
	_resolve_references()

	var west_flow_ok: bool = (_adapter_west != null and _adapter_west.is_flow_active())
	var east_flow_ok: bool = (_adapter_east != null and _adapter_east.is_flow_active())

	var west_patched: bool = (_patch_west != null and _patch_west.is_patched())
	var east_patched: bool = (_patch_east != null and _patch_east.is_patched())

	var west_press_ok: bool = (_manometer_west != null and _manometer_west.get_pressure() > 2.0)
	var east_press_ok: bool = (_manometer_east != null and _manometer_east.get_pressure() > 2.0)

	var stabilized: bool = (west_flow_ok and east_flow_ok and west_patched and east_patched and west_press_ok and east_press_ok)

	if stabilized and not _is_stabilized:
		_is_stabilized = true
		emit_signal("lab_stabilized")
	elif not stabilized and _is_stabilized:
		_is_stabilized = false

	if _status_label != null and _status_label is Label:
		if _is_stabilized:
			_status_label.text = "SISTEMA ESTABILIZADO"
		else:
			var west_str: String = "OK" if (west_flow_ok and west_patched) else ("FUGA" if not west_patched else "CORTE")
			var east_str: String = "OK" if (east_flow_ok and east_patched) else ("FUGA" if not east_patched else "CORTE")
			_status_label.text = "ESTADO COOLANT | OESTE: %s | ESTE: %s" % [west_str, east_str]


func is_stabilized() -> bool:
	return _is_stabilized


func get_snapshot() -> Dictionary:
	return {
		"is_stabilized": _is_stabilized
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("is_stabilized"):
		_is_stabilized = bool(data["is_stabilized"])
	_update_status()
