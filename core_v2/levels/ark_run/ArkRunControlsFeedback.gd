extends Reference

# FD-324 F7 — controles de gameplay de los slots Suit OS + feedback visual.
# Lee los holds reales de `player:thrusters` y `player:rope` (reubicables) o
# Shift/Q y E; empuja en dirección de cámara/WASD, apunta la cuerda con la
# cámara activa y dibuja halo de propulsor, marcador de anclaje y tether. También
# arma la línea de controles con las etiquetas reales de los slots.

const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const RopeSwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const THRUSTERS_ID := "player:thrusters"
const ROPE_ID := "player:rope"
const HALO_COLOR := Color(0.3, 0.85, 1.0, 1.0)
const ROPE_COLOR := Color(0.35, 1.0, 0.75, 1.0)
const SLOT_DEFAULTS := {"thrusters": "L2", "rope": "R2", "nav": "R1", "light": "L1"}

var loop = null
var wiring = null
var slice = null
var thrusting := false
var rope_state := "IDLE"
var _t := 0.0
var _halo = null
var _marker = null
var _tether = null
var _controls_cache := ""

func setup(loop_node, wiring_node) -> void:
	loop = loop_node
	wiring = wiring_node
	slice = wiring.slice if wiring != null else null

func tick(dt: float, pilot, physics, pos: Vector3) -> void:
	_t += dt
	var host = slice.get_node_or_null("RaceHudRoot/ArkRunSuitOSHost") if slice != null else null
	var slot_thrust: bool = host != null and host.is_thrusters_slot_pressed()
	var key_thrust: bool = Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_Q)
	thrusting = (slot_thrust or key_thrust) and physics != null \
		and not bool(physics._was_grounded) and slice.explosion.launched
	if thrusting:
		ThrusterScript.apply(physics, dt, _thrust_direction(pilot), 1.0 if slot_thrust else 0.0, key_thrust)
	_update_halo(pilot)
	var aim: Vector3 = _camera_forward(pilot)
	var rope_pressed: bool = (host != null and host.is_rope_slot_pressed()) \
		or Input.is_key_pressed(KEY_E)
	if slice.rope_input != null:
		slice.rope_input.step(pilot, wiring.anchors, aim, rope_pressed, dt)
	_update_rope_feedback(pilot, aim)

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

func _update_halo(pilot) -> void:
	if _halo == null or not is_instance_valid(_halo):
		_halo = _make_mesh(pilot, "ThrusterHalo", _sphere(0.55), HALO_COLOR)
		_halo.translation = Vector3(0.0, 0.15, 0.45)
	if _halo == null:
		return
	_halo.visible = thrusting
	if thrusting:
		var pulse: float = 1.0 + 0.15 * sin(_t * 20.0)
		_halo.scale = Vector3.ONE * pulse

func _update_rope_feedback(pilot, aim: Vector3) -> void:
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	var anchor := Vector3.ZERO
	var hit := false
	if attached:
		var rope = slice.rope_input.get_rope()
		anchor = rope.get_anchor() if rope != null else pilot.global_transform.origin
		rope_state = "ATTACHED"
	else:
		var best: Dictionary = RopeSwingScript.select_best_anchor(
			pilot.global_transform.origin, aim, wiring.anchors,
			_float_prop(slice.rope_input, "max_range", 55.0),
			_float_prop(slice.rope_input, "cone_deg", 38.0))
		hit = bool(best.get("hit", false))
		anchor = best.get("anchor_position", Vector3.ZERO)
		rope_state = "READY" if hit else "IDLE"
	if _marker == null or not is_instance_valid(_marker):
		_marker = _make_mesh(slice.get_node("TraversalRoot"), "RopeAnchorMarker", _torus(), ROPE_COLOR)
	if _marker != null:
		_marker.visible = hit or attached
		_marker.global_transform.origin = anchor
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

# Etiquetas reales de los 4 slots (se actualizan si el jugador reubica apps).
func controls_text() -> String:
	var suit_os = Engine.get_main_loop().root.get_node_or_null("SuitOS")
	var thrust_label := _slot_label(suit_os, THRUSTERS_ID, SLOT_DEFAULTS["thrusters"])
	var rope_label := _slot_label(suit_os, ROPE_ID, SLOT_DEFAULTS["rope"])
	var nav_label := _slot_label(suit_os, "player:autonav", SLOT_DEFAULTS["nav"])
	var light_label := _slot_label(suit_os, "player:flashlight", SLOT_DEFAULTS["light"])
	var text := "WASD mover · Espacio saltar · %s/Shift propulsor · %s/E cuerda · %s/TAB autonav · %s linterna · Backspace reiniciar" \
		% [thrust_label, rope_label, nav_label, light_label]
	_controls_cache = text
	return text

func _slot_label(suit_os, screen_id: String, fallback: String) -> String:
	if suit_os == null or not suit_os.has_method("slot_label_for_screen"):
		return fallback
	var label: String = String(suit_os.slot_label_for_screen(screen_id))
	return label if label != "" else fallback

func get_controls_text() -> String:
	return _controls_cache if _controls_cache != "" else controls_text()
