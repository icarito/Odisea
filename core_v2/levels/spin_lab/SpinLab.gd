extends Spatial
# FD-323 Fase 3C — SpinLab completo. Escena aislada sin WorldRotator.
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const FieldResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")
const CameraControllerScript = preload("res://core_v2/camera/SpinRealCameraController.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")
const RopeScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const HUB_RADIUS := 8.0
const SPOKE_PLATES := [0, 2]
export(float) var spin_omega := 0.0
export(float) var plate_clearance := 0.6
var pilot = null
var spiral_field = null
var spin_camera = null
var spin_predictor = null
var spokes: Array = []
var hub = null
var rope = null
var _spiral_config: Dictionary = {}
var _rope_anchors: Array = []
var _previous_gravity_mode := -1
var _determinism_state: Dictionary = {}
func _ready() -> void:
	process_priority = 100
	spiral_field = get_node_or_null("DomeSpiralField")
	pilot = get_node_or_null("Pilot")
	hub = get_node_or_null("AxialHub/SpinAxialHub")
	rope = get_node_or_null("SpinRopeSwing")
	if spin_omega <= 0.0:
		spin_omega = SpinFrame.omega_for()
	_spiral_config = _resolve_spiral_config()
	_ensure_presentation_nodes()
	_apply_spin_gravity_mode()
	_configure_spokes()
	_rope_anchors = _collect_rope_anchors()
	if pilot != null:
		pilot.set_spin_real_enabled(true)
		spawn_at_plate(0)
func _exit_tree() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null and _previous_gravity_mode >= 0:
		world.set_gravity_mode(_previous_gravity_mode)
func _physics_process(delta: float) -> void:
	_apply_rope_constraint()
	update_spin_presentation(delta)
func get_spiral_config() -> Dictionary:
	return _spiral_config.duplicate(true)
func _resolve_spiral_config() -> Dictionary:
	if spiral_field != null and spiral_field.has_method("get_spiral_configs"):
		var configs: Array = spiral_field.get_spiral_configs()
		if not configs.empty():
			return configs[0]
	return FieldResource.default_spiral_config()
func _ensure_presentation_nodes() -> void:
	spin_camera = get_node_or_null("SpinRealCamera")
	if spin_camera == null:
		spin_camera = CameraControllerScript.new()
		spin_camera.name = "SpinRealCamera"
		add_child(spin_camera)
	spin_predictor = get_node_or_null("SpinLandingPredictor")
	if spin_predictor == null:
		spin_predictor = PredictorScript.new()
		spin_predictor.name = "SpinLandingPredictor"
		add_child(spin_predictor)
func _apply_spin_gravity_mode() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world == null:
		return
	_previous_gravity_mode = int(world.get_current_gravity_mode())
	world.set_gravity_mode(GravityModes.Mode.SPIN_REAL)
func _configure_spokes() -> void:
	spokes = []
	for plate_index in SPOKE_PLATES:
		var spoke = get_node_or_null("Spokes/SpinSpoke_%d" % plate_index)
		if spoke == null:
			continue
		spoke.configure_from_plate(
			SpiralGeometry.plate_transform(_spiral_config, plate_index), HUB_RADIUS
		)
		spokes.append(spoke)
func _collect_rope_anchors() -> Array:
	var anchors: Array = []
	var registry = get_node_or_null("/root/DomeRegistry")
	if spiral_field == null or registry == null:
		return anchors
	for dome_id in registry.get_all_dome_ids():
		var info: Dictionary = registry.get_dome(String(dome_id))
		var spiral_index: int = int(info.get("spiral_index", 0))
		if spiral_index < 0 or spiral_index >= spiral_field.get_spiral_count():
			continue
		anchors.append_array(spiral_field.get_plate_world_anchors(
			spiral_index, int(info.get("plate_index", 0)),
			registry.get_anchors(String(dome_id))
		))
	return anchors
func try_attach_rope(aim_dir: Vector3 = Vector3.ZERO) -> bool:
	if pilot == null or rope == null:
		return false
	var origin: Vector3 = pilot.global_transform.origin
	var aim: Vector3 = aim_dir
	if aim.length_squared() < 0.000001:
		aim = -pilot.global_transform.basis.z
	var best: Dictionary = RopeScript.select_best_anchor(
		origin, aim.normalized(), _rope_anchors, rope.max_len, 75.0
	)
	if not bool(best["hit"]):
		return false
	rope.attach(best["anchor_position"], origin)
	return true
func detach_rope() -> void:
	if rope != null:
		rope.detach()
