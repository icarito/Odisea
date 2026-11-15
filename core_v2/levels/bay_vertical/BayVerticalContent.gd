extends Spatial

# Capa de CONTENIDO CURADO de la bahía radial (FD-322), montada SOBRE la
# proyección del `ScaffoldStreamController` + `CylinderRotator`.
#
# El stream genera el anillo exterior (banda a `flat.y = 0`); NO aporta la
# subida radial al eje. Este nodo aporta el RECORRIDO jugable y los landmarks
# curados, todos anclados en el plano del stream (espacio "flat": x = arco,
# y = radial hacia el eje, z = axial) y proyectados cada frame con
# `BayCylinderRotator.project_flat_point()`, de modo que:
#
#   - el contenido queda SOBRE los chunks del stream y sigue su reorientación;
#   - al cambiar el modo (consola), `spiral_blend` reorienta TODO el recorrido
#     junto con la geometría (el modo axial lo aplana; el centrífugo lo curva);
#   - la conectividad entrada -> eje es determinista (espiral sembrada), no
#     depende del WFC del stream.
#
# Contenido: espiral de subida (suelo + colisión), plataforma/sala de control y
# baliza en el eje, atajos (cinta/caja, láser, gloo), puente mode-gated (sólo
# propulsión) y rotor de peligro sincronizado con el ciclo.
#
# Este nodo debe colgar del `ScaffoldStreamController` (o de un nodo a identidad
# bajo él): las poses proyectadas viven en el espacio local del stream, igual
# que las de los chunks.
#
# Determinismo: todo deriva de `generation_seed` y de parámetros fijos (sin
# `randf`). Estado serializable.

const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")

const COLLISION_LAYER_ENV := 1

export(int) var generation_seed := 20261114
export(NodePath) var rotator_path := NodePath("")
export(NodePath) var cycle_path := NodePath("")
export(NodePath) var stream_path := NodePath("")
# Luces de sala que el ciclo pinta por fase (SAFE/WARNING/DANGER). Si el path
# queda vacío se busca un hermano llamado "BayLights".
export(NodePath) var lights_path := NodePath("")
export(float, 1.0, 3.0) var turns := 1.25
export(int, 8, 96) var spine_segments := 56
export(float) var walkway_width := 4.2
export(float) var walkway_thickness := 0.3
export(float, 2.0, 20.0) var summit_clearance := 8.0
export(float, 0.1, 0.9) var gloo_gap_ratio := 0.5
export(int, 1, 6) var gloo_gap_segments := 2
export(float, 0.05, 0.9) var laser_ratio := 0.32
export(float, 0.05, 0.95) var bridge_ratio := 0.68
export(float, 0.05, 0.95) var rotor_ratio := 0.82
export(float, 0.05, 0.9) var conveyor_ratio := 0.14

signal content_ready()

var _rotator: Node = null
var _cycle: Node = null
var _anchors: Array = []        # [{node: Spatial, flat: Vector3}]
var _segment_bodies: Array = [] # [{node: Spatial, ia: int, ib: int}]
var _spine_flat: Array = []     # puntos flat de la espiral
var _mode_bridge: StaticBody = null
var _rotor: Spatial = null
var _shortcuts: Array = []
var _glooSpan: Node = null
var _laserGate: Node = null
var _lights: Array = []
var _summit_flat := Vector3.ZERO
var _last_player_local_x := NAN
var _last_blend := -1.0
var _built := false

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	_sync_to_stream()
	_resolve_refs()
	_build()
	_built = true
	_project_all()

# Las poses proyectadas viven en el espacio local del stream (igual que las de
# los chunks). Si este nodo cuelga de la raíz del nivel, igualamos su transform
# al del stream para que su marco local coincida.
func _sync_to_stream() -> void:
	if stream_path.is_empty():
		return
	var stream = get_node_or_null(stream_path)
	if stream is Spatial:
		transform = (stream as Spatial).transform

func _resolve_refs() -> void:
	_rotator = get_node_or_null(rotator_path)
	if _rotator == null:
		var p: Node = get_parent()
		while p != null and _rotator == null:
			if p.has_method("project_flat_point"):
				_rotator = p
				break
			p = p.get_parent()
	_cycle = get_node_or_null(cycle_path)
	_resolve_lights()

