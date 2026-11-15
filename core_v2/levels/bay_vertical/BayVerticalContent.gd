extends Spatial

# Capa de CONTENIDO CURADO de la bahía radial (FD-322), montada SOBRE la
# proyección del `ScaffoldStreamController` + `CylinderRotator`, y calibrada con
# el presupuesto de FLOW del Transit-Run (`BayTransitFlow`, contrato
# `docs/canon/WFC_FLOW_METRICS.md`).
#
# Reglas del contrato (Sebastián, 2026-11-15):
#   - la RUTA PRINCIPAL se calibra a `v_run` y NUNCA se bloquea con un puzle: es
#     una espiral continua cuya altura por tramo (`step_rise`) y cuyos huecos
#     (`SprintGap`) salen del presupuesto (huecos ≤ 70-80 % del alcance);
#   - los ATAJOS CURADOS son Side Sockets OPCIONALES (90-100 % del alcance) con
#     su técnica (gloo, láser, mag-rail) y etiqueta de chunk;
#   - el roll-jump es técnica de habilidad, no requisito (ningún hueco lo exige).
#
# Los huecos y alturas NO están hardcodeados: se derivan de `BayTransitFlow`, que
# lee `g` del anillo (g(r) = ω²·r, `GravityWorld.ship_angular_velocity_rad_s`) y
# los alcances del contrato cuando aterriza; si no, usa sus fallbacks.
#
# El contenido se ancla en el plano del stream (flat: x = arco, y = radial hacia
# el eje, z = axial) y se proyecta cada frame con
# `BayCylinderRotator.project_flat_point()`, así queda SOBRE los chunks y sigue
# tanto la rotación del cilindro como el cambio de modo.
#
# Determinismo: todo deriva del presupuesto + `generation_seed` (sin `randf`).

const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")
const FlowScript := preload("res://core_v2/levels/bay_vertical/BayTransitFlow.gd")
const ValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const COLLISION_LAYER_ENV := 1

export(int) var generation_seed := 20261114
export(NodePath) var rotator_path := NodePath("")
export(NodePath) var cycle_path := NodePath("")
export(NodePath) var stream_path := NodePath("")
export(NodePath) var lights_path := NodePath("")
# Contrato de flow (opcional): vacío = ruta por defecto del presupuesto.
export(String) var flow_contract_path := ""
# Overrides del presupuesto (0 / -1 = derivar del contrato).
export(int) var spine_segments := 0
export(float) var walkway_width := 4.2
export(float) var walkway_thickness := 0.3
export(float, 2.0, 20.0) var summit_clearance := 8.0
# Cada cuántos tramos de la ruta principal hay un SprintGap (ritmo).
export(int, 2, 12) var sprint_gap_every := 5
export(float) var socket_radial_offset := 6.0

signal content_ready()

var _flow = null
var _rotator: Node = null
var _cycle: Node = null
var _anchors: Array = []        # [{node: Spatial, flat: Vector3}]
var _segment_bodies: Array = [] # [{node: Spatial, ia: int, ib: int, label: String}]
var _spine_flat: Array = []     # puntos flat de la espiral (ruta principal)
var _main_gaps: Array = []      # longitudes (flat) de los SprintGap de la ruta principal
var _sockets: Array = []        # [{name, label, nodes: Array}]
var _mode_bridge: StaticBody = null
var _mag_rail_nodes: Array = []
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
	if root == null and get_parent() != null:
		root = get_parent().get_node_or_null("BayLights")
	if root == null:
		return
	var stack: Array = [root]
	while not stack.empty():
		var n = stack.pop_back()
		if n is Light:
			_lights.append(n)
		for c in n.get_children():
			stack.push_back(c)

# ── Presupuesto de flow ──────────────────────────────────────────────────────

func _build_flow() -> void:
	_flow = FlowScript.new()
	if not flow_contract_path.empty():
		_flow.load_contract(flow_contract_path)
	# g del anillo: g(r) = ω²·r con el giro real del barco.
	_flow.configure_gravity_from_world(get_node_or_null("/root/GravityWorld"), _base_radius())

func get_flow():
	return _flow

func get_flow_describe() -> Dictionary:
	return _flow.describe() if _flow != null else {}

# ── Construcción ─────────────────────────────────────────────────────────────

func _build() -> void:
	_build_flow()
	_compute_spine_flat()
	_build_spine()
	_build_summit()
	_build_sockets()
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

