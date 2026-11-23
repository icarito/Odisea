extends Reference

# FD-325 polish — utilidades de física para la cuerda del Ark Run (línea de visión).
# Funciones sin estado: el espacio físico y el ojo los pasa el caller.

const LOS_MIN_CLEARANCE_M := 4.5
const EPSILON := 1e-6

static func space_state() -> PhysicsDirectSpaceState:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var world: World = tree.root.get_world()
	return world.direct_space_state if world != null else null

# Excluye al pilot y todo lo que cuelga de él (cápsula y rig de cámara).
static func exclude_for(pilot) -> Array:
	var exclude: Array = []
	if pilot != null and is_instance_valid(pilot):
		exclude.append(pilot)
		for child in pilot.get_children():
			if child is CollisionObject:
				exclude.append(child)
	return exclude

# bodies-only + hit_from_inside: el origen dentro de una placa devuelve vacío si se apaga,
# y el guard de proximidad al ojo descarta esa geometría contenedora. Rechaza si algo
# sólido queda a más de LOS_MIN_CLEARANCE_M del anclaje.
static func has_line_of_sight(space: PhysicsDirectSpaceState, eye: Vector3, point: Vector3, pilot) -> bool:
	if space == null or point.distance_to(eye) <= EPSILON:
		return true
	var hit: Dictionary = space.intersect_ray(eye, point, exclude_for(pilot), 0x7FFFFFFF, true, false)
	if hit.empty():
		return true
	var hit_pos: Vector3 = hit.get("position", point)
	if hit_pos.distance_to(eye) <= LOS_MIN_CLEARANCE_M:
		return true
	return hit_pos.distance_to(point) <= LOS_MIN_CLEARANCE_M
