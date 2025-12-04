extends Node

class_name PlayerJump

# @export_range(0.0, 1.0, 0.01) var coyote_time := 0.15
export var coyote_time := 0.15
# @export_range(0.0, 1.0, 0.01) var jump_buffer_time := 0.12
export var jump_buffer_time := 0.12

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var should_jump_buffered := false

func reset_on_floor() -> void:
	coyote_timer = coyote_time
	should_jump_buffered = false
	jump_buffer_timer = 0.0

func on_air_tick(delta: float) -> void:
	coyote_timer = max(0.0, coyote_timer - delta)
	if should_jump_buffered:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)
		if jump_buffer_timer <= 0.0:
			should_jump_buffered = false

func buffer_jump() -> void:
	should_jump_buffered = true
	jump_buffer_timer = jump_buffer_time

func can_jump() -> bool:
	return coyote_timer > 0.0 or should_jump_buffered