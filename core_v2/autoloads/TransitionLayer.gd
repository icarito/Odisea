extends CanvasLayer

signal transition_covered_screen
signal transition_finished

export(float, 0.0, 3.0) var default_fade_out_duration := 0.35
export(float, 0.0, 3.0) var default_fade_in_duration := 0.35

var _overlay: ColorRect = null
var _loading_root: Control = null
var _loading_label: Label = null
var _loading_subtitle: Label = null
var _loading_progress: ProgressBar = null
var _loading_footer: Label = null
var _fade_tween: Tween = null
var _is_animating := false

func _ready() -> void:
	layer = 1000
	pause_mode = Node.PAUSE_MODE_PROCESS

	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.anchor_left = 0.0
	_overlay.anchor_top = 0.0
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_loading_root = Control.new()
	_loading_root.name = "LoadingRoot"
	_loading_root.anchor_left = 0.0
	_loading_root.anchor_top = 0.0
	_loading_root.anchor_right = 1.0
	_loading_root.anchor_bottom = 1.0
	_loading_root.visible = false
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_loading_root)

	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.align = Label.ALIGN_CENTER
	_loading_label.valign = Label.VALIGN_CENTER
	_loading_label.anchor_left = 0.25
	_loading_label.anchor_top = 0.43
	_loading_label.anchor_right = 0.75
	_loading_label.anchor_bottom = 0.50
	_loading_label.text = "Cargando..."
	_loading_root.add_child(_loading_label)

	_loading_subtitle = Label.new()
	_loading_subtitle.name = "LoadingSubtitle"
	_loading_subtitle.align = Label.ALIGN_CENTER
	_loading_subtitle.valign = Label.VALIGN_TOP
	_loading_subtitle.anchor_left = 0.25
	_loading_subtitle.anchor_top = 0.48
	_loading_subtitle.anchor_right = 0.75
	_loading_subtitle.anchor_bottom = 0.52
	_loading_subtitle.add_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	_loading_subtitle.text = ""
	_loading_root.add_child(_loading_subtitle)

	_loading_progress = ProgressBar.new()
	_loading_progress.name = "LoadingProgress"
	_loading_progress.anchor_left = 0.25
	_loading_progress.anchor_top = 0.51
	_loading_progress.anchor_right = 0.75
	_loading_progress.anchor_bottom = 0.56
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 100.0
	_loading_progress.value = 0.0
	_loading_progress.percent_visible = true
	_loading_root.add_child(_loading_progress)

	_loading_footer = Label.new()
	_loading_footer.name = "LoadingFooter"
	_loading_footer.align = Label.ALIGN_CENTER
	_loading_footer.valign = Label.VALIGN_BOTTOM
	_loading_footer.anchor_left = 0.0
	_loading_footer.anchor_top = 0.90
	_loading_footer.anchor_right = 1.0
	_loading_footer.anchor_bottom = 0.97
	_loading_footer.add_color_override("font_color", Color("#445566"))
	_loading_footer.text = "icarito\nodisea.educa.juegos"
	_loading_root.add_child(_loading_footer)

	_fade_tween = Tween.new()
	_fade_tween.name = "FadeTween"
	add_child(_fade_tween)

func play(animation_name: String, params: Dictionary = {}):
	match String(animation_name).to_lower():
		"fade_out":
			var out_duration := float(params.get("duration", default_fade_out_duration))
			if _loading_root:
				_loading_root.visible = bool(params.get("show_loading", _loading_root.visible))
			var out_state = _fade_to_alpha(1.0, out_duration)
			if out_state is GDScriptFunctionState:
				yield(out_state, "completed")
			emit_signal("transition_covered_screen")
			return
		"fade_in":
			var in_duration := float(params.get("duration", default_fade_in_duration))
			var in_state = _fade_to_alpha(0.0, in_duration)
			if in_state is GDScriptFunctionState:
				yield(in_state, "completed")
			hide_loading()
			emit_signal("transition_finished")
			return
		"loading_screen_show":
			show_loading(
				String(params.get("message", "Cargando...")),
				bool(params.get("show_progress", true)),
				String(params.get("subtitle", ""))
			)
			return
		_:
			printerr("[TransitionLayer] Unknown animation: ", animation_name)

func show_loading(message: String = "Cargando...", show_progress: bool = true, subtitle: String = "") -> void:
	if _loading_label:
		_loading_label.text = message
	if _loading_subtitle:
		_loading_subtitle.text = subtitle
		_loading_subtitle.visible = subtitle != ""
	if _loading_progress:
		_loading_progress.visible = show_progress
		_loading_progress.value = 0.0
	if _overlay:
		_overlay.visible = true
	if _loading_root:
		_loading_root.visible = true

func hide_loading() -> void:
	if _loading_root:
		_loading_root.visible = false

func set_loading_progress(progress_01: float) -> void:
	if not _loading_progress:
		return
	var clamped = clamp(progress_01, 0.0, 1.0)
	_loading_progress.value = clamped * 100.0

func is_animating() -> bool:
	return _is_animating

func _fade_to_alpha(target_alpha: float, duration: float):
	if not _overlay:
		return

	var target := clamp(target_alpha, 0.0, 1.0)
	if duration <= 0.0:
		var c = _overlay.color
		c.a = target
		_overlay.color = c
		_overlay.visible = target > 0.0
		_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if target > 0.0 else Control.MOUSE_FILTER_IGNORE
		return

	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	if _fade_tween:
		_fade_tween.stop_all()
	_is_animating = true
	_fade_tween.interpolate_property(
		_overlay,
		"color:a",
		_overlay.color.a,
		target,
		duration,
		Tween.TRANS_LINEAR,
		Tween.EASE_IN_OUT
	)
	_fade_tween.start()
	yield(_fade_tween, "tween_all_completed")
	_is_animating = false

	if target <= 0.0:
		_overlay.visible = false
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