# Ruta principal derivada del presupuesto: un tramo por `main_route_gap()` de
# arco. En cada SprintGap el arco avanza pero la altura NO sube, así el hueco
# queda AL MISMO NIVEL (delta_h = 0) y el salto entra en el umbral main, tal como
# mide el contrato (hueco al mismo nivel ≤ 80 % del alcance).
func _compute_spine_flat() -> void:
	_spine_flat.clear()
	_main_gaps.clear()
	var base_radius: float = _base_radius()
	var total_rise: float = max(4.0, base_radius - summit_clearance)
	var step: float = max(0.5, _flow.step_rise())
	var seg_arc: float = max(2.0, _flow.main_route_gap())
	var max_steps: int = spine_segments if spine_segments > 0 else 256
	var pts: Array = [Vector3.ZERO]
	var x := 0.0
	var y := 0.0
	var k := 0
	while y < total_rise - 0.001 and k < max_steps:
		var gap: bool = _is_sprint_gap(k)
		x += seg_arc
		if not gap:
			y += step
		pts.append(Vector3(x, min(y, total_rise), 0.0))
		k += 1
	_spine_flat = pts

func _seg_index_of(node: Spatial) -> Dictionary:
	for e in _segment_bodies:
		if e["node"] == node:
			return e
	return {}

func _segment_len() -> float:
	if _spine_flat.size() > 1:
		return _spine_flat[1].distance_to(_spine_flat[0])
	return 4.0

# SprintGap de la ruta principal: se omite la placa cada `sprint_gap_every`
# tramos. NO es un puzle: el hueco queda al 70-80 % del alcance (salto a v_run).
func _is_sprint_gap(i: int) -> bool:
	return sprint_gap_every > 0 and (i % sprint_gap_every) == (sprint_gap_every - 1)

func _build_spine() -> void:
	var mat := _make_material(Color(0.34, 0.38, 0.43), 0.35, 0.7)
	var rail_mat := _make_material(Color(0.22, 0.25, 0.29), 0.4, 0.6)
	var gap := 0.0
	var n: int = _spine_flat.size() - 1
	var seg_len: float = _segment_len()
	for i in range(n):
		if _is_sprint_gap(i):
			# Distancia real del tramo omitido (el hueco queda al mismo nivel).
			gap += _spine_flat[i + 1].distance_to(_spine_flat[i])
			continue
		if gap > 0.0:
			_main_gaps.append(gap)
			gap = 0.0
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
		body.set_meta("flow_label", "RhythmSteps" if (i % sprint_gap_every) != 0 else "SprintGap")
		add_child(body)
		_segment_bodies.append({"node": body, "ia": i, "ib": i + 1, "label": String(body.get_meta("flow_label"))})

func _build_summit() -> void:
	var top: int = _spine_flat.size() - 1
	# La cima se ancla al ÚLTIMO punto de la espiral (mismo nivel y arco) para que
	# el tramo final sea alcanzable y la cima quede junto al eje.
	_summit_flat = Vector3(_spine_flat[top].x, _spine_flat[top].y, 0.0)
	var anchor := _add_anchor("Summit", _summit_flat)
	anchor.set_meta("flow_label", "CuratedSocket")
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
	var room := MeshInstance.new()
	var rbox := CubeMesh.new()
	rbox.size = Vector3(4.0, 2.4, 4.0)
	room.mesh = rbox
	room.material_override = _make_material(Color(0.2, 0.23, 0.28), 0.5, 0.5, Color(0.25, 0.55, 0.8), 0.4)
	room.translation = Vector3(0.0, 1.4, -1.4)
	anchor.add_child(room)
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

# ── Side Sockets (atajos OPCIONALES) ─────────────────────────────────────────

# Índice de la espiral para un socket, desplazado por semilla (variación por
# partida sin tocar la ruta principal).
func _socket_index(fraction: float) -> int:
	var n: int = _spine_flat.size() - 1
	var base := int(round(fraction * float(n)))
	var jitter: int = (generation_seed / 7) % 3
	return int(clamp(float(base + jitter), 1.0, float(max(1, n - 1))))

