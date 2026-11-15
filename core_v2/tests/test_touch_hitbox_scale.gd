extends GdUnitTestSuite

# Bug Android: al cambiar la escala de render en vivo (Opciones / AdaptiveRenderScale ->
# SettingsManager.apply_render_resolution -> set_screen_stretch) baja el viewport interno y
# UIScaleCompensator encoge el Container de MobileUI con rect_scale. El hit-test de los botones
# tactiles (TouchActionButton._input) compara event.position contra get_global_rect(), que
# devuelve el origen escalado pero el TAMAÑO sin escalar: el rect de toque queda mas grande que
# el boton dibujado. A escalas chicas ese rect invadido tapa el centro de un boton vecino que se
# procesa antes en el grupo _input y se lo come con set_input_as_handled(), asi que el boton
# apuntado "no siempre" responde. El joystick (virtual_joystick.gd) y TouchCameraControls ya
# usan el rect escalado (rect_size * get_global_transform_with_canvas().get_scale()); el fix es
# el mismo calculo en TouchActionButton.
#
# El test inyecta un ScreenTouch real en coordenadas de ventana (el pipeline del motor lo
# re-escala a viewport) en el CENTRO del boton, a distintas escalas y resoluciones efectivas
# (800x600 y el perfil LOW 640x480, que con reference_height=600 deja la escala efectiva en
# 0.48), y verifica que el boton apuntado reciba el toque (su _touch_index). Antes del fix,
# a escala efectiva <= 0.5 el toque lo roba un vecino y el assert falla.

const MobileUIManagerScript = preload("res://core_v2/autoloads/MobileUIManager.gd")
const UIScaleCompensatorScript = preload("res://core_v2/ui/UIScaleCompensator.gd")
const TouchActionButtonScript = preload("res://core_v2/ui/TouchActionButton.gd")
const ElevatorFloorSelectorScript = preload("res://core_v2/props/elevator/ElevatorFloorSelector.gd")

const TOUCH_INDEX := 11

# Todos los botones tactiles del MobileUI (mismo script TouchActionButton).
const BUTTONS := [
	"Container/ActionButtons/InteractButton",
	"Container/ActionButtons/CrouchButton",
	"Container/ActionButtons/JumpButton",
	"Container/ActionButtons/HUDButton",
	"Container/ActionButtons/FireButton",
	"Container/ToolButtons/ToolPrevButton",
	"Container/ToolButtons/ToolNextButton",
	"Container/ZeroGButtons/RollLeftButton",
	"Container/ZeroGButtons/RollRightButton",
]

# (render_resolution, render_scale). Incluye el barrido que pide el reporte (1.0 -> 0.75 -> 0.6)
# y el perfil LOW real (640x480 con reference_height=600 lleva la escala efectiva a 0.6/0.48).
const SCENARIOS := [
	[Vector2(800, 600), 1.0],
	[Vector2(800, 600), 0.75],
	[Vector2(800, 600), 0.6],
	[Vector2(800, 600), 0.5],
	[Vector2(640, 480), 0.75],
	[Vector2(640, 480), 0.6],
]

var _mgr = null
var _mobile_ui = null
var _saved_is_mobile := false
var _saved_is_touch_active := false
var _saved_touch_seen := false
var _saved_is_zero_g := false
var _saved_render_resolution := Vector2(800, 600)
var _saved_render_scale := 1.0
var _saved_render_resolution_user_set := false
var _saved_render_scale_user_set := false
var _saved_full_resolution_holders := {}

