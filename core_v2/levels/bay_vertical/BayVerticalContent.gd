extends Spatial

# Capa de CONTENIDO CURADO de la bahía radial (FD-322 / pista E "Transit-Run"),
# montada SOBRE la proyección del `ScaffoldStreamController` + `CylinderRotator`.
#
# La RUTA PRINCIPAL es parkour real (no una rampa): una secuencia de plataformas
# separadas por saltos, dimensionados con el contrato `docs/canon/WFC_FLOW_METRICS.md`
# vía `BayTransitFlow` (que lee la física de `FlowMetrics` y el `g_eff(r) = ω²·r`
# del anillo):
#   - `RhythmSteps`: saltos de cadencia con subida radial (`rise ≤ 0.70·H_max`).
#   - `SprintGap`: cruce horizontal al mismo nivel (`gap ≤ 0.75·D_max`).
# Los dos quedan dentro de la banda 70-80 % del alcance: INV-1 del contrato.
#
# Los DESVÍOS CURADOS (cinta, láser, gloo, rotor) son Side Sockets OPCIONALES con
# recompensa cinética: nunca bloquean la ruta principal (INV-3). La cornisa/mantle
# y el GlooClimb viven SOLO en esos desvíos.
#
# Lenguaje visual fijo: la ruta principal va en LUZ CÁLIDA ESTABLE; los atajos
# llevan FRANJAS y LUZ FRÍA.
#
# Determinismo: todo deriva del presupuesto + `generation_seed` (sin `randf`).

const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")
const FlowScript := preload("res://core_v2/levels/bay_vertical/BayTransitFlow.gd")
const ValidatorScript := preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const COLLISION_LAYER_ENV := 1

# Lenguaje visual.
const COLOR_MAIN_LIGHT := Color(1.0, 0.82, 0.52)
const COLOR_SHORTCUT_LIGHT := Color(0.32, 0.78, 1.0)
const COLOR_SHORTCUT_STRIPE := Color(0.9, 0.75, 0.2)

signal slice_completed()
signal content_ready()

export(int) var generation_seed := 20261114
export(NodePath) var rotator_path := NodePath("")
export(NodePath) var cycle_path := NodePath("")
export(NodePath) var stream_path := NodePath("")
export(NodePath) var lights_path := NodePath("")
export(bool) var configure_ring_gravity := true
export(float) var walkway_width := 3.2
export(float) var platform_length := 3.0
export(float) var platform_thickness := 0.3
export(float, 4.0, 30.0) var summit_clearance := 6.0
# Cada cuántos saltos de ritmo se cruza un SprintGap horizontal.
export(int, 2, 8) var sprint_every := 4
export(float) var socket_radial_offset := 6.0

var _flow = null
var _rotator: Node = null
var _cycle: Node = null
var _anchors: Array = []          # [{node: Spatial, flat: Vector3}]
var _plates: Array = []           # [{node: Spatial, ia: int, kind: String}]
var _route: Array = []            # [{flat: Vector3, kind: String}]
var _hops: Array = []             # [{kind: String, gap: float, dh: float}]
var _main_gaps: Array = []
var _sockets: Array = []
var _mag_rail_nodes: Array = []
var _mode_bridge: StaticBody = null
var _rotor: Spatial = null
var _beacon: MeshInstance = null
var _shortcuts: Array = []
var _glooSpan: Node = null
var _laserGate: Node = null
var _lights: Array = []
var _summit_flat := Vector3.ZERO
var _last_player_local_x := NAN
var _last_blend := -1.0
var _built := false
var _slice_done := false

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

func _base_radius() -> float:
	if _rotator != null and "base_radius" in _rotator:
		return float(_rotator.base_radius)
	return 48.0

func _build_flow() -> void:
	_flow = FlowScript.new()
	var gw = get_node_or_null("/root/GravityWorld")
	var radius: float = _base_radius()
	var omega := 0.0
	if gw != null and "ship_angular_velocity_rad_s" in gw:
		if configure_ring_gravity:
			# Anillo a la gravedad del PILOTO (Jump.gravity): así g_eff(r) = ω²·r
			# queda calibrada con los valores medidos del contrato en la superficie.
			omega = sqrt(_flow.fm.gravity / max(radius, 0.001))
			gw.set_centrifugal_reference_radius(radius)
			gw.set_ship_angular_velocity(omega)
		else:
			omega = float(gw.ship_angular_velocity_rad_s)
	_flow.configure_ring(omega, radius)

