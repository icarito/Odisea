extends Spatial

# FD-323 Fase 3B — base aislada de SpinLab.
# Escena limpia sin WorldRotator: un DomeSpiralField estático, Pilot en SPIN_REAL,
# cámara 2.5D co-rotante y predictor de aterrizaje (solo presentación).
# Todos los spawns derivan de DomeSpiralFieldGeometry.plate_transform.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const FieldResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")
const CameraControllerScript = preload("res://core_v2/camera/SpinRealCameraController.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")

export(float) var spin_omega := 0.0
export(float) var plate_clearance := 0.6

var pilot = null
var spiral_field = null
var spin_camera = null
var spin_predictor = null
var _spiral_config: Dictionary = {}

func _ready() -> void:
	# Después del Pilot (prioridad 0): la presentación usa el estado post-física.
	process_priority = 100
	spiral_field = get_node_or_null("DomeSpiralField")
	pilot = get_node_or_null("Pilot")
	if spin_omega <= 0.0:
		spin_omega = SpinFrame.omega_for()
	_spiral_config = _resolve_spiral_config()
	_ensure_presentation_nodes()
	if pilot != null:
		pilot.set_spin_real_enabled(true)
		spawn_at_plate(0)

func _physics_process(delta: float) -> void:
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

func _plate_size() -> Vector3:
	if spiral_field != null and "plate_size" in spiral_field:
		return spiral_field.plate_size
	return FieldResource.DEFAULT_PLATE_SIZE

# Coloca al Pilot de pie sobre la placa, con su "up" alineado a la normal radial.
func spawn_at_plate(plate_index: int) -> void:
	if pilot == null:
		return
	var plate: Transform = SpiralGeometry.plate_transform(_spiral_config, plate_index)
	var up: Vector3 = plate.basis.y.normalized()
	var offset: float = _plate_size().y * 0.5 + max(plate_clearance, 0.0)
	var basis: Basis = Basis(
		plate.basis.x.normalized(), up, plate.basis.z.normalized()
	).orthonormalized()
	_place_pilot(Transform(basis, plate.origin + up * offset), up, Vector3.ZERO)

# Coloca al Pilot cerca del eje, en la z de la placa, con empuje radial v0 hacia afuera.
func spawn_at_hub_drop(plate_index: int, r0: float = 10.0, v0: float = 4.0) -> void:
	if pilot == null:
		return
	var plate: Transform = SpiralGeometry.plate_transform(_spiral_config, plate_index)
	var position := Vector3(r0, 0.0, plate.origin.z)
	var up: Vector3 = SpinFrame.up(position, Vector3.UP)
	var z_axis: Vector3 = plate.basis.z.normalized()
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	var basis: Basis = Basis(x_axis, up, z_axis).orthonormalized()
	_place_pilot(Transform(basis, position), up, Vector3(v0, 0.0, 0.0))

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
		physics.recharge_thrusters()

# Radio de referencia de la placa más cercana a la z actual (sin constantes mágicas).
func r_local_for_position(position: Vector3) -> float:
	var count: int = SpiralGeometry.plate_count_for(_spiral_config)
	var total_height: float = float(_spiral_config.get("total_height", 8000.0))
	var step: float = max(float(_spiral_config.get("plate_step", 40.0)), 0.001)
	var index: int = int(clamp(
		round((position.z + total_height * 0.5) / step), 0.0, float(count - 1)
	))
	return SpinFrame.r_perp(
		SpiralGeometry.plate_transform(_spiral_config, index).origin
	).length()

func _is_airborne() -> bool:
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if physics != null:
		return not bool(physics._was_grounded)
	return not pilot.is_on_floor()

# Actualiza cámara y predictor solo en SPIN_REAL; nunca muta la simulación.
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
