extends GdUnitTestSuite

# test_widget_idle_fade.gd - B4: auto-hide de widgets en gameplay por inactividad.
# El host apaga muy lento (IDLE_FADE_OUT_SECONDS) contexto + slots tras la misma inactividad
# que MobileUI, y los devuelve con actividad (jugador en movimiento o cualquier input/HUD).

const SuitOSWidgetHostScript = preload("res://core_v2/ui/hud/SuitOSWidgetHost.gd")
const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")

class FakePlayer extends KinematicBody:
	var velocity := Vector3.ZERO

var _widget_host: Node = null
var _fake_player: Node = null
var _previous_player = null

func before() -> void:
	if has_node("/root/ANNAV2"):
		get_node("/root/ANNAV2").set_replay_mode(true)

func before_test() -> void:
	SuitOS._hud_mode_active = false
	_previous_player = SessionManager.player
	_fake_player = auto_free(FakePlayer.new())
	_fake_player.name = "IdleFadeFakePlayer"
	get_tree().root.add_child(_fake_player)
	SessionManager.player = _fake_player

	_widget_host = auto_free(SuitOSWidgetHostScript.new())
	_widget_host.name = "SuitOSWidgetHostIdleFade"
	get_tree().root.add_child(_widget_host)
	# El fade se maneja a mano en los tests: nada de _process en paralelo.
	_widget_host.set_process(false)
	_widget_host._cinematic_active = false

func after_test() -> void:
	SessionManager.player = _previous_player
	_fake_player = null
	_previous_player = null
	if is_instance_valid(_widget_host):
		_widget_host.free()
	_widget_host = null
	SuitOS._hud_mode_active = false
	SuitOS.clear_slots()
	yield(await_idle_frame(), "completed")

func test_idle_timeout_is_read_from_mobile_ui_manager_not_hardcoded() -> void:
	var was_timeout: float = MobileUIManager.touch_idle_timeout
	MobileUIManager.touch_idle_timeout = 7.25
	assert_float(_widget_host._idle_timeout_seconds()).is_equal(7.25)
	MobileUIManager.touch_idle_timeout = was_timeout


func test_widgets_fade_out_very_slowly_after_idle_and_return_on_activity() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:idle_fade"
	add_child(screen)
	SuitOS.pin_to_slot(0, "test:idle_fade")
	var root: Control = _widget_host.get_widget_root()
	# Sin movimiento del jugador: el acumulador decide.
	assert_float(root.modulate.a).is_equal(1.0)

	var timeout: float = _widget_host._idle_timeout_seconds()
	assert_float(timeout).is_greater(0.0)
	# Antes del timeout sigue opaco.
	_widget_host._idle_seconds = timeout - 0.1
	_widget_host._tick_idle_fade(0.05)
	assert_float(root.modulate.a).is_equal(1.0)

	# Pasado el timeout arranca el fade, y es MUY lento: media duracion deja la mitad.
	assert_bool(_widget_host.IDLE_FADE_OUT_SECONDS >= 3.0).is_true()
	assert_bool(_widget_host.IDLE_FADE_OUT_SECONDS > _widget_host.IDLE_FADE_IN_SECONDS).is_true()
	_widget_host._idle_seconds = timeout
	_widget_host._tick_idle_fade(_widget_host.IDLE_FADE_OUT_SECONDS * 0.5)
	assert_float(root.modulate.a).is_equal_approx(0.5, 0.02)
	_widget_host._tick_idle_fade(_widget_host.IDLE_FADE_OUT_SECONDS * 0.5)
	assert_float(root.modulate.a).is_equal(0.0)

	# Actividad: vuelve rapido, sin esperar el timeout.
	_widget_host._note_activity()
	_widget_host._tick_idle_fade(_widget_host.IDLE_FADE_IN_SECONDS)
	assert_float(root.modulate.a).is_equal(1.0)
	# El acumulador arranco de cero con la actividad: un tick corto no alcanza el timeout.
	assert_float(_widget_host._idle_seconds).is_less(timeout)

	SuitOS.clear_slots()
	SuitOS.unregister_screen(screen)


func test_player_movement_counts_as_activity() -> void:
	_fake_player.velocity = Vector3(1.0, 0.0, 0.0)
	assert_bool(_widget_host._activity_detected()).is_true()
	_fake_player.velocity = Vector3.ZERO
	assert_bool(_widget_host._activity_detected()).is_false()


func test_idle_fade_is_disabled_outside_gameplay() -> void:
	var root: Control = _widget_host.get_widget_root()
	root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_widget_host._idle_alpha = 0.0

	# Cinematica: no se apaga, y si estaba apagado se restaura.
	_widget_host._cinematic_active = true
	assert_bool(_widget_host._idle_fade_enabled()).is_false()
	_widget_host._tick_idle_fade(0.1)
	assert_float(root.modulate.a).is_equal(1.0)
	_widget_host._cinematic_active = false

	# Modo HUD: tampoco.
	SuitOS._hud_mode_active = true
	assert_bool(_widget_host._idle_fade_enabled()).is_false()
	_widget_host._tick_idle_fade(0.1)
	assert_float(root.modulate.a).is_equal(1.0)
	SuitOS._hud_mode_active = false

	# Y en gameplay vuelve a habilitarse.
	_fake_player.velocity = Vector3.ZERO
	assert_bool(_widget_host._idle_fade_enabled()).is_true()