func get_flow():
	return _flow

func get_flow_describe() -> Dictionary:
	return _flow.describe() if _flow != null else {}

# ── Construcción ─────────────────────────────────────────────────────────────

func _build() -> void:
	_build_flow()
	_compute_route()
	_build_route()
	_build_summit()
	_build_sockets()
	_build_rotor()
	if _cycle != null and _cycle.has_signal("phase_changed"):
		_cycle.connect("phase_changed", self, "_on_phase_changed")
		if _cycle.has_method("get_phase"):
			_apply_phase_lights(int(_cycle.get_phase()))
	emit_signal("content_ready")

# Ruta parkour en el plano del stream (flat: x = arco, y = radial hacia el eje).
# Cada salto se dimensiona con el `g_eff` del radio local; el hueco horizontal se
# recorta además contra el límite de la superficie, así cerca del eje no crece.
# Ritmo de la ruta por semilla: cuántos RhythmSteps hay entre dos SprintGap.
# Así el patrón del parkour varía por partida (y la validación por semilla es
# significativa) sin salirse nunca del presupuesto de flow.
func _rhythm_run_length() -> int:
	var span: int = int(max(2.0, float(sprint_every - 1)))
	var seed_i: int = int(abs(float(generation_seed)))
	return 2 + (seed_i % span)

func _compute_route() -> void:
	_route.clear()
	_hops.clear()
	_main_gaps.clear()
	var base_radius: float = _base_radius()
	var total_rise: float = max(4.0, base_radius - summit_clearance)
	var surface_gap_limit: float = _flow.main_gap(base_radius, 0.0)
	var rhythm_run: int = _rhythm_run_length()
	var cycle_len: int = rhythm_run + 1
	var x := 0.0
	var y := 0.0
	_route.append({"flat": Vector3(0.0, 0.0, 0.0), "kind": "RhythmSteps"})
	var step := 0
	while y < total_rise - 0.01 and _route.size() < 400:
		var r: float = _flow.radius_at(y)
		var is_sprint: bool = (step % cycle_len) == (cycle_len - 1)
		var gap: float
		var dh: float
		var kind: String
		if is_sprint:
			gap = min(_flow.main_gap(r, 0.0), surface_gap_limit)
			dh = 0.0
			kind = "SprintGap"
		else:
			dh = min(_flow.rhythm_rise(r), total_rise - y)
			gap = min(_flow.rhythm_gap(r, dh), surface_gap_limit)
			kind = "RhythmSteps"
		x += gap + platform_length
		if not is_sprint:
			y += dh
		_route.append({"flat": Vector3(x, y, 0.0), "kind": kind})
		_hops.append({"kind": kind, "gap": gap, "dh": dh})
		if is_sprint:
			_main_gaps.append(gap)
		step += 1

func _platform_kind_at(i: int) -> String:
	if i <= 0:
		return "RhythmSteps"
	if i - 1 < _hops.size():
		return String(_hops[i - 1]["kind"])
	return "RhythmSteps"

func _build_route() -> void:
	var walk_mat := _make_material(Color(0.36, 0.39, 0.43), 0.35, 0.7)
	var rail_mat := _make_material(Color(0.24, 0.27, 0.31), 0.4, 0.6)
	for i in range(_route.size()):
		var flat: Vector3 = _route[i]["flat"]
		var kind := _platform_kind_at(i)
		var body := StaticBody.new()
		body.name = "Platform_%02d" % i
		body.collision_layer = COLLISION_LAYER_ENV
		body.collision_mask = 255
		var plate := MeshInstance.new()
		var box := CubeMesh.new()
		box.size = Vector3(platform_length, platform_thickness, walkway_width)
		plate.mesh = box
		plate.material_override = walk_mat
		body.add_child(plate)
		var col := CollisionShape.new()
		var colbox := BoxShape.new()
		colbox.extents = Vector3(platform_length * 0.5, platform_thickness * 0.5, walkway_width * 0.5)
		col.shape = colbox
		body.add_child(col)
		for side in [-1.0, 1.0]:
			var rail := MeshInstance.new()
			var rbox := CubeMesh.new()
			rbox.size = Vector3(platform_length, 0.35, 0.08)
			rail.mesh = rbox
			rail.material_override = rail_mat
			rail.translation = Vector3(0.0, 0.28, side * walkway_width * 0.5)
			body.add_child(rail)
		body.set_meta("flow_kind", kind)
		# La ruta principal va en LUZ CÁLIDA ESTABLE: un bulbo tenue por plataforma.
		var lamp := OmniLight.new()
		lamp.light_color = COLOR_MAIN_LIGHT
		lamp.light_energy = 1.1
		lamp.omni_range = 7.0
		lamp.shadow_enabled = false
		lamp.translation = Vector3(0.0, 1.6, 0.0)
		body.add_child(lamp)
		add_child(body)
		_plates.append({"node": body, "ia": i, "kind": kind})
	_register_projected_plates()

