extends Spatial
class_name Room3DLab

# Room3DLab.gd - Industrial Environment Diagnostics & Simulation Laboratory (FD-281)
# Manages 3 sealed rooms (Control, Cryo A, Plasma B), 3 airlocks, and HoloTerminals.

export(NodePath) var control_room_path: NodePath
export(NodePath) var cryo_room_path: NodePath
export(NodePath) var plasma_room_path: NodePath

export(NodePath) var airlock_1_path: NodePath # Control <-> Cryo
export(NodePath) var airlock_2_path: NodePath # Control <-> Plasma
export(NodePath) var airlock_3_path: NodePath # Cryo <-> Plasma

export(NodePath) var plasma_pressure_section_path: NodePath

var control_room: Room3D = null
var cryo_room: Room3D = null
var plasma_room: Room3D = null

var airlock_1: AirlockControllerV2 = null
var airlock_2: AirlockControllerV2 = null
var airlock_3: AirlockControllerV2 = null

var plasma_pressure_section: PressureSection = null


func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("room_3d_lab")
	_resolve_nodes()


func _resolve_nodes() -> void:
	if control_room_path:
		control_room = get_node_or_null(control_room_path) as Room3D
	if cryo_room_path:
		cryo_room = get_node_or_null(cryo_room_path) as Room3D
	if plasma_room_path:
		plasma_room = get_node_or_null(plasma_room_path) as Room3D

	if airlock_1_path:
		airlock_1 = get_node_or_null(airlock_1_path) as AirlockControllerV2
	if airlock_2_path:
		airlock_2 = get_node_or_null(airlock_2_path) as AirlockControllerV2
	if airlock_3_path:
		airlock_3 = get_node_or_null(airlock_3_path) as AirlockControllerV2

	if plasma_pressure_section_path:
		plasma_pressure_section = get_node_or_null(plasma_pressure_section_path) as PressureSection


func purge_plasma_chamber() -> void:
	if plasma_pressure_section and is_instance_valid(plasma_pressure_section):
		plasma_pressure_section.purge()
	elif plasma_room and is_instance_valid(plasma_room):
		plasma_room.set_pressure(1.0)
		plasma_room.set_contamination(0.0)


func purge_cryo_chamber() -> void:
	if cryo_room and is_instance_valid(cryo_room):
		cryo_room.set_pressure(1.0)
		cryo_room.set_contamination(0.0)
		cryo_room.set_temperature(20.0)


func get_snapshot() -> Dictionary:
	return {}


func restore_snapshot(_data: Dictionary) -> void:
	pass
