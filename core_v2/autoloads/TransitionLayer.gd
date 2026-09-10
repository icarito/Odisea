extends CanvasLayer

signal transition_covered_screen
signal transition_finished

export(float, 0.0, 3.0) var default_fade_out_duration := 0.35
export(float, 0.0, 3.0) var default_fade_in_duration := 0.35

# Uncovering as soon as the scene is in the tree shows it before the driver has
# built the programs its materials need: the geometry arrives untextured and pops
# in over the next seconds. Hold the cover until the renderer stops compiling.
# Bounded on purpose -- a driver that refuses a variant never reaches zero (Adreno
# rejects the scene ubershader outright), and an unbounded wait hangs the
# transition. The timeout is the knob: raise it on a slow device, set it to 0 to
# uncover immediately.
export(float, 0.0, 15.0) var shader_settle_timeout := 4.0
export(int, 1, 30) var shader_settle_quiet_frames := 4

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
			# The loading text and bar are opaque, but the overlay behind them is still
			# transparent while the fade runs, so revealing them now pastes them over
			# the live game. Hold them until the screen is actually covered.
			var want_loading := false
			if _loading_root:
				want_loading = bool(params.get("show_loading", _loading_root.visible))
				_loading_root.visible = false
			var out_state = _fade_to_alpha(1.0, out_duration)
			if out_state is GDScriptFunctionState:
				yield(out_state, "completed")
			if _loading_root:
				_loading_root.visible = want_loading
			emit_signal("transition_covered_screen")
			return
		"fade_in":
			var in_duration := float(params.get("duration", default_fade_in_duration))
			if bool(params.get("wait_for_shaders", true)):
				var settle_state = _await_shader_settle()
				if settle_state is GDScriptFunctionState:
					yield(settle_state, "completed")
			# El texto y la barra son opacos, asi que sostenerlos mientras el negro se
			# desvanece los deja pegados sobre el juego que va apareciendo detras. Se
			# ocultan ahora, con la pantalla todavia cubierta, no al final del fundido:
			# la regla es que el cartel de carga solo se ve sobre negro.
			hide_loading()
			# El fundido de entrada descubre la escena aunque la cola de shaders siga
			# drenando -- el tope de _await_shader_settle es un tope, no una garantia.
			# La viñeta toma la posta ahi: cierra los bordes mientras entra lo que
			# falta y se abre sola cuando el renderizador se aquieta.
			var settle_pending := bool(params.get("wait_for_shaders", true)) and not _renderer_is_quiet()
			if settle_pending:
				_show_settle_vignette()
			var in_state = _fade_to_alpha(0.0, in_duration)
			if in_state is GDScriptFunctionState:
				yield(in_state, "completed")
			if settle_pending:
				_hold_settle_vignette()
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

func _renderer_is_quiet() -> bool:
	return VisualServer.get_render_info(VisualServer.INFO_SHADER_COMPILES_IN_FRAME) == 0

# Reutiliza las barras cinematograficas de ScreenEffectsManager en vez de dibujar una
# viñeta propia: el juego ya tiene ese lenguaje visual y el jugador ya lo asocia con
# "esto es una escena, no un error". Se cierran al descubrir y se abren cuando el
# renderizador deja de compilar.
func _show_settle_vignette() -> void:
	var fx = get_node_or_null("/root/ScreenEffectsManager")
	if fx and fx.has_method("show_script_cinematic_bars"):
		fx.show_script_cinematic_bars()

func _hide_settle_vignette() -> void:
	var fx = get_node_or_null("/root/ScreenEffectsManager")
	if fx and fx.has_method("hide_script_cinematic_bars"):
		fx.hide_script_cinematic_bars()

# Sostiene las barras hasta que el renderizador deja de compilar. Con su propio tope:
# si un driver nunca llega a cero --paso en Adreno con el ubershader-- la escena no
# puede quedarse enmarcada para siempre.
func _hold_settle_vignette() -> void:
	var tree := get_tree()
	if tree == null:
		_hide_settle_vignette()
		return
	var timeout := 20.0
	if ProjectSettings.has_setting("odisea/transition/vignette_hold_timeout"):
		timeout = float(ProjectSettings.get_setting("odisea/transition/vignette_hold_timeout"))
	var deadline := OS.get_ticks_msec() + int(max(0.0, timeout) * 1000.0)
	var quiet := 0
	while quiet < shader_settle_quiet_frames:
		if OS.get_ticks_msec() >= deadline:
			break
		yield(tree, "idle_frame")
		if not is_instance_valid(self):
			return
		if _renderer_is_quiet():
			quiet += 1
		else:
			quiet = 0
	_hide_settle_vignette()

# Returns a GDScriptFunctionState only when it actually waits; callers check.
func _await_shader_settle():
	var tree := get_tree()
	if tree == null or shader_settle_timeout <= 0.0:
		return
	# El techo sale de project.godot para poder moverlo por plataforma sin recompilar
	# (odisea/transition/shader_settle_timeout, con override .Android). Android
	# materializa una variante encolada por frame, asi que su cola tarda mucho mas en
	# aquietarse que la de escritorio: medido en el Redmi, 45 s no alcanzaban y el
	# fusible terminaba mandando el tiempo total -- el jugador esperaba mirando un
	# aviso ya leido. Es un tope, no una meta: al vencer se descubre igual, y con el
	# batching lo que falta entra de a poco en vez de en un tiron.
	var timeout := shader_settle_timeout
	if ProjectSettings.has_setting("odisea/transition/shader_settle_timeout"):
		timeout = float(ProjectSettings.get_setting("odisea/transition/shader_settle_timeout"))
	var deadline := OS.get_ticks_msec() + int(max(0.0, timeout) * 1000.0)
	var quiet := 0
	while quiet < shader_settle_quiet_frames:
		if OS.get_ticks_msec() >= deadline:
			return
		yield(tree, "idle_frame")
		if VisualServer.get_render_info(VisualServer.INFO_SHADER_COMPILES_IN_FRAME) > 0:
			quiet = 0
		else:
			quiet += 1

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