# Las placas no se proyectan con un único pivote: cada una va a su punto flat.
func _register_projected_plates() -> void:
	for entry in _plates:
		var ia: int = entry["ia"]
		_anchors.append({"node": entry["node"], "flat": _route[ia]["flat"]})

func _build_summit() -> void:
	var top: int = _route.size() - 1
	_summit_flat = Vector3(_route[top]["flat"].x, _route[top]["flat"].y, 0.0)
	var anchor := _add_anchor("Summit", _summit_flat)
	anchor.set_meta("flow_kind", "CuratedSocket")
	var platform := StaticBody.new()
	platform.collision_layer = COLLISION_LAYER_ENV
	platform.collision_mask = 255
	var disc := CylinderMesh.new()
	disc.top_radius = 5.0
	disc.bottom_radius = 5.0
	disc.height = 0.4
	var pmesh := MeshInstance.new()
	pmesh.mesh = disc
	pmesh.material_override = _make_material(Color(0.26, 0.29, 0.33), 0.4, 0.6)
	platform.add_child(pmesh)
	var col := CollisionShape.new()
	var cyl := CylinderShape.new()
	cyl.radius = 5.0
	cyl.height = 0.4
	col.shape = cyl
	platform.add_child(col)
	anchor.add_child(platform)
	var room := MeshInstance.new()
	var rbox := CubeMesh.new()
	rbox.size = Vector3(3.6, 2.2, 3.6)
	room.mesh = rbox
	room.material_override = _make_material(Color(0.2, 0.23, 0.28), 0.5, 0.5, Color(0.25, 0.55, 0.8), 0.4)
	room.translation = Vector3(0.0, 1.3, -1.3)
	anchor.add_child(room)
	# Baliza (visible desde todo el anillo): cálida en ruta, cambia al completar.
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.16
	pillar.bottom_radius = 0.24
	pillar.height = 5.0
	_beacon = MeshInstance.new()
	_beacon.mesh = pillar
	_beacon.material_override = _make_material(COLOR_MAIN_LIGHT, 0.0, 1.0, COLOR_MAIN_LIGHT, 2.6)
	_beacon.translation = Vector3(0.0, 2.7, 1.5)
	_beacon.add_to_group("no_occlusion")
	anchor.add_child(_beacon)
	var blight := OmniLight.new()
	blight.omni_range = 10.0
	blight.light_color = COLOR_MAIN_LIGHT
	blight.light_energy = 1.8
	blight.shadow_enabled = false
	_beacon.add_child(blight)
	# El faro de la cima también es luz cálida estable de la ruta principal.
	var warm := OmniLight.new()
	warm.omni_range = 14.0
	warm.light_color = COLOR_MAIN_LIGHT
	warm.light_energy = 2.0
	warm.shadow_enabled = false
	anchor.add_child(warm)

# ── Desvíos curados (Side Sockets OPCIONALES) ────────────────────────────────

func _socket_index(fraction: float) -> int:
	var n: int = _route.size() - 1
	var base := int(round(fraction * float(n)))
	var jitter: int = (generation_seed / 7) % 3
	return int(clamp(float(base + jitter), 1.0, float(max(1, n - 1))))

func _add_socket(name: String, label: String, nodes: Array, reward: String) -> void:
	_sockets.append({"name": name, "label": label, "nodes": nodes, "reward": reward})

