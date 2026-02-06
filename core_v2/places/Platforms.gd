extends MultiMeshInstance
tool
# SpiralGeneratorV2.gd
# Replica la lógica de OpenSCAD usando MultiMesh para alto rendimiento.

export(Mesh) var plate_mesh # Asigna aquí un CubeMesh de 80x80x2
export var total_height: float = 8000.0
export var plate_step: float = 40.0
export var turns: float = 8.0
export var r_min: float = 220.0
export var r_max: float = 260.0
export var interlock_angle: float = 45.0

# Controles de Animación
export var animate: bool = true # true = usar animación, false = usar manual_blend
export(float, 0.0, 1.0) var manual_blend: float = 0.0 # 0 = Axial, 1 = Centrífugo
export var cycle_duration: float = 10.0
var time_accumulator: float = 0.0

func _init():
	add_to_group("replay_sync")

func _ready():
	_setup_multimesh()

func _setup_multimesh():
	var plate_count = int(total_height / plate_step)
	
	# Inicializar MultiMesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = plate_count
	multimesh.mesh = plate_mesh

func _physics_process(delta: float):
	time_accumulator += delta
	_update_spiral_animation()

func _update_spiral_animation():
	if not multimesh: return
	
	# 1. Calcular el 'blend' ($t en OpenSCAD)
	var blend: float
	if animate:
		# Ping-pong: 0 → 1 → 0 over cycle_duration
		var half_cycle = cycle_duration / 2.0
		var t_in_cycle = fmod(time_accumulator, cycle_duration)
		var raw_t: float
		if t_in_cycle < half_cycle:
			raw_t = t_in_cycle / half_cycle # 0 → 1 durante primera mitad
		else:
			raw_t = 2.0 - (t_in_cycle / half_cycle) # 1 → 0 durante segunda mitad
		blend = _ease_smoothstep(raw_t)
	else:
		blend = manual_blend
	
	var plate_count = multimesh.instance_count
	var angle_per_plate = (360.0 * turns) / plate_count
	
	for i in range(plate_count):
		var u = float(i) / (plate_count - 1)
		var r = lerp(r_min, r_max, u)
		var z = i * plate_step
		var theta = deg2rad(i * angle_per_plate)
		
		# Lógica de rotación de OpenSCAD
		var y_ang = deg2rad(-90.0 * blend)
		var interlock = deg2rad(interlock_angle * blend)
		
		# Crear la Transformación (Matriz)
		var xform = Transform.IDENTITY
		
		# 1. Posicionar en la espiral (Translate Z -> Rotate Theta -> Translate R)
		xform.origin = Vector3(cos(theta) * r, z, sin(theta) * r)
		
		# 2. Orientación local (Inclinación centrífuga + Interlock)
		# OpenSCAD aplica rotaciones de adentro hacia afuera:
		#   rotate([0, 0, interlock]) -> rotate([0, y_ang, 0]) -> rotate([0, 0, theta])
		# En Godot construimos la base en ese mismo orden:
		var basis = Basis.IDENTITY
		basis = basis.rotated(Vector3(0, 0, 1), interlock) # 1. Interlock local (eje Z de SCAD)
		basis = basis.rotated(Vector3(0, 1, 0), y_ang) # 2. Inclinación centrífuga (eje Y de SCAD)
		basis = basis.rotated(Vector3(0, 1, 0), theta) # 3. Posición en espiral (eje Z de SCAD = Y de Godot)
		
		xform.basis = basis
		
		multimesh.set_instance_transform(i, xform)

func _ease_smoothstep(x: float) -> float:
	return x * x * (3 - 2 * x)

# --- Integración con Replay ---
func get_snapshot() -> Dictionary:
	return {"t": time_accumulator}

func restore_snapshot(data: Dictionary):
	time_accumulator = data.t
	_update_spiral_animation()