# Tres sockets curados con su técnica y etiqueta. Todos son OPCIONALES: la ruta
# principal sigue siendo transitable por sí sola.
func _build_sockets() -> void:
	var n: int = _spine_flat.size() - 1
	if n < 12:
		return
	_build_gloo_climb()
	_build_laser_socket(_socket_index(0.30), _socket_index(0.30) + 3)
	_build_mag_rail_socket(_socket_index(0.62), _socket_index(0.62) + 4)
	_build_crate_socket(_socket_index(0.16))

func _add_socket(name: String, label: String, nodes: Array) -> void:
	_sockets.append({"name": name, "label": label, "nodes": nodes})

func _build_gloo_climb() -> void:
	var n: int = _spine_flat.size() - 1
	var gap_i: int = -1
	for i in range(n):
		if _is_sprint_gap(i):
			gap_i = i
			break
	if gap_i < 0:
		return
	_glooSpan = GlooSpanScript.new()
	_glooSpan.name = "ShortcutGlooSpan"
	_glooSpan.required_blobs = 2
	_glooSpan.span_height = 0.2
	_glooSpan.bridge_width = walkway_width * 0.5
	_glooSpan.set_meta("flat_a", _spine_flat[gap_i])
	_glooSpan.set_meta("flat_b", _spine_flat[gap_i + 1])
	_glooSpan.set_meta("flow_label", "GlooClimb")
	add_child(_glooSpan)
	_shortcuts.append(_glooSpan)
	_add_socket("GlooClimb", "GlooClimb", [_glooSpan])

# Raíl paralelo elevado entre dos índices de la espiral, con su técnica.
func _build_socket_rail(name: String, i0: int, i1: int, label: String, mat: SpatialMaterial) -> Array:
	i0 = int(clamp(float(i0), 0.0, float(_spine_flat.size() - 2)))
	i1 = int(clamp(float(i1), float(i0 + 1), float(_spine_flat.size() - 1)))
	var nodes: Array = []
	var seg_len: float = _segment_len()
	for k in range(i0, i1):
		var a: Vector3 = _spine_flat[k] + Vector3(0.0, socket_radial_offset, 0.0)
		var b: Vector3 = _spine_flat[k + 1] + Vector3(0.0, socket_radial_offset, 0.0)
		var body := StaticBody.new()
		body.name = "%s_%02d" % [name, k]
		body.collision_layer = COLLISION_LAYER_ENV
		body.collision_mask = 255
		var mesh := MeshInstance.new()
		var box := CubeMesh.new()
		box.size = Vector3(walkway_width * 0.75, walkway_thickness, seg_len * 1.05)
		mesh.mesh = box
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape.new()
		var colbox := BoxShape.new()
		colbox.extents = Vector3(walkway_width * 0.375, walkway_thickness * 0.5, seg_len * 0.525)
		col.shape = colbox
		body.add_child(col)
		body.set_meta("flow_label", label)
		add_child(body)
		var mid: Vector3 = (a + b) * 0.5
		_register_projected(body, mid)
		_segment_bodies.append({"node": body, "flat_a": a, "flat_b": b, "label": label})
		nodes.append(body)
	return nodes

func _build_laser_socket(i0: int, i1: int) -> void:
	var mat := _make_material(Color(0.4, 0.34, 0.2), 0.4, 0.6)
	var nodes := _build_socket_rail("LaserSocket", i0, i1, "CuratedSocket", mat)
	if nodes.empty():
		return
	var gate_flat: Vector3 = _spine_flat[i0] + Vector3(0.0, socket_radial_offset, 0.0)
	var anchor := _add_anchor("LaserSocketGate", gate_flat)
	anchor.set_meta("flow_label", "CuratedSocket")
	_laserGate = LaserGateScript.new()
	_laserGate.name = "ShortcutLaserGate"
	_laserGate.cut_time = 2.0
	anchor.add_child(_laserGate)
	_shortcuts.append(_laserGate)
	nodes.append(_laserGate)
	_add_socket("CuratedSocket", "CuratedSocket", nodes)

func _build_mag_rail_socket(i0: int, i1: int) -> void:
	var mat := _make_material(Color(0.6, 0.52, 0.22), 0.3, 0.7, Color(0.9, 0.75, 0.3), 0.6)
	var nodes := _build_socket_rail("MagRail", i0, i1, "MagRail", mat)
	if nodes.empty():
		return
	_mag_rail_nodes = nodes
	_mode_bridge = nodes[0] if nodes[0] is StaticBody else null
	_add_socket("MagRail", "MagRail", nodes)

