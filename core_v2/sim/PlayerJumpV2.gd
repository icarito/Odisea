extends Node

# PlayerJumpV2.gd - Componente para lógica de salto con coyote time y jump buffer

const COYOTE_TIME := 0.15  # ~120-150 ms
const JUMP_BUFFER_TIME := 0.1  # ~100-120 ms

var coyote_timer := 0.0
var jump_buffer_timer := 0.0

func reset_on_floor() -> void:
	coyote_timer = COYOTE_TIME

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