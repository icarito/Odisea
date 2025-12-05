extends RigidBody
var max_forwardDrive = -999.0
var min_forwardDrive = 999.0

# control variables
export(float) var enginePower : float = 150.0
export(Curve) var torqueCurve : Curve

export(float) var maxSpeedKph : float = 100.0
export(float) var maxReverseSpeedKph : float = 20.0

export(float) var maxBrakingCoef : float = 0.05
export(float) var rollingResistance : float = 0.001

export(float) var steeringAngle : float = 30.0
export(float) var steerSpeed : float = 15.0
export(float) var maxSteerLimitRatio : float = 0.95
export(float) var steerReturnSpeed : float = 30.0

export(float) var autoStopSpeedMS : float = 1.0

onready var frontLeftElement: Spatial = $FL_ray
onready var frontRightElement: Spatial = $FR_ray

var driveElements : Array = []
var drivePerRay : float = enginePower

var currentDrivePower : float = 0.0
var currentSteerAngle : float = 0.0
var maxSteerAngle : float = steeringAngle

var currentSpeed : float = 0.0

func _handle_physics(delta) -> void:
	# --- Lógica de Entrada Unificada (Mando y Teclado) ---
	# Se calcula una sola vez, fuera del bucle de las ruedas.
	var forwardDrive : float = 0.0
	var steering : float = 0.0

	# Primero, intentamos obtener la entrada del joystick si está conectado.
	# Si no hay entrada del joystick (o su valor es muy bajo), usamos el teclado como alternativa.
	if Input.is_joy_known(0):
		forwardDrive = Input.get_joy_axis(0, JOY_AXIS_1)
		steering = Input.get_joy_axis(0, JOY_AXIS_0)
	else:
		forwardDrive = Input.get_axis("backward", "forward")
		steering = Input.get_axis("left", "right")

	# Debug: Solo imprimir si forwardDrive cambia significativamente
	if forwardDrive > max_forwardDrive:
		max_forwardDrive = forwardDrive
		print("[DEBUG] Nuevo forwardDrive máximo:", max_forwardDrive)
	if forwardDrive < min_forwardDrive:
		min_forwardDrive = forwardDrive
		print("[DEBUG] Nuevo forwardDrive mínimo:", min_forwardDrive)

	# --- Control de Dirección Analógico Directo ---
	# El ángulo de las ruedas refleja directamente la entrada del joystick.
	var desiredAngle : float = steering * steeringAngle

	# 4WD with front wheel steering
	for driveElement in driveElements:
		var finalForce : Vector3 = Vector3.ZERO
		var finalBrake : float = rollingResistance

		# limit steering based on speed and apply steering
		var maxSteerRatio : float = range_lerp(currentSpeed * 3.6, 0, maxSpeedKph, 0, maxSteerLimitRatio)
		maxSteerAngle = (1 - maxSteerRatio) * steeringAngle
		currentSteerAngle = clamp(desiredAngle, -maxSteerAngle, maxSteerAngle)
		frontRightElement.rotation_degrees.y = currentSteerAngle
		frontLeftElement.rotation_degrees.y = currentSteerAngle

		# --- Lógica de Freno y Aceleración ---
		# Si la entrada es en la dirección opuesta al movimiento, aplicamos el freno.
		if sign(currentSpeed) != sign(forwardDrive) and !is_zero_approx(currentSpeed) and forwardDrive != 0:
			finalBrake = maxBrakingCoef * abs(forwardDrive)
		# Si no hay entrada y la velocidad es baja, aplicamos un freno de estacionamiento.
		elif is_zero_approx(forwardDrive) and abs(currentSpeed) < autoStopSpeedMS:
			finalBrake = maxBrakingCoef

		# calculate motor forces
		var speedInterp : float
		if forwardDrive > 0:
			# Aceleración hacia adelante
			speedInterp = range_lerp(abs(currentSpeed), 0.0, maxSpeedKph / 3.6, 0.0, 1.0)
		elif forwardDrive < 0:
			# Marcha atrás
			speedInterp = range_lerp(abs(currentSpeed), 0.0, maxReverseSpeedKph / 3.6, 0.0, 1.0)
		else:
			speedInterp = 0.0

		# Debug: Imprimir solo si la fuerza final cambia significativamente
		var last_finalForce = null
		if driveElement.has_method("get"):
			last_finalForce = driveElement.get("_last_finalForce")
		# Si la curva de par no está definida, usamos la potencia del motor directamente.
		if torqueCurve:
			currentDrivePower = torqueCurve.interpolate_baked(speedInterp) * drivePerRay
		else:
			currentDrivePower = drivePerRay

		# Aplica la fuerza en la dirección correcta (sin el signo negativo)
		finalForce = driveElement.global_transform.basis.z * currentDrivePower * forwardDrive

		if driveElement.has_method("set"):
			driveElement.set("_last_finalForce", finalForce)

		# apply drive force and braking
		driveElement.apply_force(finalForce)
		driveElement.apply_brake(finalBrake)

func _ready() -> void:
	# setup array of drive elements and setup drive power
	for node in get_children():
		if node is DriveElement:
			driveElements.append(node)
	
	if !driveElements.empty():
		drivePerRay = enginePower / driveElements.size()
		print("Found %d drive elements connected to wheeled vehicle, setting to provide %.2f force each." % [driveElements.size(), drivePerRay])
	else:
		print("Warning: No DriveElement nodes found. Vehicle will not move.")
	
func _physics_process(delta) -> void:
	# calculate forward speed
	currentSpeed = global_transform.basis.xform_inv(linear_velocity).z
	_handle_physics(delta)
