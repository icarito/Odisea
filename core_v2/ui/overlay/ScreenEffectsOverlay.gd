extends Control

signal death_cover_reached
signal death_cover_cleared
signal death_confirmed

export(float) var death_close_sec := 0.15
export(float) var death_open_sec := 0.18
export(float) var death_curve := 0.14
export(float) var death_feather := 0.02
export(float) var cinematic_transition_sec := 0.22
export(float) var cinematic_bar_height_ratio := 0.11

var death_progress := 0.0 setget _set_death_progress
var cinematic_progress := 0.0 setget _set_cinematic_progress
var _waiting_for_death_confirm := false

onready var _effect_rect: ColorRect = $EffectRect
onready var _title: Label = $Title

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	_prepare_material()
	_update_shader_params()
	_update_title()
	_update_visibility()

func begin_death_cover(params: Dictionary = {}):
	var duration := float(params.get("duration", death_close_sec))
	_stop_active_tweens()
	_set_death_progress(0.0 if bool(params.get("restart", false)) else death_progress)
	var state = _animate_value("_set_death_progress", death_progress, 1.0, duration)
	if state is GDScriptFunctionState:
		yield(state, "completed")
	emit_signal("death_cover_reached")

func end_death_cover(params: Dictionary = {}):
	var duration := float(params.get("duration", death_open_sec))
	_cancel_death_confirm_wait()
	_stop_active_tweens()
	var state = _animate_value("_set_death_progress", death_progress, 0.0, duration)
	if state is GDScriptFunctionState:
		yield(state, "completed")
	emit_signal("death_cover_cleared")

func wait_for_death_confirm(_params: Dictionary = {}):
	if _waiting_for_death_confirm:
		yield(self, "death_confirmed")
		return
	_set_waiting_for_death_confirm(true)
	yield(self, "death_confirmed")

func set_cinematic_bars_enabled(enabled: bool, immediate: bool = false) -> void:
	_stop_active_tweens_for("CinematicTween")
	if immediate:
		_set_cinematic_progress(1.0 if enabled else 0.0)
		return
	var target := 1.0 if enabled else 0.0
	_animate_value("_set_cinematic_progress", cinematic_progress, target, cinematic_transition_sec, "CinematicTween")

func reset_effects(immediate: bool = true) -> void:
	_cancel_death_confirm_wait()
	_stop_active_tweens()
	if immediate:
		_set_death_progress(0.0)
		_set_cinematic_progress(0.0)
		return
	_animate_value("_set_death_progress", death_progress, 0.0, death_open_sec, "DeathTween")
	_animate_value("_set_cinematic_progress", cinematic_progress, 0.0, cinematic_transition_sec, "CinematicTween")

func _set_death_progress(value: float) -> void:
	death_progress = clamp(value, 0.0, 1.0)
	_update_shader_params()
	_update_title()
	_update_visibility()

func _set_cinematic_progress(value: float) -> void:
	cinematic_progress = clamp(value, 0.0, 1.0)
	_update_shader_params()
	_update_visibility()

func _prepare_material() -> void:
	if not is_instance_valid(_effect_rect):
		return
	if _effect_rect.material:
		_effect_rect.material = _effect_rect.material.duplicate()

func _update_shader_params() -> void:
	if not is_instance_valid(_effect_rect):
		return
	var material = _effect_rect.material
	if material and material is ShaderMaterial:
		material.set_shader_param("death_progress", death_progress)
		material.set_shader_param("death_curve", death_curve)
		material.set_shader_param("death_feather", death_feather)
		material.set_shader_param("cinematic_progress", cinematic_progress)
		material.set_shader_param("cinematic_bar_height", cinematic_bar_height_ratio)

func _update_title() -> void:
	if not is_instance_valid(_title):
		return
	var title_alpha = clamp((death_progress - 0.72) / 0.24, 0.0, 1.0)
	if _waiting_for_death_confirm:
		title_alpha = max(title_alpha, 1.0)
	_title.visible = title_alpha > 0.01
	var c = _title.modulate
	c.a = title_alpha
	_title.modulate = c

func _update_visibility() -> void:
	visible = death_progress > 0.001 or cinematic_progress > 0.001

func _input(event: InputEvent) -> void:
	if not _waiting_for_death_confirm:
		return
	if not _is_confirm_event(event):
		return
	_complete_death_confirm_wait()
	get_tree().set_input_as_handled()

func _animate_value(method_name: String, from_value: float, to_value: float, duration: float, tween_name: String = "DeathTween"):
	if duration <= 0.0:
		call(method_name, to_value)
		return null
	var tw := Tween.new()
	tw.name = tween_name
	add_child(tw)
	tw.interpolate_method(self, method_name, from_value, to_value, duration, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tw.start()
	yield(tw, "tween_all_completed")
	if is_instance_valid(tw):
		tw.queue_free()

func _stop_active_tweens() -> void:
	_stop_active_tweens_for("DeathTween")
	_stop_active_tweens_for("CinematicTween")

func _stop_active_tweens_for(tween_name: String) -> void:
	var tween = get_node_or_null(tween_name)
	if tween and tween is Tween:
		tween.stop_all()
		tween.queue_free()

func _set_waiting_for_death_confirm(waiting: bool) -> void:
	_waiting_for_death_confirm = waiting
	set_process_input(waiting)
	_update_title()

func _complete_death_confirm_wait() -> void:
	if not _waiting_for_death_confirm:
		return
	_set_waiting_for_death_confirm(false)
	emit_signal("death_confirmed")

func _cancel_death_confirm_wait() -> void:
	if not _waiting_for_death_confirm:
		return
	_set_waiting_for_death_confirm(false)
	emit_signal("death_confirmed")

func _is_confirm_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false
