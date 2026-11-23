extends Reference

# FD-324 F4 — modelo puro del Suit OS del Ark-Run.
#
# Todas las funciones son estáticas: no hay estado ni aleatoriedad. El mini mapa y la
# gravedad local salen directamente de SpinFrame (FD-323), no de una segunda matemática.
# Los snapshots sólo usan tipos serializables (float/Array/String) para que el widget y
# el control remoto lean lo mismo.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

const DEFAULT_HULL_RADIUS := 340.0
const DEFAULT_SLICE_LENGTH := 2000.0
const G_REF := 9.8

const BRIDGE_Z := 880.0
const CORE_Z := 0.0
const ENGINE_Z := -940.0
const ELEVATORS_R := 240.0
const ELEVATORS_Z := -400.0

const DEFAULT_DESTINATION_ID := "engine"
const DESTINATION_BRIDGE := "bridge"
const DESTINATION_CORE := "core"
const DESTINATION_ENGINE := "engine"
const DESTINATION_ELEVATORS := "elevators"


# Corte transversal (círculo) + coordenada axial normalizada en [-1, 1].
static func minimap(position: Vector3, hull_radius: float = DEFAULT_HULL_RADIUS,
		slice_length: float = DEFAULT_SLICE_LENGTH) -> Dictionary:
	var radial := Vector3(position.x, position.y, 0.0)
	var radius: float = radial.length()
	var half: float = slice_length * 0.5
	var angle: float = atan2(position.y, position.x) if radius > 0.000001 else 0.0
	var unit := Vector2(1.0, 0.0)
	if radius > 0.000001:
		unit = Vector2(radial.x, radial.y) / radius
	var radius_ratio: float = clamp(radius / hull_radius, 0.0, 1.0) if hull_radius > 0.0 else 0.0
	var axial_ratio: float = clamp(position.z / half, -1.0, 1.0) if half > 0.0 else 0.0
	var axial: float = clamp(position.z, -half, half) if half > 0.0 else 0.0
	return {
		"angle": angle,
		"radius": radius,
		"radius_ratio": radius_ratio,
		"radial": [unit.x, unit.y],
		"point": [unit.x * radius_ratio, unit.y * radius_ratio],
		"axial": axial,
		"axial_ratio": axial_ratio,
		"half_length": half,
	}


# Gravedad local: magnitud en g y flecha 2D donde +X es popa (-Z) y +Y es radial.
# Con a_axial = 0 la flecha apunta radial/afuera; al encender gira hacia popa.
static func gravity_reading(position: Vector3, omega: float, a_axial: float = 0.0) -> Dictionary:
	var g: Vector3 = SpinFrame.g_eff(position, omega, a_axial)
	var magnitude: float = g.length()
	var direction := Vector3.ZERO
	if magnitude > 0.000001:
		direction = g / magnitude
	var radial_mag: float = sqrt(direction.x * direction.x + direction.y * direction.y)
	var arrow := Vector2(-direction.z, radial_mag)
	var arrow_angle: float = atan2(arrow.x, arrow.y) if magnitude > 0.000001 else 0.0
	return {
		"g": magnitude / G_REF,
		"magnitude": magnitude,
		"direction": [direction.x, direction.y, direction.z],
		"radial": [direction.x, direction.y],
		"arrow": [arrow.x, arrow.y],
		"arrow_angle": arrow_angle,
		"toward_pop": direction.z < -0.000001,
	}


static func ignition_snapshot(state: String, countdown: float) -> Dictionary:
	var normalized := state.to_upper()
	if normalized != "WARNING" and normalized != "ACTIVE":
		normalized = "IDLE"
	return {
		"state": normalized,
		"countdown": max(countdown, 0.0),
		"warning": normalized == "WARNING",
		"active": normalized == "ACTIVE",
	}


static func urgency_for_ignition(state: String) -> String:
	if state == "ACTIVE":
		return "alarm"
	if state == "WARNING":
		return "urgent"
	return "quiet"


static func destinations() -> Array:
	return [
		{"id": DESTINATION_BRIDGE, "label": "Puente", "position": Vector3(0.0, 0.0, BRIDGE_Z)},
		{"id": DESTINATION_CORE, "label": "Núcleo", "position": Vector3(0.0, 0.0, CORE_Z)},
		{"id": DESTINATION_ENGINE, "label": "Motor", "position": Vector3(0.0, 0.0, ENGINE_Z)},
		{"id": DESTINATION_ELEVATORS, "label": "Ascensores",
			"position": Vector3(ELEVATORS_R, 0.0, ELEVATORS_Z)},
	]


static func destination_by_id(id: String) -> Dictionary:
	for destination in destinations():
		if String(destination.get("id", "")) == id:
			return destination
	return {}


static func destination_index(id: String) -> int:
	var list := destinations()
	for i in range(list.size()):
		if String(list[i].get("id", "")) == id:
			return i
	return -1


static func next_destination_id(id: String, step: int = 1) -> String:
	var list := destinations()
	var index: int = destination_index(id)
	if list.empty():
		return ""
	if index < 0:
		index = 0
	index = int((index + step) % list.size())
	if index < 0:
		index += list.size()
	return String(list[index].get("id", ""))


static func destination_snapshot(destination: Dictionary) -> Dictionary:
	var pos: Vector3 = destination.get("position", Vector3.ZERO)
	return {
		"id": String(destination.get("id", "")),
		"label": String(destination.get("label", "")),
		"position": [pos.x, pos.y, pos.z],
		"z": pos.z,
	}


static func destinations_snapshot() -> Array:
	var result: Array = []
	for destination in destinations():
		result.append(destination_snapshot(destination))
	return result