func before_test() -> void:
	_reset_inputs()
	_mgr = get_node_or_null("/root/MobileUIManager")
	assert_object(_mgr).is_not_null()
	_saved_is_mobile = _mgr._is_mobile
	_saved_is_touch_active = _mgr._is_touch_active
	_saved_touch_seen = _mgr._touch_seen
	_saved_is_zero_g = _mgr._is_zero_g
	# SettingsManager es un autoload compartido entre suites: guardar TODO lo que toca el test
	# (valores, flags y holders) para devolverlo exactamente igual al terminar.
	var settings = get_node_or_null("/root/SettingsManager")
	if settings != null:
		_saved_render_resolution = settings.render_resolution
		_saved_render_scale = settings.render_scale
		_saved_render_resolution_user_set = settings._render_resolution_user_set
		_saved_render_scale_user_set = settings._render_scale_user_set
		_saved_full_resolution_holders = settings._full_resolution_holders.duplicate()
	_mgr._is_mobile = true
	_mgr._is_touch_active = true
	_mgr._touch_seen = true
	_mgr._is_zero_g = true
	_mgr._is_cinematic_active = false
	if not is_instance_valid(_mgr._mobile_ui):
		_mgr._spawn_mobile_ui()
	_mgr._refresh_mobile_ui_visibility()
	_mobile_ui = _mgr._mobile_ui
	assert_object(_mobile_ui).is_not_null()
	_mobile_ui.visible = true

func after_test() -> void:
	_reset_inputs()
	if is_instance_valid(_mobile_ui):
		_mobile_ui.free()
		_mobile_ui = null
	if is_instance_valid(_mgr):
		_mgr._mobile_ui = null
		_mgr._is_mobile = _saved_is_mobile
		_mgr._is_touch_active = _saved_is_touch_active
		_mgr._touch_seen = _saved_touch_seen
		_mgr._is_zero_g = _saved_is_zero_g
		_mgr._refresh_mobile_ui_visibility()
	_restore_display()

func test_un_toque_en_el_centro_activa_el_boton_en_cada_escala() -> void:
	var tree := get_tree()
	for scenario in SCENARIOS:
		var resolution: Vector2 = scenario[0]
		var scale: float = scenario[1]
		_apply_display(resolution, scale)
		yield(tree, "idle_frame")
		yield(tree, "idle_frame")
		var viewport_size: Vector2 = tree.root.size
		var window := Vector2(OS.window_size)
		for path in BUTTONS:
			var btn = _mobile_ui.get_node(path)
			btn.force_update_transform()
			var xf: Transform2D = btn.get_global_transform_with_canvas()
			var center: Vector2 = xf.xform(btn.rect_size * 0.5)
			var window_pos := Vector2(
				center.x * window.x / viewport_size.x,
				center.y * window.y / viewport_size.y)
			_press(window_pos)
			var got: int = btn._touch_index
			var holder := _touch_holder(btn)
			_release(window_pos)
			yield(tree, "idle_frame")
			assert_int(got).override_failure_message(
				"%s no recibio el toque en su centro (%s) con resolucion %s y escala %.2f (efectiva %.2f): lo tomo %s"
					% [btn.name, str(center), str(resolution), scale,
						_effective_scale(), holder]).is_equal(TOUCH_INDEX)

# El cleanup no debe dejar SettingsManager cambiado para las suites que corren despues en el mismo
# proceso (el autoload es compartido): valores, flags y holders vuelven tal cual estaban.
func test_el_cleanup_restaura_la_configuracion_de_settings() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	assert_object(settings).is_not_null()
	var before_resolution: Vector2 = settings.render_resolution
	var before_scale: float = settings.render_scale
	var before_res_user: bool = settings._render_resolution_user_set
	var before_scale_user: bool = settings._render_scale_user_set
	var before_holders: Dictionary = settings._full_resolution_holders.duplicate()

	_apply_display(Vector2(640, 480), 0.6)
	_restore_display()

	assert_vector2(settings.render_resolution).is_equal(before_resolution)
	assert_float(settings.render_scale).is_equal_approx(before_scale, 0.0001)
	assert_bool(settings._render_resolution_user_set).is_equal(before_res_user)
	assert_bool(settings._render_scale_user_set).is_equal(before_scale_user)
	assert_dict(settings._full_resolution_holders).is_equal(before_holders)