func _build_crate_socket(i: int) -> void:
	i = int(clamp(float(i), 0.0, float(_spine_flat.size() - 2)))
	var anchor := _add_anchor("CrateSocket", _spine_flat[i])
	anchor.set_meta("flow_label", "CuratedSocket")
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
	_add_socket("CuratedSocket", "CuratedSocket", [anchor])

func _build_rotor() -> void:
	var n: int = _spine_flat.size() - 1
	var i: int = int(clamp(float(n) * 0.78, 1.0, float(n - 1)))
	var anchor := _add_anchor("RotorAnchor", _spine_flat[i])
	anchor.set_meta("flow_label", "CuratedSocket")
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

func _register_projected(node: Spatial, flat: Vector3) -> void:
	_anchors.append({"node": node, "flat": flat})

# ── Proyección / modo ────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _built:
		return
	if _rotator == null or not is_instance_valid(_rotator):
		_resolve_refs()
		if _rotator == null:
			return
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

func _project_segment(entry: Dictionary) -> void:
	var body: Spatial = entry["node"]
	if not is_instance_valid(body):
		return
	var ta: Transform
	var tb: Transform
	if entry.has("flat_a"):
		ta = _project_point(entry["flat_a"])
		tb = _project_point(entry["flat_b"])
	else:
		var ia: int = entry["ia"]
		var ib: int = entry["ib"]
		if ib >= _spine_flat.size():
			return
		ta = _project_point(_spine_flat[ia])
		tb = _project_point(_spine_flat[ib])
	var mid: Vector3 = (ta.origin + tb.origin) * 0.5
	var fwd: Vector3 = tb.origin - ta.origin
	if fwd.length_squared() < 0.0001:
		body.transform = Transform(Basis.IDENTITY, mid)
		return
	# La placa sigue AMBOS extremos: +Z a lo largo del tramo (incluye la subida) y
	# +Y es la normal de la superficie, así el recorrido es una RAMPA continua y no
	# una escalera de peldaños (que el jugador no podría subir caminando).
	var z: Vector3 = fwd.normalized()
	var up_ref: Vector3 = ta.basis.y.normalized()
	if up_ref.length_squared() < 0.0001:
		up_ref = Vector3.UP
	var x: Vector3 = up_ref.cross(z)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	var y: Vector3 = z.cross(x).normalized()
	body.transform = Transform(Basis(x, y, z), mid)

func _apply_mode_to_content() -> void:
	var blend: float = 1.0
	if _rotator != null and _rotator.has_method("get_spiral_blend"):
		blend = float(_rotator.call("get_spiral_blend"))
	# El MagRail (atajo Opcional) existe SOLO en propulsión (blend ~ 0).
	var thrust: bool = blend <= 0.001
	for node in _mag_rail_nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node is CollisionObject:
			node.collision_layer = COLLISION_LAYER_ENV if thrust else 0
		if node is Spatial:
			node.visible = thrust

func _on_phase_changed(phase: int) -> void:
	_apply_phase_lights(phase)

# El ciclo pinta la sala (SAFE/WARNING/DANGER) y habilita el rotor: es su
# consumidor real, no solo una conexión.
func _apply_phase_lights(phase: int) -> void:
	var color: Color = Color(0.55, 0.8, 1.0)
	var energy := 1.7
	if phase == 1:
		color = Color(1.0, 0.72, 0.25)
		energy = 2.6
	elif phase == 2:
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

# ── API para la escena / tests ───────────────────────────────────────────────

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

# Longitudes (en el plano flat) de los huecos de la RUTA PRINCIPAL. Todas deben
# caer dentro del umbral de flow principal.
func get_main_route_gaps() -> Array:
	return _main_gaps.duplicate()

func get_main_route_gap_limit() -> float:
	return _flow.main_route_gap() if _flow != null else 0.0

func get_known_labels() -> Array:
	var labels := {}
	for entry in _segment_bodies:
		labels[String(entry.get("label", ""))] = true
	for s in _sockets:
		labels[String(s["label"])] = true
	return labels.keys()

func get_sockets() -> Array:
	return _sockets.duplicate()

func get_socket_labels() -> Array:
	var out: Array = []
	for s in _sockets:
		out.append(String(s["label"]))
	return out

# ── Validación de flow (delegada a FlowRouteValidator) ───────────────────────