func _resolve_lights() -> void:
	_lights.clear()
	var root = get_node_or_null(lights_path) if not lights_path.is_empty() else null
	if root == null:
		root = get_parent().get_node_or_null("BayLights") if get_parent() != null else null
	if root == null:
		return
	var stack: Array = [root]
	while not stack.empty():
		var n = stack.pop_back()
		if n is Light:
			_lights.append(n)
		for c in n.get_children():
			stack.push_back(c)

# ── Construcción ─────────────────────────────────────────────────────────────

func _build() -> void:
	_compute_spine_flat()
	_build_spine()
	_build_summit()
	_build_laser_gate()
	_build_gloo_span()
	_build_conveyor()
	_build_mode_bridge()
	_build_rotor()
	if _cycle != null and _cycle.has_signal("phase_changed"):
		_cycle.connect("phase_changed", self, "_on_phase_changed")
		if _cycle.has_method("get_phase"):
			_apply_phase_lights(int(_cycle.get_phase()))
	emit_signal("content_ready")

func _base_radius() -> float:
	if _rotator != null and "base_radius" in _rotator:
		return float(_rotator.base_radius)
	return 48.0

# Puntos flat de la espiral: arco creciente (vuelta angular) y radio decreciente
# (radial hacia el eje = "subir"). flat.y va de 0 (anillo exterior) a
# base_radius - summit_clearance (borde de la cima, casi en el eje).
func _compute_spine_flat() -> void:
	_spine_flat.clear()
	var base_radius: float = _base_radius()
	var total_arc: float = float(turns) * TAU * base_radius
	var top_radial: float = max(1.0, base_radius - summit_clearance)
	var n: int = max(2, spine_segments)
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		_spine_flat.append(Vector3(t * total_arc, t * top_radial, 0.0))

func _segment_len() -> float:
	if _spine_flat.size() > 1:
		return _spine_flat[1].distance_to(_spine_flat[0])
	return 4.0

func _is_gap_segment(i: int) -> bool:
	var n: int = max(2, spine_segments)
	var center: float = gloo_gap_ratio * float(n)
	var half: float = float(gloo_gap_segments) * 0.5
	return abs(float(i) + 0.5 - center) <= half

func _build_spine() -> void:
	var mat := _make_material(Color(0.34, 0.38, 0.43), 0.35, 0.7)
	var rail_mat := _make_material(Color(0.22, 0.25, 0.29), 0.4, 0.6)
	var n: int = max(2, spine_segments)
	var seg_len: float = _segment_len()
	for i in range(n):
		if _is_gap_segment(i):
			continue
		var body := StaticBody.new()
		body.name = "Spine_%02d" % i
		body.collision_layer = COLLISION_LAYER_ENV
		body.collision_mask = 255
		var plate := MeshInstance.new()
		var box := CubeMesh.new()
		box.size = Vector3(walkway_width, walkway_thickness, seg_len * 1.12)
		plate.mesh = box
		plate.material_override = mat
		body.add_child(plate)
		var col := CollisionShape.new()
		var colbox := BoxShape.new()
		colbox.extents = Vector3(walkway_width * 0.5, walkway_thickness * 0.5, seg_len * 0.56)
		col.shape = colbox
		body.add_child(col)
		for side in [-1.0, 1.0]:
			var rail := MeshInstance.new()
			var rbox := CubeMesh.new()
			rbox.size = Vector3(0.1, 0.7, seg_len * 1.12)
			rail.mesh = rbox
			rail.material_override = rail_mat
			rail.translation = Vector3(side * walkway_width * 0.5, 0.45, 0.0)
			body.add_child(rail)
		add_child(body)
		_segment_bodies.append({"node": body, "ia": i, "ib": i + 1})