func _build_sockets() -> void:
	if _route.size() < 10:
		return
	_build_conveyor_socket(_socket_index(0.14))
	_build_laser_socket(_socket_index(0.34))
	_build_gloo_climb()
	_build_ledge_socket(_socket_index(0.60))
	_build_mag_rail_socket(_socket_index(0.80))

# Franjas + luz fría: el lenguaje visual de los atajos.
func _decorate_shortcut(body: Spatial) -> void:
	var stripe_mat := _make_material(COLOR_SHORTCUT_STRIPE, 0.2, 0.6, COLOR_SHORTCUT_STRIPE, 1.2)
	for i in range(3):
		var stripe := MeshInstance.new()
		var sbox := CubeMesh.new()
		sbox.size = Vector3(platform_length * 0.9, 0.04, 0.22)
		stripe.mesh = sbox
		stripe.material_override = stripe_mat
		stripe.translation = Vector3(0.0, platform_thickness * 0.5 + 0.02, (float(i) - 1.0) * walkway_width * 0.3)
		body.add_child(stripe)
	var cold := OmniLight.new()
	cold.light_color = COLOR_SHORTCUT_LIGHT
	cold.light_energy = 1.3
	cold.omni_range = 6.0
	cold.shadow_enabled = false
	cold.translation = Vector3(0.0, 1.3, 0.0)
	body.add_child(cold)

func _make_plate(name: String) -> StaticBody:
	var body := StaticBody.new()
	body.name = name
	body.collision_layer = COLLISION_LAYER_ENV
	body.collision_mask = 255
	var mesh := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(platform_length, platform_thickness, walkway_width * 0.8)
	mesh.mesh = box
	mesh.material_override = _make_material(Color(0.3, 0.33, 0.38), 0.4, 0.6)
	body.add_child(mesh)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(platform_length * 0.5, platform_thickness * 0.5, walkway_width * 0.4)
	col.shape = colbox
	body.add_child(col)
	_decorate_shortcut(body)
	return body

func _build_conveyor_socket(i: int) -> void:
	var flat: Vector3 = _route[i]["flat"] + Vector3(0.0, socket_radial_offset * 0.5, walkway_width)
	var anchor := _add_anchor("ConveyorSocket", flat)
	anchor.set_meta("flow_kind", "CuratedSocket")
	var body := _make_plate("ConveyorPlate")
	anchor.add_child(body)
	# Recompensa cinética: una caja-cinta que impulsa al jugador que la cruza.
	var crate := MeshInstance.new()
	var cbox := CubeMesh.new()
	cbox.size = Vector3(1.2, 1.2, 1.2)
	crate.mesh = cbox
	crate.material_override = _make_material(Color(0.5, 0.44, 0.3), 0.3, 0.8)
	crate.translation = Vector3(0.0, 0.6, 0.0)
	body.add_child(crate)
	_shortcuts.append(body)
	_add_socket("ConveyorSocket", "CuratedSocket", [body], "boost")

func _build_laser_socket(i: int) -> void:
	var flat: Vector3 = _route[i]["flat"] + Vector3(0.0, socket_radial_offset, -walkway_width)
	var anchor := _add_anchor("LaserSocket", flat)
	anchor.set_meta("flow_kind", "CuratedSocket")
	var body := _make_plate("LaserPlate")
	anchor.add_child(body)
	_laserGate = LaserGateScript.new()
	_laserGate.name = "ShortcutLaserGate"
	_laserGate.cut_time = 2.0
	var gate_anchor := _add_anchor("LaserGateAnchor", flat + Vector3(platform_length * 0.5, 0.0, 0.0))
	gate_anchor.set_meta("flow_kind", "CuratedSocket")
	gate_anchor.add_child(_laserGate)
	_shortcuts.append(_laserGate)
	_add_socket("LaserSocket", "CuratedSocket", [body, _laserGate], "shortcut")

