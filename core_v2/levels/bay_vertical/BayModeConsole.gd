extends Area

# Consola de cambio de modo de gravedad (FD-322).
#
# Sebastián: el cambio centrífugo <-> propulsión LO ACTIVA EL JUGADOR desde consolas
# en el camino y desde la sala de control. Es un puzle que reconfigura las rutas, no
# un reloj. Acá la consola es un interruptor FÍSICO (proximidad): el jugador la pisa/
# toca y conmuta el modo del pozo. Sin texto ni hints de teclas (narrativa ambiental).
#
# Determinismo: el toggle es un cambio de estado (no un reloj); se resuelve en
# `_physics_process` vía `body_entered` del Area. El estado vive en el pozo.

export(NodePath) var well_path: NodePath = NodePath("")
export(Color) var spin_color := Color(0.3, 0.8, 1.0, 1.0)
export(Color) var thrust_color := Color(1.0, 0.7, 0.3, 1.0)

var _well: Node = null
var _light: OmniLight = null
var _pips: Array = []
var _armed := true

func _ready() -> void:
	_well = _resolve_well()
	_build_console()
	collision_layer = 0
	collision_mask = 2  # jugador
	monitoring = true
	connect("body_entered", self, "_on_body_entered")
	if _well and _well.has_method("get_gravity_mode"):
		_refresh(_well.get_gravity_mode())

func _resolve_well() -> Node:
	if not well_path.is_empty():
		var n = get_node_or_null(well_path)
		if n:
			return n
	return get_parent()

func _build_console() -> void:
	var pedestal := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = Vector3(0.8, 1.0, 0.5)
	pedestal.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.18, 0.2, 0.24, 1.0)
	mat.metallic = 0.5
	mat.roughness = 0.5
	pedestal.material_override = mat
	pedestal.translation = Vector3(0.0, 0.5, 0.0)
	add_child(pedestal)
	# Tres pips de estado (no texto): se encienden según el modo.
	var pip_mesh := CubeMesh.new()
	pip_mesh.size = Vector3(0.14, 0.05, 0.14)
	for i in range(3):
		var pip := MeshInstance.new()
		pip.mesh = pip_mesh
		var pm := SpatialMaterial.new()
		pm.albedo_color = Color(0.1, 0.12, 0.14, 1.0)
		pm.emission_enabled = true
		pm.emission = Color(0, 0, 0, 0)
		pip.material_override = pm
		pip.translation = Vector3(-0.24 + float(i) * 0.24, 1.02, 0.0)
		add_child(pip)
		_pips.append(pip)
	_light = OmniLight.new()
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	_light.translation = Vector3(0.0, 1.2, 0.0)
	add_child(_light)
	var col := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(0.5, 0.6, 0.4)
	col.shape = box
	col.translation = Vector3(0.0, 0.6, 0.0)
	add_child(col)

func _on_body_entered(body: Node) -> void:
	if not _armed:
		return
	if not body.is_in_group("player"):
		return
	if _well and _well.has_method("toggle_gravity_mode"):
		if _well.toggle_gravity_mode():
			_armed = false  # un disparo por entrada; se rearma al salir
			call_deferred("_arm_after_exit")

func _arm_after_exit() -> void:
	# Rearmar cuando el jugador ya no esté dentro (evita doble toggle por frame).
	var tree = get_tree()
	if tree == null:
		return
	yield(tree, "physics_frame")
	_armed = true

func set_mode(mode: int) -> void:
	_refresh(mode)

func _refresh(mode: int) -> void:
	# 0 = propulsión (axial), 1 = centrífugo (spin). Sin texto: pips + luz.
	var color: Color = thrust_color if mode == 0 else spin_color
	for i in range(_pips.size()):
		var pip = _pips[i]
		if not is_instance_valid(pip):
			continue
		var mat: SpatialMaterial = pip.material_override
		var lit: bool = (i <= (0 if mode == 0 else 2))
		mat.albedo_color = color if lit else Color(0.1, 0.12, 0.14, 1.0)
		mat.emission = color if lit else Color(0, 0, 0, 0)
	if _light:
		_light.light_color = color
		_light.light_energy = 1.2
