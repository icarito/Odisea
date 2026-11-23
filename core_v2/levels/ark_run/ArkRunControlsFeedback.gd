extends Reference

# FD-324 F7 — controles de gameplay de los slots Suit OS + feedback visual.
# Lee los holds reales de `player:thrusters` y `player:rope` (reubicables) o
# Shift/Q y E; empuja en dirección de cámara/WASD, apunta la cuerda con la
# cámara activa y dibuja halo de propulsor, marcador de anclaje y tether. También
# arma la línea de controles con las etiquetas reales de los slots.

const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeSwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const TronMaterials = preload("res://core_v2/levels/ark_run/ArkRunTronMaterials.gd")
const ROPE_COLOR := Color(0.35, 1.0, 0.75, 1.0)
const PLUME_LENGTH := 3.0

var loop = null
var wiring = null
var slice = null
var thrusting := false
var rope_state := "IDLE"
var rope_distance := 0.0
var _t := 0.0
var _halo = null
var _marker = null
var _tether = null

func setup(loop_node, wiring_node) -> void:
	loop = loop_node
	wiring = wiring_node
	slice = wiring.slice if wiring != null else null

func tick(dt: float, pilot, physics, pos: Vector3) -> void:
	_t += dt
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	var lt_pressed: bool = slice.thruster_input != null \
		and (slice.thruster_input.read_left_trigger() >= float(slice.thruster_input.deadzone) \
			or slice.thruster_input.read_keyboard_pressed())
	var rope_pressed: bool = slice.rope_input != null and slice.rope_input.is_trigger_pressed()
	var reeling: bool = attached and rope_pressed and lt_pressed
	thrusting = lt_pressed and not attached and physics != null \
		and not bool(physics._was_grounded) and slice.explosion.launched
	var thrust_dir: Vector3 = _thrust_direction(pilot)
	if thrusting:
		ThrusterScript.apply(physics, dt, thrust_dir, 1.0, true)
	_update_halo(pilot, thrust_dir)
	var aim: Vector3 = _rope_aim(pilot)
	var aim_anchors: Array = _comfort_anchors(pilot)
	if slice.rope_input != null:
		slice.rope_input.step(pilot, aim_anchors, aim, rope_pressed, dt, reeling)
	_update_rope_feedback(pilot, aim, reeling, aim_anchors)

func _thrust_direction(pilot) -> Vector3:
	var forward: Vector3 = _camera_forward(pilot)
	var move := Vector2.ZERO
	if pilot.input_provider != null and pilot.input_provider.last_input != null:
		move = pilot.input_provider.last_input.move_vec
	if move.length() < 0.05:
		return forward
	var right: Vector3 = forward.cross(Vector3.UP)
	right = right.normalized() if right.length_squared() > 0.000001 else Vector3.RIGHT
	var direction: Vector3 = right * move.x + forward * (-move.y)
	return direction.normalized() if direction.length_squared() > 0.000001 else forward

func _camera_forward(pilot) -> Vector3:
	var camera: Camera = null
	if loop != null and loop.get_viewport() != null:
		camera = loop.get_viewport().get_camera()
	if camera != null:
		var forward: Vector3 = -camera.global_transform.basis.z
		if forward.length_squared() > 0.000001:
			return forward.normalized()
	var fallback: Vector3 = -pilot.global_transform.basis.z
	return fallback.normalized() if fallback.length_squared() > 0.000001 else Vector3.FORWARD

func _rope_aim(pilot) -> Vector3:
	if loop != null and loop.has_method("rope_aim_dir"):
		return loop.rope_aim_dir(pilot)
	return _camera_forward(pilot)

# Pluma aditiva/emisiva orientada exactamente en -thrust_dir, saliendo de la
# espalda de Elias. El shader pulsa por TIME y el cono es mas ancho en la cola.
func _update_halo(pilot, thrust_dir: Vector3) -> void:
	if _halo == null or not is_instance_valid(_halo):
		_halo = MeshInstance.new()
		_halo.name = "ThrusterPlume"
		_halo.mesh = _plume()
		_halo.mesh.material = TronMaterials.plume_material()
		pilot.add_child(_halo)
	if _halo == null:
		return
	_halo.visible = thrusting
	if not thrusting:
		return
	_orient_plume(pilot, thrust_dir)