func _build_gloo_climb() -> void:
	# GlooClimb: ascenso que supera el salto; SOLO opcional (INV-3).
	var n: int = _route.size() - 1
	var i: int = _socket_index(0.46)
	var j: int = int(clamp(float(i + 2), 0.0, float(n)))
	_glooSpan = GlooSpanScript.new()
	_glooSpan.name = "ShortcutGlooClimb"
	_glooSpan.required_blobs = 2
	_glooSpan.span_height = 0.2
	_glooSpan.bridge_width = walkway_width * 0.5
	_glooSpan.set_meta("flow_kind", "GlooClimb")
	_glooSpan.set_meta("flat_a", _route[i]["flat"] + Vector3(0.0, socket_radial_offset, 0.0))
	_glooSpan.set_meta("flat_b", _route[j]["flat"] + Vector3(0.0, socket_radial_offset, 0.0))
	add_child(_glooSpan)
	_shortcuts.append(_glooSpan)
	_add_socket("GlooClimb", "GlooClimb", [_glooSpan], "climb")

func _build_ledge_socket(i: int) -> void:
	# Cornisa con mantle: borde por encima de la ruta, alcanzable solo con cornisa
	# (≤ alcance de mantle). Recompensa cinética (atajo alto).
	var flat: Vector3 = _route[i]["flat"]
	var r: float = _flow.radius_at(flat.y)
	var lift: float = min(_flow.ledge_mantle_max_height(r) * 0.72, 4.6)
	var anchor := _add_anchor("LedgeSocket", flat + Vector3(0.0, lift, walkway_width * 1.2))
	anchor.set_meta("flow_kind", "CuratedSocket")
	var body := _make_plate("LedgePlate")
	anchor.add_child(body)
	# Labio de cornisa (borde agarrable visualmente).
	var lip := MeshInstance.new()
	var lbox := CubeMesh.new()
	lbox.size = Vector3(platform_length, 0.5, 0.25)
	lip.mesh = lbox
	lip.material_override = _make_material(COLOR_SHORTCUT_STRIPE, 0.3, 0.5, COLOR_SHORTCUT_STRIPE, 1.0)
	lip.translation = Vector3(0.0, -0.35, -walkway_width * 0.45)
	body.add_child(lip)
	_shortcuts.append(body)
	_add_socket("LedgeSocket", "CuratedSocket", [body], "ledge")

func _build_mag_rail_socket(i: int) -> void:
	var n: int = _route.size() - 1
	var i0: int = int(clamp(float(i), 2.0, float(max(2, n - 2))))
	var i1: int = int(clamp(float(i0 + 2), float(i0 + 1), float(n)))
	var mat := _make_material(Color(0.55, 0.5, 0.25), 0.3, 0.7, Color(0.9, 0.78, 0.3), 0.7)
	var nodes: Array = []
	for k in range(i0, i1):
		var flat: Vector3 = (_route[k]["flat"] + _route[k + 1]["flat"]) * 0.5 + Vector3(0.0, socket_radial_offset * 0.8, -walkway_width * 0.6)
		var body := StaticBody.new()
		body.name = "MagRail_%02d" % k
		body.collision_layer = COLLISION_LAYER_ENV
		body.collision_mask = 255
		var mesh := MeshInstance.new()
		var box := CubeMesh.new()
		box.size = Vector3(platform_length * 1.4, platform_thickness, walkway_width * 0.55)
		mesh.mesh = box
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape.new()
		var colbox := BoxShape.new()
		colbox.extents = Vector3(platform_length * 0.7, platform_thickness * 0.5, walkway_width * 0.275)
		col.shape = colbox
		body.add_child(col)
		body.set_meta("flow_kind", "MagRail")
		_decorate_shortcut(body)
		add_child(body)
		_register_projected(body, flat)
		nodes.append(body)
	if nodes.empty():
		return
	_mag_rail_nodes = nodes
	_mode_bridge = nodes[0] if nodes[0] is StaticBody else null
	_add_socket("MagRail", "MagRail", nodes, "grind")

func _build_rotor() -> void:
	# Peligro de la ruta principal, sincronizado con el ciclo (consumidor real).
	var n: int = _route.size() - 1
	var i: int = int(clamp(float(n) * 0.78, 1.0, float(max(1, n - 1))))
	var anchor := _add_anchor("RotorAnchor", _route[i]["flat"])
	anchor.set_meta("flow_kind", "RhythmSteps")
	var spin := Spatial.new()
	spin.name = "RotorSpin"
	anchor.add_child(spin)
	var arm := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(walkway_width * 0.9, 0.18, 1.4)
	arm.mesh = box
	arm.material_override = _make_material(Color(0.85, 0.2, 0.12), 0.3, 0.8, Color(0.9, 0.25, 0.15), 1.4)
	arm.translation = Vector3(0.0, 0.9, 0.0)
	spin.add_child(arm)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(walkway_width * 0.45, 0.09, 0.7)
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
			node.transform = _transform_at(entry["flat"])
	_project_gloo_span()
	_apply_mode_to_content()

