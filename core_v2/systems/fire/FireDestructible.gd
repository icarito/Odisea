extends Node
class_name FireDestructible

# FD-051: componente que derrite una pieza cuando el fuego alcanza su altura.
#
# CAPA LÓGICA. Se le cuelga como hijo a cualquier prop (rampa, plataforma) sin cambiar su
# clase base. No simula nada: un `if` de su propia Y contra el float compartido del
# FireSystem. Determinista y barato.
#
# Produce el "el camino se desmorona detrás de ti" que valida el bucle del Vertical Slice.

signal melt_started()
signal melted()

# Margen bajo la pieza: el fuego la alcanza un poco antes de tocarla.
export(float) var melt_offset := 0.0
# Segundos de gracia visible entre que empieza a derretirse y que colapsa.
export(float) var melt_delay := 1.5
# Desactiva la colisión al colapsar (la pieza deja de sostener al jugador).
export(bool) var disable_collision_on_melt := true
# Oculta la pieza al colapsar. Con false, queda ennegrecida y sin colisión.
export(bool) var hide_on_melt := true
# Color al que tiende el material durante el derretimiento.
export(Color) var char_color := Color(0.08, 0.06, 0.06, 1.0)

var is_melting := false
var is_melted := false

var _melt_timer := 0.0
var _host: Spatial = null
var _fire_system: Node = null
var _char_material: SpatialMaterial = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	add_to_group("fire_destructible")
	_host = _resolve_host()
	if _host == null:
		push_warning("[FireDestructible] sin host Spatial; el componente no hará nada.")
		set_physics_process(false)
		return
	call_deferred("_connect_fire_system")

func reset() -> void:
	is_melting = false
	is_melted = false
	_melt_timer = 0.0
	if is_instance_valid(_host):
		_host.visible = true
		_set_collision_disabled(false)

func _physics_process(delta: float) -> void:
	if is_melted or not is_instance_valid(_host):
		return
	if not is_instance_valid(_fire_system):
		_connect_fire_system()
		return

	if not is_melting:
		var threshold: float = _host.global_transform.origin.y - melt_offset
		if float(_fire_system.fire_height) >= threshold:
			is_melting = true
			_melt_timer = melt_delay
			emit_signal("melt_started")
		return

	_melt_timer = max(_melt_timer - delta, 0.0)
	_apply_char_tint(1.0 - (_melt_timer / max(melt_delay, 0.001)))
	if _melt_timer <= 0.0:
		_collapse()

func _collapse() -> void:
	is_melted = true
	if disable_collision_on_melt:
		_set_collision_disabled(true)
	if hide_on_melt and is_instance_valid(_host):
		_host.visible = false
	emit_signal("melted")

func _resolve_host() -> Spatial:
	var parent: Node = get_parent()
	if parent is Spatial:
		return parent as Spatial
	return null

func _connect_fire_system() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("fire_system")
	if systems.empty():
		return
	_fire_system = systems[0]

func _set_collision_disabled(disabled: bool) -> void:
	if not is_instance_valid(_host):
		return
	for shape in _find_collision_shapes(_host):
		shape.disabled = disabled

func _find_collision_shapes(node: Node) -> Array:
	var found := []
	if node is CollisionShape:
		found.append(node)
	for child in node.get_children():
		if child is Node:
			found += _find_collision_shapes(child)
	return found

func _apply_char_tint(progress: float) -> void:
	if not is_instance_valid(_host):
		return
	var mesh: MeshInstance = _find_first_mesh(_host)
	if mesh == null:
		return
	if _char_material == null:
		_char_material = SpatialMaterial.new()
		var source = mesh.get_active_material(0)
		if source is SpatialMaterial:
			_char_material.albedo_color = source.albedo_color
		mesh.material_override = _char_material
	_char_material.albedo_color = _char_material.albedo_color.linear_interpolate(char_color, clamp(progress, 0.0, 1.0) * 0.1)

func _find_first_mesh(node: Node) -> MeshInstance:
	if node is MeshInstance:
		return node as MeshInstance
	for child in node.get_children():
		if child is Node:
			var found: MeshInstance = _find_first_mesh(child)
			if found != null:
				return found
	return null

# --- REPLAY ---

func get_snapshot() -> Dictionary:
	return {
		"is_melting": is_melting,
		"is_melted": is_melted,
		"melt_timer": _melt_timer
	}

func restore_snapshot(data: Dictionary) -> void:
	is_melting = bool(data.get("is_melting", false))
	is_melted = bool(data.get("is_melted", false))
	_melt_timer = float(data.get("melt_timer", 0.0))
	if is_instance_valid(_host):
		if is_melted:
			if disable_collision_on_melt:
				_set_collision_disabled(true)
			if hide_on_melt:
				_host.visible = false
		else:
			_host.visible = true
			_set_collision_disabled(false)