func _segment_flat_center(i: int) -> Vector3:
	if i + 1 < _spine_flat.size():
		return (_spine_flat[i] + _spine_flat[i + 1]) * 0.5
	return _spine_flat[i]

func _main_plate_entries() -> Array:
	var out: Array = []
	for entry in _segment_bodies:
		if entry.has("ia"):
			out.append(entry)
	return out

# Grafo de la ruta principal en el MARCO DEL CILINDRO (flat): ahí el "horizontal"
# es el arco y el "up" es el radial, que es como camina el jugador en el anillo.
func build_route_graph() -> Dictionary:
	var entries := _main_plate_entries()
	var nodes: Array = []
	var edges: Array = []
	var seg_len: float = _segment_len()
	for entry in entries:
		var ia: int = entry["ia"]
		nodes.append({
			"id": "s%d" % ia,
			"position": _segment_flat_center(ia),
			"size": Vector3(seg_len, 0.0, walkway_width),
			"g": _flow.g if _flow != null else 14.0,
		})
	nodes.append({"id": "summit", "position": _summit_flat, "size": 5.5,
		"g": _flow.g if _flow != null else 14.0})
	# Aristas = salto FÍSICO de una placa a la siguiente. Contiguas se tocan
	# (hueco 0); con un SprintGap en el medio, el hueco es el tramo omitido, que
	# por construcción está al mismo nivel (delta_h = 0).
	for k in range(entries.size() - 1):
		var ia: int = entries[k]["ia"]
		var ib: int = entries[k + 1]["ia"]
		var gap_h := 0.0
		var dh := 0.0
		if ib > ia + 1:
			for j in range(ia + 1, ib):
				var a: Vector3 = _spine_flat[j]
				var b: Vector3 = _spine_flat[j + 1]
				gap_h += abs(b.x - a.x)
				dh += b.y - a.y
		edges.append({"from": "s%d" % ia, "to": "s%d" % ib,
			"gap_horizontal": gap_h, "delta_h": dh})
	if not entries.empty():
		# La cima se ancla al último punto de la espiral: el tramo final se toca.
		edges.append({"from": "s%d" % entries[-1]["ia"], "to": "summit",
			"gap_horizontal": 0.0, "delta_h": 0.0})
	return {
		"nodes": nodes,
		"edges": edges,
		"entry": "s%d" % entries[0]["ia"] if not entries.empty() else "",
		"exit": "summit",
	}

# Valida que exista una ruta principal entrada->cima SOLO con saltos dentro del
# umbral main (sin herramientas ni sockets), con las métricas del contrato.
func validate_main_route() -> Dictionary:
	if _flow == null:
		return {}
	return ValidatorScript.validate(build_route_graph(), _flow.metrics())

# ¿Algún bloqueo con puzle (gloo/láser) está en la ruta principal? La ruta
# principal no debe tener ninguno: todos los gates viven en sockets.
func main_route_has_puzzle_blocker() -> bool:
	for entry in _segment_bodies:
		if not entry.has("ia"):
			continue
		var label := String(entry.get("label", ""))
		if label == "GlooClimb" or label == "CuratedSocket":
			return true
	return false

func get_gloo_span() -> Node:
	return _glooSpan

func get_laser_gate() -> Node:
	return _laserGate

func get_shortcuts() -> Array:
	return _shortcuts

func get_rotor() -> Spatial:
	return _rotor

func get_segment_count() -> int:
	var main := 0
	for entry in _segment_bodies:
		if entry.has("ia"):
			main += 1
	return main

# Nodos de la RUTA PRINCIPAL (placas), en orden.
func get_main_segment_nodes() -> Array:
	var out: Array = []
	for entry in _segment_bodies:
		if entry.has("ia"):
			out.append(entry["node"])
	return out

func get_light_count() -> int:
	return _lights.size()

func get_active_phase() -> int:
	if _cycle != null and _cycle.has_method("get_phase"):
		return int(_cycle.get_phase())
	return -1

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
	return {"seed": generation_seed, "shortcuts": states, "flow": get_flow_describe()}

func restore_snapshot(data: Dictionary) -> void:
	var states: Array = data.get("shortcuts", [])
	for entry in states:
		var n: String = entry.get("name", "")
		var st = entry.get("state", {})
		for shortcut in _shortcuts:
			if is_instance_valid(shortcut) and shortcut.name == n and shortcut.has_method("restore_state"):
				shortcut.restore_state(st)