# Pivote + rotación del punto flat: la plataforma hereda el "up" radial del
# cilindro (el plano de la pasarela queda perpendicular a la gravedad local).
func _transform_at(flat: Vector3) -> Transform:
	return _project_point(flat)

func _project_gloo_span() -> void:
	if _glooSpan == null or not is_instance_valid(_glooSpan):
		return
	if not _glooSpan.has_meta("flat_a"):
		return
	_glooSpan.span_from = project_flat_world(_glooSpan.get_meta("flat_a"))
	_glooSpan.span_to = project_flat_world(_glooSpan.get_meta("flat_b"))
	if _glooSpan.has_method("refresh_span"):
		_glooSpan.call("refresh_span")

func _apply_mode_to_content() -> void:
	var blend: float = 1.0
	if _rotator != null and _rotator.has_method("get_spiral_blend"):
		blend = float(_rotator.call("get_spiral_blend"))
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

func _apply_phase_lights(phase: int) -> void:
	if _slice_done:
		return
	var color: Color = COLOR_MAIN_LIGHT
	var energy := 1.6
	if phase == 1:
		color = Color(1.0, 0.72, 0.25)
		energy = 2.4
	elif phase == 2:
		color = Color(1.0, 0.4, 0.2)
		energy = 3.2
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

# ── Marcador de "slice completado" ───────────────────────────────────────────

# Lo llama el buffer de salida de la cima: la baliza vira a verde estable y se
# emite `slice_completed` (sin texto en el juego, como pide el FD).
func mark_slice_completed() -> void:
	if _slice_done:
		return
	_slice_done = true
	if _beacon != null and is_instance_valid(_beacon):
		var mat := _make_material(Color(0.4, 1.0, 0.55), 0.0, 1.0, Color(0.4, 1.0, 0.55), 3.0)
		_beacon.material_override = mat
		for child in _beacon.get_children():
			if child is Light:
				child.light_color = Color(0.4, 1.0, 0.55)
				child.light_energy = 2.6
	emit_signal("slice_completed")

func is_slice_completed() -> bool:
	return _slice_done

# ── API para la escena / tests ───────────────────────────────────────────────