func _build_summit() -> void:
	var base_radius: float = _base_radius()
	var top: int = _spine_flat.size() - 1
	_summit_flat = Vector3(_spine_flat[top].x, max(1.0, base_radius - summit_clearance * 0.4), 0.0)
	var anchor := _add_anchor("Summit", _summit_flat)
	var platform := StaticBody.new()
	platform.collision_layer = COLLISION_LAYER_ENV
	platform.collision_mask = 255
	var disc := CylinderMesh.new()
	disc.top_radius = 5.5
	disc.bottom_radius = 5.5
	disc.height = 0.4
	var pmesh := MeshInstance.new()
	pmesh.mesh = disc
	pmesh.material_override = _make_material(Color(0.24, 0.28, 0.33), 0.4, 0.6)
	platform.add_child(pmesh)
	var col := CollisionShape.new()
	var cyl := CylinderShape.new()
	cyl.radius = 5.5
	cyl.height = 0.4
	col.shape = cyl
	platform.add_child(col)
	anchor.add_child(platform)
	# Sala de control (lectura de destino, sin texto).
	var room := MeshInstance.new()
	var rbox := CubeMesh.new()
	rbox.size = Vector3(4.0, 2.4, 4.0)
	room.mesh = rbox
	room.material_override = _make_material(Color(0.2, 0.23, 0.28), 0.5, 0.5, Color(0.25, 0.55, 0.8), 0.4)
	room.translation = Vector3(0.0, 1.4, -1.4)
	anchor.add_child(room)
	# Baliza visible desde todo el anillo.
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.16
	pillar.bottom_radius = 0.24
	pillar.height = 5.0
	var beacon := MeshInstance.new()
	beacon.mesh = pillar
	beacon.material_override = _make_material(Color(1.0, 0.82, 0.5), 0.0, 1.0, Color(1.0, 0.78, 0.4), 2.6)
	beacon.translation = Vector3(0.0, 2.7, 1.6)
	beacon.add_to_group("no_occlusion")
	anchor.add_child(beacon)
	var blight := OmniLight.new()
	blight.omni_range = 9.0
	blight.light_color = Color(1.0, 0.82, 0.5)
	blight.light_energy = 1.8
	blight.shadow_enabled = false
	beacon.add_child(blight)

func _build_laser_gate() -> void:
	var n: int = max(2, spine_segments)
	var i: int = int(clamp(laser_ratio * float(n), 1.0, float(n - 2)))
	_laserGate = LaserGateScript.new()
	_laserGate.name = "ShortcutLaserGate"
	_laserGate.cut_time = 2.0
	var anchor := _add_anchor("LaserAnchor", _spine_flat[i + 1])
	anchor.add_child(_laserGate)
	_shortcuts.append(_laserGate)

func _build_gloo_span() -> void:
	var n: int = max(2, spine_segments)
	var center: int = int(gloo_gap_ratio * float(n))
	var half: int = int(max(1, gloo_gap_segments) * 0.5)
	var i0: int = int(clamp(float(center - half - 1), 0.0, float(n - 1)))
	var i1: int = int(clamp(float(center + half), 0.0, float(n)))
	_glooSpan = GlooSpanScript.new()
	_glooSpan.name = "ShortcutGlooSpan"
	_glooSpan.required_blobs = 2
	_glooSpan.span_height = 0.2
	_glooSpan.bridge_width = walkway_width * 0.5
	_glooSpan.set_meta("flat_a", _spine_flat[i0])
	_glooSpan.set_meta("flat_b", _spine_flat[i1])
	# El GlooSpan se ubica solo a partir de span_from/span_to (world); no cuelga de
	# un anchor proyectado para no pelear con esa transformación.
	add_child(_glooSpan)
	_shortcuts.append(_glooSpan)

func _build_conveyor() -> void:
	# Cinta-caja: un tramo con una caja que ayuda a trepar. Caja ESTÁTICA (no un
	# cuerpo rígido bajo un padre re-proyectado cada frame, que la haría saltar).
	var n: int = max(2, spine_segments)
	var i: int = int(clamp(conveyor_ratio * float(n), 1.0, float(n - 2)))
	var anchor := _add_anchor("ConveyorAnchor", _spine_flat[i])
	var body := StaticBody.new()
	body.name = "CrateAnchor"
	body.collision_layer = COLLISION_LAYER_ENV
	body.collision_mask = 255
	var mesh := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	mesh.mesh = box
	mesh.material_override = _make_material(Color(0.45, 0.4, 0.28), 0.3, 0.8)
	mesh.translation = Vector3(0.0, 0.7, 0.0)
	body.add_child(mesh)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(0.7, 0.7, 0.7)
	col.shape = colbox
	col.translation = Vector3(0.0, 0.7, 0.0)
	body.add_child(col)
	anchor.add_child(body)
	_shortcuts.append(body)