func _orient_plume(pilot, thrust_dir: Vector3) -> void:
	var exhaust: Vector3 = -thrust_dir.normalized() \
		if thrust_dir.length_squared() > 0.000001 else pilot.global_transform.basis.z
	exhaust = exhaust.normalized()
	var body_back: Vector3 = pilot.global_transform.basis.z.normalized()
	var muzzle: Vector3 = pilot.global_transform.origin + body_back * 0.55
	var center: Vector3 = muzzle + exhaust * (PLUME_LENGTH * 0.5)
	var ref: Vector3 = body_back
	if ref.cross(exhaust).length_squared() < 0.000001:
		ref = pilot.global_transform.basis.x
	if ref.cross(exhaust).length_squared() < 0.000001:
		ref = Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(exhaust).normalized()
	var z_axis: Vector3 = x_axis.cross(exhaust).normalized()
	_halo.global_transform = Transform(Basis(x_axis, exhaust, z_axis), center)
	var pulse: float = 1.0 + 0.12 * sin(_t * 20.0)
	_halo.scale = Vector3(pulse, 1.0, pulse)

# Prefiere anclajes que no obliguen a mirar muy arriba (<=30 m sobre el pilot).
func _comfort_anchors(pilot) -> Array:
	var origin: Vector3 = pilot.global_transform.origin
	var filtered: Array = []
	for anchor in wiring.anchors:
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		if point.y - origin.y <= 30.0:
			filtered.append(anchor)
	return filtered if not filtered.empty() else wiring.anchors

func _update_rope_feedback(pilot, aim: Vector3, reeling: bool = false, anchors: Array = []) -> void:
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	var anchor := Vector3.ZERO
	var hit := false
	if attached:
		var rope = slice.rope_input.get_rope()
		anchor = rope.get_anchor() if rope != null else pilot.global_transform.origin
		rope_state = "REELING" if reeling else "ATTACHED"
		rope_distance = pilot.global_transform.origin.distance_to(anchor)
	else:
		var candidates: Array = anchors if not anchors.empty() else wiring.anchors
		var best: Dictionary = RopeSwingScript.select_best_anchor(
			pilot.global_transform.origin, aim, candidates,
			_float_prop(slice.rope_input, "max_range", 55.0),
			_float_prop(slice.rope_input, "cone_deg", 38.0))
		hit = bool(best.get("hit", false))
		anchor = best.get("anchor_position", Vector3.ZERO)
		rope_state = "READY" if hit else "IDLE"
		rope_distance = float(best.get("distance", 0.0)) if hit else 0.0
	if _marker == null or not is_instance_valid(_marker):
		_marker = _make_mesh(slice.get_node("TraversalRoot"), "RopeAnchorMarker", _torus(), ROPE_COLOR)
	if _marker != null:
		_marker.visible = hit or attached
		_marker.global_transform.origin = anchor
		_marker.scale = Vector3.ONE * 1.6
		_marker.rotation = Vector3(_t * 0.7, _t * 0.9, 0.0)
	if _tether == null or not is_instance_valid(_tether):
		_tether = _make_tether(slice.get_node("TraversalRoot"))
	if _tether != null:
		_tether.visible = attached
		_tether.clear()
		if attached:
			_tether.begin(Mesh.PRIMITIVE_LINE_STRIP)
			_tether.add_vertex(pilot.global_transform.origin)
			_tether.add_vertex(anchor)
			_tether.end()

func _float_prop(obj, property_name: String, default_value: float) -> float:
	if obj == null or not (property_name in obj):
		return default_value
	return float(obj.get(property_name))

func _plume() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	# +Y = direccion de escape (lejos de Elias): cola ancha; tobera angosta.
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.07
	mesh.height = PLUME_LENGTH
	mesh.radial_segments = 16
	mesh.rings = 1
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh

func _torus() -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.1
	mesh.outer_radius = 1.7
	mesh.rings = 20
	mesh.ring_segments = 6
	return mesh

func _material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 1.8
	return material

func _make_mesh(parent, node_name: String, mesh: Mesh, color: Color):
	if parent == null:
		return null
	mesh.material = _material(color)
	var instance := MeshInstance.new()
	instance.name = node_name
	instance.mesh = mesh
	parent.add_child(instance)
	return instance

func _make_tether(parent):
	if parent == null:
		return null
	var geometry := ImmediateGeometry.new()
	geometry.name = "RopeTether"
	geometry.material_override = _material(ROPE_COLOR)
	parent.add_child(geometry)
	return geometry