func place_projected(node: Spatial, flat: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	_anchors.append({"node": node, "flat": flat})
	node.transform = _transform_at(flat)

func project_flat_world(flat: Vector3) -> Vector3:
	if _rotator == null or not _rotator.has_method("project_flat_point"):
		return flat
	var local: Vector3 = _rotator.call("project_flat_point", flat).origin
	return _rotator.global_transform.xform(local)

func is_mode_bridge_solid() -> bool:
	return _mode_bridge != null and is_instance_valid(_mode_bridge) and _mode_bridge.collision_layer != 0

func get_route_points() -> Array:
	return _route.duplicate()

func get_route_hops() -> Array:
	var out: Array = []
	for h in _hops:
		out.append({"kind": h["kind"], "gap": h["gap"], "dh": h["dh"]})
	return out

func get_summit_flat() -> Vector3:
	return _summit_flat

func get_main_route_gaps() -> Array:
	return _main_gaps.duplicate()

func get_main_route_gap_limit() -> float:
	return _flow.main_gap(_base_radius(), 0.0) if _flow != null else 0.0

func has_hop_kind(kind: String) -> bool:
	for h in _hops:
		if String(h["kind"]) == kind:
			return true
	return false

func get_route_kinds() -> Array:
	var seen := {}
	for h in _hops:
		seen[String(h["kind"])] = true
	return seen.keys()

func get_sockets() -> Array:
	return _sockets.duplicate()

func get_socket_labels() -> Array:
	var out: Array = []
	for s in _sockets:
		out.append(String(s["label"]))
	return out

func get_socket_rewards() -> Array:
	var out: Array = []
	for s in _sockets:
		out.append(String(s["reward"]))
	return out

# INV-3: ningún desvío curado ni herramienta está en la ruta principal.
func main_route_has_puzzle_blocker() -> bool:
	for entry in _plates:
		var kind := String(entry["kind"])
		if kind == "CuratedSocket" or kind == "GlooClimb" or kind == "MagRail":
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

func get_platform_count() -> int:
	return _plates.size()

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

# ── Validación de flow ───────────────────────────────────────────────────────

# Grafo de la ruta principal en el marco del cilindro (flat): el "horizontal" es
# el arco y el "up" el radial, que es como camina el jugador en el anillo. Cada
# nodo lleva su `g_eff(r)` local (INV-4: peor tick ya lo fija `BayTransitFlow`).
func build_route_graph() -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	for i in range(_route.size()):
		var flat: Vector3 = _route[i]["flat"]
		nodes.append({
			"id": "p%d" % i,
			"position": flat,
			"size": Vector3(platform_length, 0.0, walkway_width),
			"g": _flow.g_eff(_flow.radius_at(flat.y)) if _flow != null else 14.0,
			"tags": [_platform_kind_at(i)],
		})
	for i in range(_hops.size()):
		var h: Dictionary = _hops[i]
		var g_from: float = _flow.g_eff(_flow.radius_at(_route[i]["flat"].y)) if _flow != null else 14.0
		var g_to: float = _flow.g_eff(_flow.radius_at(_route[i + 1]["flat"].y)) if _flow != null else 14.0
		edges.append({
			"from": "p%d" % i,
			"to": "p%d" % (i + 1),
			"gap_horizontal": float(h["gap"]),
			"delta_h": float(h["dh"]),
			"tags": [String(h["kind"])],
			# INV-4: el peor caso es el g_eff MÁS ALTO de los extremos (menos alcance).
			"g": max(g_from, g_to),
		})
	return {
		"nodes": nodes,
		"edges": edges,
		"entry": "p0" if not _route.empty() else "",
		"exit": "p%d" % (_route.size() - 1) if not _route.empty() else "",
	}

func validate_main_route() -> Dictionary:
	if _flow == null:
		return {}
	var graph := build_route_graph()
	# El validador evalúa cada arista con el g del nodo destino (su `g_eff` local).
	return ValidatorScript.validate(graph, _flow.metrics_for_g(_flow.g_eff(_base_radius())))

# Peor exigencia de la ruta principal (fracción del alcance). ≤ 0.80 = válida.
func worst_main_demand_ratio() -> float:
	var result: Dictionary = validate_main_route()
	if result.empty():
		return 1.0
	var critical: Dictionary = result.get("critical_main_edge", {})
	if critical.empty():
		critical = result.get("most_demanding_edge", {})
	if critical.empty():
		return 0.0
	return float(critical.get("demand_ratio", 1.0))

# Reporte de calibración: para cada semilla, si la ruta principal valida y su
# peor exigencia. Lo usa el test de N semillas.
func calibration_report(seeds: Array) -> Array:
	var out: Array = []
	var saved: int = generation_seed
	for s in seeds:
		generation_seed = int(s)
		_compute_route()
		var result: Dictionary = validate_main_route()
		out.append({
			"seed": int(s),
			"valid": bool(result.get("valid_main_route", false)),
			"worst_demand": worst_main_demand_ratio(),
			"hops": _hops.size(),
			"cycle": _rhythm_run_length() + 1,
		})
	generation_seed = saved
	_compute_route()
	return out

# ── Estado serializable (replay + save) ──────────────────────────────────────

func get_snapshot() -> Dictionary:
	var states := []
	for shortcut in _shortcuts:
		if is_instance_valid(shortcut) and shortcut.has_method("get_state"):
			states.append({"name": shortcut.name, "state": shortcut.get_state()})
	return {"seed": generation_seed, "shortcuts": states, "flow": get_flow_describe(),
		"slice_completed": _slice_done}

func restore_snapshot(data: Dictionary) -> void:
	var states: Array = data.get("shortcuts", [])
	for entry in states:
		var n: String = entry.get("name", "")
		var st = entry.get("state", {})
		for shortcut in _shortcuts:
			if is_instance_valid(shortcut) and shortcut.name == n and shortcut.has_method("restore_state"):
				shortcut.restore_state(st)
	if bool(data.get("slice_completed", false)):
		mark_slice_completed()