func _build_mode_bridge() -> void:
	# Atajo que EXISTE en un solo modo: en propulsión (blend 0) es sólido y
	# atraviesa un tramo; en centrífugo se desolidifica (el recorrido curvo es el
	# camino). Anclado a la espiral, así está conectado al recorrido real.
	var n: int = max(2, spine_segments)
	var i: int = int(clamp(bridge_ratio * float(n), 1.0, float(n - 2)))
	var seg_len: float = _segment_len()
	var body := StaticBody.new()
	body.name = "ModeBridge"
	body.collision_layer = COLLISION_LAYER_ENV
	body.collision_mask = 255
	var mesh := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(walkway_width * 0.8, 0.2, seg_len * 2.4)
	mesh.mesh = box
	mesh.material_override = _make_material(Color(0.6, 0.52, 0.22), 0.3, 0.7, Color(0.9, 0.75, 0.3), 0.6)
	body.add_child(mesh)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(walkway_width * 0.4, 0.1, seg_len * 1.2)
	col.shape = colbox
	body.add_child(col)
	var anchor := _add_anchor("BridgeAnchor", _spine_flat[i])
	anchor.add_child(body)
	_mode_bridge = body

func _build_rotor() -> void:
	var n: int = max(2, spine_segments)
	var i: int = int(clamp(rotor_ratio * float(n), 1.0, float(n - 1)))
	var anchor := _add_anchor("RotorAnchor", _spine_flat[i])
	var spin := Spatial.new()
	spin.name = "RotorSpin"
	anchor.add_child(spin)
	var arm := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(walkway_width * 0.9, 0.18, 1.6)
	arm.mesh = box
	arm.material_override = _make_material(Color(0.85, 0.2, 0.12), 0.3, 0.8, Color(0.9, 0.25, 0.15), 1.4)
	arm.translation = Vector3(0.0, 0.95, 0.0)
	spin.add_child(arm)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(walkway_width * 0.45, 0.09, 0.8)
	col.shape = colbox
	spin.add_child(col)
	_rotor = spin

func _add_anchor(node_name: String, flat: Vector3) -> Spatial:
	var anchor := Spatial.new()
	anchor.name = node_name
	add_child(anchor)
	_anchors.append({"node": anchor, "flat": flat})
	return anchor

# ── Proyección / modo ────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _built:
		return
	if _rotator == null or not is_instance_valid(_rotator):
		_resolve_refs()
		if _rotator == null:
			return
	# El rotor gira de forma determinista a partir del reloj del ciclo (no un
	# timer propio): mismo estado -> misma pose.
	_animate_hazards()
	var player_local_x: float = _player_local_x()
	var blend: float = float(_rotator.get_spiral_blend()) if _rotator.has_method("get_spiral_blend") else 1.0
	if not is_nan(_last_player_local_x) and abs(player_local_x - _last_player_local_x) < 0.05 and abs(blend - _last_blend) < 0.001:
		return
	_last_player_local_x = player_local_x
	_last_blend = blend
	_project_all()

func _player_local_x() -> float:
	if _rotator == null:
		return 0.0
	if _rotator.has_method("_get_player_local_x"):
		return float(_rotator.call("_get_player_local_x"))
	return 0.0

func _project_point(flat: Vector3) -> Transform:
	if _rotator == null or not _rotator.has_method("project_flat_point"):
		return Transform(Basis.IDENTITY, flat)
	return _rotator.call("project_flat_point", flat)

func _project_all() -> void:
	for entry in _anchors:
		var node: Spatial = entry["node"]
		if is_instance_valid(node):
			node.transform = _project_point(entry["flat"])
	for entry in _segment_bodies:
		_project_segment(entry)
	_project_gloo_span()
	_apply_mode_to_content()

func _project_gloo_span() -> void:
	if _glooSpan == null or not is_instance_valid(_glooSpan):
		return
	if not _glooSpan.has_meta("flat_a"):
		return
	_glooSpan.span_from = project_flat_world(_glooSpan.get_meta("flat_a"))
	_glooSpan.span_to = project_flat_world(_glooSpan.get_meta("flat_b"))
	if _glooSpan.has_method("refresh_span"):
		_glooSpan.call("refresh_span")

# ── API para la escena: proyectar un nodo externo (p. ej. los buffers) ────────

