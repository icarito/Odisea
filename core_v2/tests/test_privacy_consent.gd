extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")

# FD-292. La pantalla se muestra al pulsar Nueva Partida la primera vez, no al abrir
# el menu, y los botones de aceptar/rechazar recien aparecen cuando la barra llega al
# final. Eso ultimo es lo que se cuida aca: si la eleccion pudiera hacerse antes, la
# pantalla dejaria de ser el rato de lectura que justifica su existencia.

func _make_screen():
	var packed = load("res://core_v2/ui/FirstRunConsent.tscn")
	assert_bool(packed != null).is_true()
	var screen = auto_free(packed.instance())
	add_child(screen)
	return screen

func test_settings_manager_expone_el_gate():
	assert_bool(SettingsManager != null).is_true()
	assert_bool(SettingsManager.has_method("needs_privacy_consent")).is_true()

func test_la_pregunta_aparece_sin_arrancar_el_nivel():
	var screen = _make_screen()
	assert_bool(screen._choice_box.visible).is_false()
	screen._on_ok_pressed()
	assert_bool(screen._telemetry_panel.visible).is_true()
	# El aviso es su propia pantalla: la pregunta esta disponible de inmediato y el
	# nivel todavia NO arranco. Si arrancara detras, su gameplay (la terminal
	# holografica) tomaria el mouse antes de que el jugador pudiera responder.
	assert_bool(screen._choice_box.visible).is_true()
	assert_bool(screen._progress.get_parent().visible).is_false()

func test_la_decision_arranca_la_carga():
	var screen = _make_screen()
	var requested := [false]
	screen.connect("loading_requested", self, "_on_loading_requested", [requested])
	screen._on_ok_pressed()
	screen._on_choice(true)
	# Recien con la decision tomada se pide la carga del nivel, y la pantalla pasa a
	# hacer de cartel de carga hasta que el nivel este listo.
	assert_bool(requested[0]).is_true()
	assert_bool(screen._choice_box.visible).is_false()
	assert_bool(screen._progress.get_parent().visible).is_true()

func _on_loading_requested(flag: Array) -> void:
	flag[0] = true

func test_aceptar_prende_la_telemetria():
	var screen = _make_screen()
	screen._on_choice(true)
	assert_bool(SettingsManager.telemetry_enabled).is_true()
	assert_bool(SettingsManager.error_reports_enabled).is_true()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()

func test_rechazar_la_deja_apagada():
	var screen = _make_screen()
	screen._on_choice(false)
	assert_bool(SettingsManager.telemetry_enabled).is_false()
	assert_bool(SettingsManager.error_reports_enabled).is_false()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()


func test_consent_keeps_the_shared_virtual_mouse_after_menu_hides():
	var menu := Control.new()
	get_tree().root.add_child(menu)
	var cursor: Control = VirtualMouse.attach_to(menu)
	var host := CanvasLayer.new()
	get_tree().root.add_child(host)
	var screen = load("res://core_v2/ui/FirstRunConsent.tscn").instance()
	host.add_child(screen)
	# attach_popup_deferred no puede add_child en el _ready del popup: cuelga un puente y se
	# engancha en el proximo idle. Sin esperar ese frame, la pantalla todavia no es requester.
	yield(get_tree(), "idle_frame")
	menu.hide()
	assert_bool(cursor.is_wanted()).is_true()
	host.free()
	menu.free()
