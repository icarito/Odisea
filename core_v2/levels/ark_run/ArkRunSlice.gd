extends Spatial

# FD-324 F0 — base del vertical slice "Del hub al motor".
#
# Escena aislada en el marco canónico de SpinFrame (eje Z, proa +Z, popa -Z).
# No instancia WorldRotator ni CylinderRotator: toda la física vive aquí.
# F0 deja la geometría gruesa (casco + espiral + hub) y las zonas consultables;
# los contenedores ExplosionController / TraversalRoot / IndustryRoot /
# EngineIgnitionRoot / RaceHudRoot quedan vacíos para F1–F5.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const FieldResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")
const CameraControllerScript = preload("res://core_v2/camera/SpinRealCameraController.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

const SLICE_SEED := 32401
const SLICE_LENGTH := 2000.0
const R_HULL := 300.0
const R_HUB := 8.0
const BRIDGE_PLATE_INDICES := [47, 48, 49]
const ENGINE_Z_MAX := -940.0
const ENGINE_IGNITION_Z := 0.0
const ZONE_BRIDGE := "Puente"
const ZONE_ENGINE := "Motor"

var pilot = null
var spiral_field = null
var spin_camera = null
var spin_predictor = null
var hub = null
var hull = null
var spin_omega := 0.0

var _spiral_config: Dictionary = {}
var _bridge_z_min := 0.0
var _previous_gravity_mode := -1

func _ready() -> void:
	process_priority = 100
	spiral_field = get_node_or_null("DomeSpiralField")
	pilot = get_node_or_null("Pilot")
	hub = get_node_or_null("AxialHub/SpinAxialHub")
	hull = get_node_or_null("ArkRunHull")
	if spin_omega <= 0.0:
		spin_omega = SpinFrame.omega_for()
	_spiral_config = _resolve_spiral_config()
	_bridge_z_min = SpiralGeometry.plate_transform(
		_spiral_config, int(BRIDGE_PLATE_INDICES[0])
	).origin.z
	_ensure_presentation_nodes()
	_configure_zone_nodes()
	_apply_spin_gravity_mode()
	if pilot != null:
		pilot.set_spin_real_enabled(true)
		spawn_at_hub_start()

func _exit_tree() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null and _previous_gravity_mode >= 0:
		world.set_gravity_mode(_previous_gravity_mode)

func _physics_process(delta: float) -> void:
	update_spin_presentation(delta)

# --- Consultas estables (F1–F6) ---

func get_spiral_config() -> Dictionary:
	return _spiral_config.duplicate(true)

func get_slice_length() -> float:
	return SLICE_LENGTH

func get_hull_radius() -> float:
	return R_HULL

func get_hub_radius() -> float:
	return R_HUB

func get_bridge_plate_indices() -> Array:
	return BRIDGE_PLATE_INDICES.duplicate()

func get_bridge_z_min() -> float:
	return _bridge_z_min

func get_engine_z_max() -> float:
	return ENGINE_Z_MAX

func get_engine_ignition_z() -> float:
	return ENGINE_IGNITION_Z
func zone_at(position: Vector3) -> String:
	if position.z <= ENGINE_Z_MAX:
		return ZONE_ENGINE
	if position.z >= _bridge_z_min:
		return ZONE_BRIDGE
	return ""

func is_in_bridge(position: Vector3) -> bool:
	return zone_at(position) == ZONE_BRIDGE

func is_in_engine(position: Vector3) -> bool:
	return zone_at(position) == ZONE_ENGINE

# --- Setup ---

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

func _configure_zone_nodes() -> void:
	var bridge = get_node_or_null("BridgeZone")
	if bridge != null:
		bridge.set_meta("zone_name", ZONE_BRIDGE)
		bridge.set_meta("z_min", _bridge_z_min)
		bridge.set_meta("plate_indices", BRIDGE_PLATE_INDICES.duplicate())
	var engine = get_node_or_null("EngineZone")
	if engine != null:
		engine.set_meta("zone_name", ZONE_ENGINE)
		engine.set_meta("z_max", ENGINE_Z_MAX)

func _apply_spin_gravity_mode() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world == null:
		return
	_previous_gravity_mode = int(world.get_current_gravity_mode())
	world.set_gravity_mode(GravityModes.Mode.SPIN_REAL)

# --- Pilot ---

func spawn_at_hub_start(r0: float = 4.0, z0: float = ENGINE_IGNITION_Z) -> void:
	if pilot == null:
		return
	var position := Vector3(max(r0, 0.01), 0.0, z0)
	var up: Vector3 = SpinFrame.up(position, Vector3.UP)
	var z_axis := Vector3(0.0, 0.0, 1.0)
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	_place_pilot(
		Transform(Basis(x_axis, up, z_axis).orthonormalized(), position), up, Vector3.ZERO
	)

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
	var total_height: float = float(_spiral_config.get("total_height", SLICE_LENGTH))
	var step: float = max(float(_spiral_config.get("plate_step", 40.0)), 0.001)
	var index: int = int(clamp(
		round((position.z + total_height * 0.5) / step), 0.0, float(count - 1)
	))
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
		spin_predictor.update_preview(
			position, pilot.velocity, spin_omega, r_local, _is_airborne(), dt
		)