func place_projected(node: Spatial, flat: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	_anchors.append({"node": node, "flat": flat})
	node.transform = _project_point(flat)

func project_flat_world(flat: Vector3) -> Vector3:
	if _rotator == null or not _rotator.has_method("project_flat_point"):
		return flat
	var local: Vector3 = _rotator.call("project_flat_point", flat).origin
	return _rotator.global_transform.xform(local)

func _project_segment(entry: Dictionary) -> void:
	var body: Spatial = entry["node"]
	if not is_instance_valid(body):
		return
	var ia: int = entry["ia"]
	var ib: int = entry["ib"]
	if ib >= _spine_flat.size():
		return
	var ta := _project_point(_spine_flat[ia])
	var tb := _project_point(_spine_flat[ib])
	var mid: Vector3 = (ta.origin + tb.origin) * 0.5
	var up: Vector3 = ta.basis.y.normalized()
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	var fwd: Vector3 = (tb.origin - ta.origin)
	if fwd.length_squared() < 0.0001:
		body.transform = Transform(Basis.IDENTITY, mid)
		return
	var z: Vector3 = (fwd - up * fwd.dot(up)).normalized()
	var x: Vector3 = up.cross(z).normalized()
	body.transform = Transform(Basis(x, up, z), mid)

func _apply_mode_to_content() -> void:
	var blend: float = 1.0
	if _rotator != null and _rotator.has_method("get_spiral_blend"):
		blend = float(_rotator.call("get_spiral_blend"))
	# El puente existe SOLO en propulsión (blend ~ 0).
	var thrust: bool = blend <= 0.001
	if _mode_bridge != null and is_instance_valid(_mode_bridge):
		_mode_bridge.collision_layer = COLLISION_LAYER_ENV if thrust else 0
		_mode_bridge.visible = thrust

func _on_phase_changed(phase: int) -> void:
	_apply_phase_lights(phase)

# El ciclo pinta la sala (SAFE/WARNING/DANGER) y habilita el rotor: es su
# consumidor real, no solo una conexión.
func _apply_phase_lights(phase: int) -> void:
	var color: Color = Color(0.55, 0.8, 1.0)
	var energy := 1.7
	if phase == 1:  # WARNING
		color = Color(1.0, 0.72, 0.25)
		energy = 2.6
	elif phase == 2:  # DANGER
		color = Color(1.0, 0.22, 0.14)
		energy = 3.4
	for light in _lights:
		if not is_instance_valid(light):
			continue
		light.light_color = color
		light.light_energy = energy

func _animate_hazards() -> void:
	if _rotor == null or not is_instance_valid(_rotor):
		return
	if _cycle == null or not _cycle.has_method("get_elapsed"):
		return
	_rotor.rotation.z = float(_cycle.get_elapsed()) * 2.2

func get_light_count() -> int:
	return _lights.size()

func get_active_phase() -> int:
	if _cycle != null and _cycle.has_method("get_phase"):
		return int(_cycle.get_phase())
	return -1

# ── Acceso para tests / depuración ───────────────────────────────────────────

func is_mode_bridge_solid() -> bool:
	return _mode_bridge != null and is_instance_valid(_mode_bridge) and _mode_bridge.collision_layer != 0

func get_spine_world_points() -> Array:
	var out: Array = []
	for flat in _spine_flat:
		out.append(_project_point(flat).origin)
	return out

func get_spine_flat_points() -> Array:
	return _spine_flat.duplicate()

func get_summit_flat() -> Vector3:
	return _summit_flat

func get_gloo_span() -> Node:
	return _glooSpan

func get_laser_gate() -> Node:
	return _laserGate

func get_shortcuts() -> Array:
	return _shortcuts

func get_rotor() -> Spatial:
	return _rotor

func get_segment_count() -> int:
	return _segment_bodies.size()

func _make_material(albedo: Color, metallic: float, roughness: float, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0) -> SpatialMaterial:
	var mat := SpatialMaterial.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy = emission_energy
	return mat

# ── Estado serializable (replay + save) ──────────────────────────────────────

func get_snapshot() -> Dictionary:
	var states := []
	for shortcut in _shortcuts:
		if is_instance_valid(shortcut) and shortcut.has_method("get_state"):
			states.append({"name": shortcut.name, "state": shortcut.get_state()})
	return {"seed": generation_seed, "shortcuts": states}

func restore_snapshot(data: Dictionary) -> void:
	var states: Array = data.get("shortcuts", [])
	for entry in states:
		var n: String = entry.get("name", "")
		var st = entry.get("state", {})
		for shortcut in _shortcuts:
			if is_instance_valid(shortcut) and shortcut.name == n and shortcut.has_method("restore_state"):
				shortcut.restore_state(st)