func _apply_rope_constraint() -> void:
	if rope == null or not rope.is_attached() or pilot == null:
		return
	var result: Dictionary = RopeScript.constrain_swing(
		pilot.global_transform.origin, pilot.velocity, rope.get_anchor(), rope.get_rope_length()
	)
	if bool(result["taut"]):
		pilot.global_transform.origin = result["position"]
		pilot.velocity = result["velocity"]
	rope._update_visual(pilot.global_transform.origin)
func spawn_at_plate(plate_index: int) -> void:
	if pilot == null:
		return
	var plate: Transform = SpiralGeometry.plate_transform(_spiral_config, plate_index)
	var up: Vector3 = plate.basis.y.normalized()
	var offset: float = 1.0 + max(plate_clearance, 0.0)
	var basis: Basis = Basis(
		plate.basis.x.normalized(), up, plate.basis.z.normalized()
	).orthonormalized()
	_place_pilot(Transform(basis, plate.origin + up * offset), up, Vector3.ZERO)
func spawn_at_hub_drop(plate_index: int, r0: float = 10.0, v0: float = 4.0) -> void:
	if pilot == null:
		return
	var plate: Transform = SpiralGeometry.plate_transform(_spiral_config, plate_index)
	var theta: float = atan2(plate.origin.y, plate.origin.x)
	var radial_dir := Vector3(cos(theta), sin(theta), 0.0)
	var position := radial_dir * r0 + Vector3(0.0, 0.0, plate.origin.z)
	var up: Vector3 = SpinFrame.up(position, Vector3.UP)
	var z_axis: Vector3 = plate.basis.z.normalized()
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	var launch: Dictionary = {"velocity": radial_dir * v0}
	if hub != null:
		launch = hub.compute_hatch_launch(position, radial_dir, v0)
	_place_pilot(Transform(Basis(x_axis, up, z_axis).orthonormalized(), position), up, launch["velocity"])
func _place_pilot(body_transform: Transform, up: Vector3, body_velocity: Vector3) -> void:
	pilot.global_transform = body_transform
	pilot.velocity = body_velocity
	pilot.set_sim_up(up)
	if "movement_logic" in pilot and is_instance_valid(pilot.movement_logic):
		pilot.movement_logic.horizontal_velocity = Vector3.ZERO
		pilot.movement_logic.wish_direction = Vector3.ZERO
	if "jump_logic" in pilot and is_instance_valid(pilot.jump_logic):
		pilot.jump_logic.set_internal_velocity(0.0)
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if physics != null:
		physics._was_grounded = false
		physics._slide_active = false
		physics._tumble_timer = 0.0
		physics.spin_thruster_dv_remaining = physics.spin_thruster_dv_max
func r_local_for_position(position: Vector3) -> float:
	var count: int = SpiralGeometry.plate_count_for(_spiral_config)
	var total_height: float = float(_spiral_config.get("total_height", 8000.0))
	var step: float = max(float(_spiral_config.get("plate_step", 40.0)), 0.001)
	var index: int = int(clamp(round((position.z + total_height * 0.5) / step), 0.0, float(count - 1)))
	return SpinFrame.r_perp(SpiralGeometry.plate_transform(_spiral_config, index).origin).length()
func _is_airborne() -> bool:
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	return not bool(physics._was_grounded) if physics != null else not pilot.is_on_floor()
func update_spin_presentation(dt: float) -> void:
	if pilot == null or not is_instance_valid(pilot) or not pilot.is_spin_real_active():
		if spin_predictor != null and is_instance_valid(spin_predictor):
			spin_predictor.visible = false
		return
	var position: Vector3 = pilot.global_transform.origin
	var r_local: float = r_local_for_position(position)
	if spin_camera != null and is_instance_valid(spin_camera):
		spin_camera.apply_to_pilot(pilot, r_local, dt)
	if spin_predictor != null and is_instance_valid(spin_predictor):
		spin_predictor.update_preview(position, pilot.velocity, spin_omega, r_local, _is_airborne(), dt)
func run_determinism_probe() -> void:
	if pilot == null:
		return
	spawn_at_hub_drop(0, 10.0, 4.0)
	for _i in range(120):
		pilot.step(1.0 / 60.0, InputDataV2.new())
	_determinism_state = {
		"position": pilot.global_transform.origin, "velocity": pilot.velocity,
		"up": pilot.get_sim_up(), "gravity_mode": _gravity_mode_at(pilot.global_transform.origin)
	}
func _gravity_mode_at(position: Vector3) -> int:
	var world = get_node_or_null("/root/GravityWorld")
	return int(world.get_gravity_mode_at(position)) if world != null else -1