# Las rutas de gameplay que preguntan "¿el toque cae sobre un boton tactil?"
# (PlayerControllerV2._is_over_touch_control y ElevatorFloorSelector._is_over_touch_control)
# deben usar el hit-test ESCALADO: con get_global_rect().has_point() el TAMANO no se escala y a
# escala chica el rect de toque invade vecinos. Aca se comprueba que un punto dentro del rect
# sin escalar pero fuera del escalado NO cuenta como toque.
func test_hitbox_escalado_no_invade_fuera_del_boton() -> void:
	var holder := Control.new()
	holder.name = "ScaledHolder"
	add_child(holder)
	holder.rect_position = Vector2(4000, 4000) # lejos de los botones del MobileUI
	holder.rect_scale = Vector2(0.5, 0.5)
	var btn := TouchActionButtonScript.new()
	btn.action_name = "interact"
	holder.add_child(btn)
	btn.rect_size = Vector2(64, 64)
	yield(get_tree(), "idle_frame")
	btn.force_update_transform()
	var xf: Transform2D = btn.get_global_transform_with_canvas()
	# Fuera del rect ESCALADO (64*0.5=32 de ancho) pero dentro del rect SIN escalar de
	# get_global_rect() (64): el bug lo contaba como toque.
	var outside_scaled: Vector2 = xf.origin + Vector2(btn.rect_size.x - 1.0, btn.rect_size.y * 0.25)
	assert_bool(btn.get_global_rect().has_point(outside_scaled)).override_failure_message(
		"El punto de prueba deberia caer dentro de get_global_rect() (sin escalar).").is_true()
	assert_bool(UIScaleCompensatorScript.point_in_control(btn, outside_scaled)).override_failure_message(
		"El helper escalado no debe contar el punto fuera del boton dibujado.").is_false()

	var selector = ElevatorFloorSelectorScript.new()
	add_child(selector)
	yield(get_tree(), "idle_frame")
	assert_bool(selector._is_over_touch_control(outside_scaled)).override_failure_message(
		"El selector no debe tragarse un toque fuera del boton escalado.").is_false()
	selector.queue_free()
	holder.queue_free()
	yield(get_tree(), "idle_frame")

func _touch_holder(target) -> String:
	for path in BUTTONS:
		var other = _mobile_ui.get_node(path)
		if other != target and other._touch_index == TOUCH_INDEX:
			return other.name
	return "-"

func _press(window_pos: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = TOUCH_INDEX
	touch.pressed = true
	touch.position = window_pos
	Input.parse_input_event(touch)
	Input.flush_buffered_events()

func _release(window_pos: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = TOUCH_INDEX
	touch.pressed = false
	touch.position = window_pos
	Input.parse_input_event(touch)
	Input.flush_buffered_events()

func _reset_inputs() -> void:
	for action in ["interact", "crouch", "jump", "hud_mode", "tool_fire_primary",
			"tool_prev_mode", "tool_next_mode", "zero_g_roll_left", "zero_g_roll_right"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	var release := InputEventScreenTouch.new()
	release.index = TOUCH_INDEX
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()

func _apply_display(resolution: Vector2, scale: float) -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings == null:
		get_tree().set_screen_stretch(
			SceneTree.STRETCH_MODE_VIEWPORT,
			SceneTree.STRETCH_ASPECT_EXPAND,
			resolution * scale)
		return
	settings.render_resolution = resolution
	settings.render_scale = scale
	settings._render_resolution_user_set = true
	settings._render_scale_user_set = true
	settings._full_resolution_holders.clear()
	settings.apply_render_resolution()

func _restore_display() -> void:
	var settings = get_node_or_null("/root/SettingsManager")
	if settings == null:
		return
	settings.render_resolution = _saved_render_resolution
	settings.render_scale = _saved_render_scale
	settings._render_resolution_user_set = _saved_render_resolution_user_set
	settings._render_scale_user_set = _saved_render_scale_user_set
	settings._full_resolution_holders = _saved_full_resolution_holders
	settings.apply_render_resolution()

func _effective_scale() -> float:
	# La escala real de la UI incluye el encogido extra de reference_height (perfil LOW).
	if is_instance_valid(_mobile_ui):
		var container = _mobile_ui.get_node_or_null("Container")
		if container != null:
			return container.rect_scale.x
	var settings = get_node_or_null("/root/SettingsManager")
	if settings == null or not settings.has_method("effective_render_scale"):
		return 1.0
	return float(settings.effective_render_scale())
