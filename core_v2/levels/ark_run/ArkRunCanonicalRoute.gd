extends Reference
class_name ArkRunCanonicalRoute

# FD-324 F2 — ruta canónica proa (+Z, Puente) → popa (-Z, Motor).
#
# Waypoints deterministas derivados de la espiral del slice. Cada uno lleva
# `pos` y `position` (mismo Vector3) más `size`, el formato que consume
# AutopilotInputV2.set_route(): con `size` apunta al punto más cercano de la
# plataforma. Los nombres permiten consultar la sub-ruta hasta Puente, Núcleo,
# Motor o cualquiera de los ascensores radiales.

const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const PLATE_SIZE := Vector3(200.0, 2.0, 200.0)
const NAME_BRIDGE := "Puente"
const NAME_HUB := "Núcleo"
const NAME_HUB_ACCESS := "Acceso_Núcleo"
const NAME_ENGINE := "Motor"
# Placas con estación de ascensor radial (el acceso al Núcleo se reserva a la de z≈0).
const ELEVATOR_PLATE_INDICES := [45, 35, 15, 5]

var _waypoints: Array = []
var _names: Array = []
var _plate_size := PLATE_SIZE
var _hub_waypoint: Dictionary = {}
var _hub_access_index := -1

static func build_waypoints(
	spiral: Dictionary, plate_size: Vector3 = PLATE_SIZE
) -> Array:
	var count: int = SpiralGeometry.plate_count_for(spiral)
	var hub_index: int = hub_plate_index(spiral)
	var waypoints: Array = []
	for plate_index in range(count - 1, -1, -1):
		var xform: Transform = SpiralGeometry.plate_transform(spiral, plate_index)
		waypoints.append(_make_waypoint(
			plate_index, xform, plate_size, hub_index, count
		))
	return waypoints

static func hub_plate_index(spiral: Dictionary) -> int:
	var best_index: int = 0
	var best_abs_z: float = INF
	for index in range(SpiralGeometry.plate_count_for(spiral)):
		var abs_z: float = abs(SpiralGeometry.plate_transform(spiral, index).origin.z)
		if abs_z < best_abs_z - 1e-6:
			best_abs_z = abs_z
			best_index = index
	return best_index

static func _make_waypoint(
	plate_index: int, xform: Transform, plate_size: Vector3,
	hub_index: int, count: int
) -> Dictionary:
	var waypoint_name := "Placa_%d" % plate_index
	var kind := "Plate"
	if plate_index == 0:
		waypoint_name = NAME_ENGINE
		kind = "Engine"
	elif plate_index == count - 1:
		waypoint_name = NAME_BRIDGE
		kind = "Bridge"
	elif plate_index == hub_index:
		waypoint_name = NAME_HUB_ACCESS
		kind = "HubAccess"
	elif ELEVATOR_PLATE_INDICES.has(plate_index):
		waypoint_name = "Ascensor_%d" % plate_index
		kind = "Elevator"
	return {
		"name": waypoint_name, "kind": kind,
		"pos": xform.origin, "position": xform.origin,
		"size": plate_size, "plate_index": plate_index, "z": xform.origin.z
	}

# AutopilotInputV2 exige `position`; `pos` se publica por el contrato de F2.
static func is_autopilot_waypoint(waypoint) -> bool:
	if typeof(waypoint) != TYPE_DICTIONARY:
		return false
	return waypoint.has("position") and typeof(waypoint["position"]) == TYPE_VECTOR3 \
		and waypoint.has("pos") and typeof(waypoint["pos"]) == TYPE_VECTOR3 \
		and waypoint.has("size") and typeof(waypoint["size"]) == TYPE_VECTOR3

func configure(spiral: Dictionary, plate_size: Vector3 = PLATE_SIZE) -> void:
	_plate_size = plate_size
	_waypoints = build_waypoints(spiral, plate_size)
	_names = []
	_hub_access_index = -1
	for waypoint in _waypoints:
		_names.append(String(waypoint["name"]))
		if String(waypoint["name"]) == NAME_HUB_ACCESS:
			_hub_access_index = _names.size() - 1
	# El Núcleo real es el hub axial (r ≤ 8) al que se llega con el ascensor radial
	# desde la terraza de z≈0; no se inserta en la cadena proa→popa.
	var hub_plate: Transform = SpiralGeometry.plate_transform(spiral, hub_plate_index(spiral))
	_hub_waypoint = {
		"name": NAME_HUB, "kind": "Hub",
		"pos": Vector3(0.0, 0.0, hub_plate.origin.z),
		"position": Vector3(0.0, 0.0, hub_plate.origin.z),
		"size": Vector3(16.0, 16.0, 16.0), "plate_index": hub_plate_index(spiral)
	}
	_names.append(NAME_HUB)

func get_waypoints() -> Array:
	return _waypoints.duplicate(true)

func get_destination_names() -> Array:
	return _names.duplicate()

func has_destination(destination_name: String) -> bool:
	return _names.find(destination_name) >= 0

# Sub-ruta desde el inicio (proa) hasta el destino nombrado, incluido.
func route_to(destination_name: String) -> Array:
	if destination_name == NAME_HUB:
		if _hub_access_index < 0:
			return []
		var prefix: Array = _waypoints.slice(0, _hub_access_index)
		prefix.append(_hub_waypoint.duplicate(true))
		return prefix
	var index: int = _names.find(destination_name)
	if index < 0:
		return []
	return _waypoints.slice(0, index)

func get_named_waypoint(destination_name: String) -> Dictionary:
	if destination_name == NAME_HUB:
		return _hub_waypoint.duplicate(true)
	var index: int = _names.find(destination_name)
	return _waypoints[index].duplicate(true) if index >= 0 else {}

func get_start_name() -> String:
	return String(_waypoints[0]["name"]) if not _waypoints.empty() else ""

func get_end_name() -> String:
	return String(_waypoints[-1]["name"]) if not _waypoints.empty() else ""
