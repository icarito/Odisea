tool
extends BaseZoneV2
class_name CameraZoneV2

# CameraZone.gd - Trigger zone to activate a cinematic rig
# Permite referenciar directamente el CinematicRig desde el Inspector.

# Referencia directa al rig (arrastra el nodo desde el árbol)
export(NodePath) var cinematic_rig_path: NodePath
export(CinematicManager.ControlMode) var control_mode = CinematicManager.ControlMode.LOCKED_VIEW

# --- Direction Latch Control ---
export(bool) var latch_on_enter := true # Si true, activa el latch de dirección al entrar a la zona
export(bool) var latch_on_exit := true # Si true, activa el latch de dirección al salir de la zona
export(Vector3) var track_axis := Vector3.RIGHT # Eje principal de movimiento 2.5D

# Cached reference (may be any Node; CinematicRigV2 is a Spatial)
var _rig_node: Node = null

# Runtime control: allows external systems (like HoloTerminal) to enable/disable this zone
var is_zone_active: bool = true

func _ready():
	if _is_rl_mode():
		monitoring = false
		monitorable = false
		set_process(false)
		set_physics_process(false)
		return
	# Auto-setup: crear CollisionShape si no existe (también en editor para visualización)
	_ensure_collision_shape()
	# Si alguien escaló el nodo Area, hornear escala en extents para que gizmos/prioridad sean consistentes.
	_bake_scale_into_extents()
	# Llamar a la lógica base de BaseZoneV2
	._ready()
	add_to_group("CameraZoneV2")
	
	# Color naranja para zonas cinemáticas
	if debug_color == Color(0, 1, 0, 0.2):
		set_debug_color(Color(1.0, 0.5, 0.0, 0.3))
	
	# Cache rig deterministically at ready
	_cache_rig()

func _ensure_collision_shape():
	"""Crea un CollisionShape automáticamente si la zona no tiene uno."""
	var has_shape := false
	for child in get_children():
		if child is CollisionShape:
			has_shape = true
			break
	
	if not has_shape:
		var shape_node = CollisionShape.new()
		shape_node.name = "CollisionShape"
		var box = BoxShape.new()
		box.extents = zone_extents
		shape_node.shape = box
		add_child(shape_node)

func _bake_scale_into_extents():
	var s := scale
	if s.distance_squared_to(Vector3.ONE) <= 0.000001:
		return

	var abs_s = Vector3(abs(s.x), abs(s.y), abs(s.z))
	if abs_s.x <= 0.001 or abs_s.y <= 0.001 or abs_s.z <= 0.001:
		return

	# Mantener posición/rotación global de hijos (rigs, cámaras) al normalizar scale del Area.
	var child_spatials: Array = []
	var child_globals: Array = []
	for child in get_children():
		if child is Spatial and not (child is CollisionShape):
			child_spatials.append(child)
			child_globals.append((child as Spatial).global_transform)

	set_zone_extents(Vector3(
		max(0.05, zone_extents.x * abs_s.x),
		max(0.05, zone_extents.y * abs_s.y),
		max(0.05, zone_extents.z * abs_s.z)
	))
	scale = Vector3.ONE

	for i in range(child_spatials.size()):
		var c = child_spatials[i] as Spatial
		if is_instance_valid(c):
			c.global_transform = child_globals[i]

	if not Engine.editor_hint:
		print("[CameraZone] Baked non-unit scale into zone_extents on ", name)

func _find_rig_in_children(node: Node) -> Node:
	"""Busca recursivamente un CinematicRigV2 entre los hijos."""
	if node is CinematicRigV2:
		return node
	for child in node.get_children():
		var found = _find_rig_in_children(child)
		if found:
			return found
	return null

func _cache_rig():
	"""Cachea la referencia al rig para evitar búsquedas repetidas.
	Si no hay `cinematic_rig_path`, intenta buscar un CinematicRigV2 entre sus hijos."""
	_rig_node = null
	# Primero intentar por path explícito
	if cinematic_rig_path and not cinematic_rig_path.is_empty():
		_rig_node = get_node_or_null(cinematic_rig_path)
		if _rig_node:
			return
		else:
			printerr("[CameraZone] Rig no encontrado en path: ", cinematic_rig_path)

	# Buscar en hijos/descendientes
	var found = _find_rig_in_children(self)
	if found:
		_rig_node = found
		cinematic_rig_path = _rig_node.get_path()
		print("[CameraZone] Auto-linked cinematic rig: ", _rig_node.name)
		return
	
	# Como último recurso, buscar rig en escena por grupo (legacy)
	var rigs = get_tree().get_nodes_in_group("cinematic_rigs")
	if rigs.size() == 1:
		_rig_node = rigs[0]
		cinematic_rig_path = _rig_node.get_path()
		print("[CameraZone] Linked single cinematic rig in scene: ", _rig_node.name)

func _on_zone_entered(_body: Node):
	# Rig activation now handled by PlayerController for determinism
	pass

func _on_zone_exited(_body: Node):
	# Rig deactivation now handled by PlayerController for determinism
	pass

func _is_rl_mode() -> bool:
	var rl_mode_env := OS.get_environment("ANNA_RL_MODE").to_lower()
	return rl_mode_env in ["1", "true", "yes", "on"]
