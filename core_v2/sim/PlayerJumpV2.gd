extends Node

# PlayerJumpV2.gd - Componente para lógica de salto con coyote time y jump buffer

export(float) var jump_force := 12.0
export(float) var gravity := -24.0 # Más pesado para mejor feeling con salto variable
export(float) var min_jump_intensity := 0.4

const COYOTE_TIME := 0.15 # ~120-150 ms
const JUMP_BUFFER_TIME := 0.1 # ~100-120 ms

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var internal_velocity := 0.0
var _is_jumping := false
var _jump_time_tracker := 0.0

const MIN_JUMP_TIME := 0.08 # Evita cortes accidentales en los primeros ~5 frames

func reset_on_floor() -> void:
	coyote_timer = COYOTE_TIME
	# _is_jumping se resetea al empezar a caer o al aterrizar
	if coyote_timer > 0.0 and _jump_time_tracker > MIN_JUMP_TIME:
		_is_jumping = false
		_jump_time_tracker = 0.0

func on_air_tick(dt: float) -> void:
	coyote_timer -= dt
	if coyote_timer < 0.0:
		coyote_timer = 0.0
	jump_buffer_timer -= dt
	if jump_buffer_timer < 0.0:
		jump_buffer_timer = 0.0

func buffer_jump() -> void:
	jump_buffer_timer = JUMP_BUFFER_TIME

func can_jump(on_floor: bool) -> bool:
	return (on_floor and jump_buffer_timer > 0.0) or (coyote_timer > 0.0 and jump_buffer_timer > 0.0)

func consume_jump() -> void:
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	_is_jumping = true

func set_internal_velocity(v: float) -> void:
	internal_velocity = v

func step(dt: float, input_jump: bool, current_vy: float, on_floor: bool) -> float:
	# If current_vy is significantly different from our internal expectation
	# (e.g. forced by external scripted event or snap), we sync to it.
	# But normally we stick to our simulated gravity.
	# NOTE: We keep current_vy for compatibility in this signature, but 
	# prefer internal_velocity.
	# Actualizar tracker si estamos saltando
	if _is_jumping:
		_jump_time_tracker += dt
	
	# Aplicar Gravedad
	internal_velocity += gravity * dt
	
	# Lógica de Salto (Inicio)
	if can_jump(on_floor):
		internal_velocity = jump_force
		consume_jump()
		_jump_time_tracker = 0.0
	
	# Si ya no estamos en el suelo y vamos cayendo, el salto terminó
	if not on_floor and internal_velocity <= 0.0:
		_is_jumping = false
	
	# Lógica de Salto Variable (Recorte a Intensidad Mínima)
	if not input_jump and _is_jumping and internal_velocity > 0.0 and _jump_time_tracker > MIN_JUMP_TIME:
		var min_v = jump_force * min_jump_intensity
		if internal_velocity > min_v:
			internal_velocity = min_v
		_is_jumping = false
		
	return internal_velocity

func get_jump_force() -> float:
	return jump_force

func get_gravity() -> float:
	return gravity