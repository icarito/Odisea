extends Spatial
class_name SealedDoorLock

# SealedDoorLock.gd - Bridge component connecting AuxPowerBus to a door (FD-259 / FD-255).
# Sealer logic: locks door when bus is OFFLINE/RESTORING, unlocks/activates door when POWERED.

const AuxPowerBusScript = preload("res://core_v2/systems/auxpower/AuxPowerBus.gd")

# --- EXPORTED PROPERTIES ---
# NodePath to the AuxPowerBus node monitoring power state.
export(NodePath) var bus_path: NodePath
# NodePath to the target door node (e.g. HeavyBlastDoor or VerticalDoor inheriting InteractableBaseV2).
export(NodePath) var door_path: NodePath

var _connected_bus: Node = null


func _ready() -> void:
	add_to_group("replay_sync")
	_setup_bus_connection()


func _setup_bus_connection() -> void:
	if bus_path == null or bus_path.is_empty():
		return

	var bus = get_node_or_null(bus_path)
	if not is_instance_valid(bus):
		return

	_connected_bus = bus

	if bus.has_signal("state_changed") and not bus.is_connected("state_changed", self, "_on_bus_state_changed"):
		bus.connect("state_changed", self, "_on_bus_state_changed")
	if bus.has_signal("power_restored") and not bus.is_connected("power_restored", self, "_on_bus_power_restored"):
		bus.connect("power_restored", self, "_on_bus_power_restored")
	if bus.has_signal("power_lost") and not bus.is_connected("power_lost", self, "_on_bus_power_lost"):
		bus.connect("power_lost", self, "_on_bus_power_lost")

	# Initial synchronization
	if bus.has_method("is_powered"):
		_update_door_state(bool(bus.call("is_powered")))


func _on_bus_state_changed(new_state: int) -> void:
	var is_powered := false
	if is_instance_valid(_connected_bus) and _connected_bus.has_method("is_powered"):
		is_powered = bool(_connected_bus.call("is_powered"))
	else:
		is_powered = (new_state == AuxPowerBusScript.State.POWERED)

	_update_door_state(is_powered)


func _on_bus_power_restored() -> void:
	_update_door_state(true)


func _on_bus_power_lost() -> void:
	_update_door_state(false)


func _update_door_state(is_powered: bool) -> void:
	if door_path == null or door_path.is_empty():
		return

	var door = get_node_or_null(door_path)
	if not is_instance_valid(door):
		return

	if is_powered:
		if door.has_method("set_active"):
			door.call("set_active", true)
		elif door.has_method("open"):
			door.call("open")
		elif door.has_method("unseal"):
			door.call("unseal")
	else:
		if door.has_method("set_active"):
			door.call("set_active", false)
		elif door.has_method("close"):
			door.call("close")
		elif door.has_method("seal"):
			door.call("seal")


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"bus_path": bus_path,
		"door_path": door_path
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("bus_path"):
		bus_path = NodePath(data["bus_path"])
	if data.has("door_path"):
		door_path = NodePath(data["door_path"])

	_setup_bus_connection()
