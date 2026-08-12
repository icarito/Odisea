extends ColorRect

onready var master_slider = find_node("MasterSlider")
onready var music_slider = find_node("MusicSlider")
onready var sfx_slider = find_node("SFXSlider")
onready var invert_y_toggle = find_node("InvertYToggle")
onready var vibration_toggle = find_node("VibrationToggle")
onready var fullscreen_option = find_node("FullscreenOption")
onready var resolution_option = find_node("ResolutionOption")
onready var render_scale_option = find_node("RenderScaleOption")
onready var vsync_option = find_node("VsyncOption")
onready var telemetry_toggle = find_node("TelemetryToggle")
onready var back_button = find_node("Back")

# Internal render resolutions (the game renders here and is stretched to the
# window). Lower = more retro/CRT look and better performance.
var render_resolutions = [
	Vector2(640, 480),
	Vector2(800, 600),
	Vector2(960, 540),
	Vector2(1280, 720),
	Vector2(1600, 900),
	Vector2(1920, 1080)
]
var render_scales: Array = [1.0, 0.9, 0.75, 0.6]

# Tamaño de diseño del panel y margen minimo contra los bordes de la pantalla.
const PANEL_PREFERRED_SIZE := Vector2(560, 400)
const MIN_PANEL_SIZE := Vector2(240, 180)
const VIEWPORT_MARGIN := 8.0

func _ready():
	_setup_options()
	_load_ui_values()
	_connect_signals()
	_setup_update_button()
	# El propio menu cambia la escala de render, que redimensiona el viewport: hay que
	# re-encajar el panel. La señal cubre ademas resolucion interna, fullscreen y la
	# rotacion de pantalla en movil.
	get_viewport().connect("size_changed", self, "_fit_to_viewport")
	_fit_to_viewport()
	back_button.grab_focus()

# Si el usuario descartó el diálogo de actualización, ofrecer aquí un acceso para
# reabrirlo (requisito UX: el dismiss debe ser recuperable desde Opciones). El botón
# se crea solo cuando hay un update pendiente, junto al botón Back.
func _setup_update_button():
	var vn = get_node_or_null("/root/VersionNotification")
	if vn == null or not vn.has_method("has_pending_update"):
		return
	if not vn.has_pending_update():
		return
	var container = back_button.get_parent()
	if container == null:
		return
	var btn = Button.new()
	btn.name = "UpdateAvailable"
	btn.text = "Ver actualización disponible"
	container.add_child(btn)
	# Colocarlo justo antes de Back.
	container.move_child(btn, back_button.get_index())
	btn.connect("pressed", self, "_on_update_button_pressed")

func _on_update_button_pressed():
	var vn = get_node_or_null("/root/VersionNotification")
	if vn and vn.has_method("reopen_update_dialog"):
		vn.reopen_update_dialog()

func _setup_options():
	# Touch is also emulated as mouse input. Without an exclusive popup, the
	# release can fall through the dropdown and press the setting underneath it.
	for option in [fullscreen_option, resolution_option, render_scale_option, vsync_option]:
		option.get_popup().set_exclusive(true)

	fullscreen_option.clear()
	fullscreen_option.add_item("Ventana")
	fullscreen_option.add_item("Pantalla Completa")

	resolution_option.clear()
	for res in render_resolutions:
		resolution_option.add_item("%dx%d" % [res.x, res.y])

	render_scale_option.clear()
	for scale in render_scales:
		render_scale_option.add_item("%d%%" % int(scale * 100.0))

	vsync_option.clear()
	vsync_option.add_item("Desactivado")
	vsync_option.add_item("Activado")

	_hide_desktop_only_options()

# En movil la app siempre corre a pantalla completa: el selector Ventana/Pantalla
# Completa no hace nada y solo gasta dos filas de un menu que ya queda justo con las
# escalas de render bajas. Misma deteccion que usa MobileUIManager.
func _hide_desktop_only_options() -> void:
	if not _is_mobile():
		return
	var label := find_node("FullscreenLabel") as Control
	if label != null:
		label.visible = false
	fullscreen_option.visible = false

func _is_mobile() -> bool:
	if OS.get_name() == "Switch":
		return false
	# ODISEA_FORCE_MOBILE_PROFILE es el mismo interruptor que usan AdaptiveRenderScale y
	# MobileLightBudget para ensayar el perfil movil desde escritorio.
	if OS.get_environment("ODISEA_FORCE_MOBILE_PROFILE") in ["1", "true", "yes", "on"]:
		return true
	return OS.has_touchscreen_ui_hint() or OS.get_name() in ["Android", "iOS"]

func _load_ui_values():
	var sm = get_node_or_null("/root/SettingsManager")
	if not sm: return

	master_slider.value = sm.master_volume
	music_slider.value = sm.music_volume
	sfx_slider.value = sm.sfx_volume
	invert_y_toggle.pressed = sm.invert_y
	vibration_toggle.pressed = sm.vibration
	telemetry_toggle.pressed = sm.telemetry_enabled

	fullscreen_option.selected = 1 if sm.fullscreen else 0
	vsync_option.selected = 1 if sm.vsync else 0

	# Select the active render resolution in the dropdown.
	for i in range(render_resolutions.size()):
		if render_resolutions[i] == sm.render_resolution:
			resolution_option.selected = i
			break
	for i in range(render_scales.size()):
		if is_equal_approx(render_scales[i], sm.render_scale):
			render_scale_option.selected = i
			break

func _connect_signals():
	master_slider.connect("value_changed", self, "_on_master_volume_changed")
	music_slider.connect("value_changed", self, "_on_music_volume_changed")
	sfx_slider.connect("value_changed", self, "_on_sfx_volume_changed")
	invert_y_toggle.connect("toggled", self, "_on_invert_y_toggled")
	vibration_toggle.connect("toggled", self, "_on_vibration_toggled")
	fullscreen_option.connect("item_selected", self, "_on_fullscreen_selected")
	resolution_option.connect("item_selected", self, "_on_resolution_selected")
	render_scale_option.connect("item_selected", self, "_on_render_scale_selected")
	vsync_option.connect("item_selected", self, "_on_vsync_selected")
	telemetry_toggle.connect("toggled", self, "_on_telemetry_toggled")
	back_button.connect("pressed", self, "_on_back_pressed")

func _on_master_volume_changed(value):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.master_volume = value
		sm.apply_audio_settings()

func _on_music_volume_changed(value):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.music_volume = value
		sm.apply_audio_settings()

func _on_sfx_volume_changed(value):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.sfx_volume = value
		sm.apply_audio_settings()

func _on_invert_y_toggled(button_pressed):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.invert_y = button_pressed

func _on_vibration_toggled(button_pressed):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.vibration = button_pressed

func _on_fullscreen_selected(index):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.fullscreen = (index == 1)
		sm.apply_display_settings()

func _on_resolution_selected(index):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.render_resolution = render_resolutions[index]
		sm.apply_render_resolution()

func _on_render_scale_selected(index: int) -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.render_scale = render_scales[index]
		sm.apply_render_resolution()

func _on_vsync_selected(index):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.vsync = (index == 1)
		sm.apply_display_settings()

func _on_telemetry_toggled(button_pressed: bool) -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.telemetry_enabled = button_pressed
		sm.apply_privacy_settings()
		sm.save_settings()

func _on_back_pressed():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.save_settings()

	if get_parent() == get_tree().root:
		queue_free()
	else:
		hide()
		var parent = get_parent()
		if parent.has_node("VBoxContainer/Options"):
			parent.find_node("Options").grab_focus()
		elif parent.has_node("VBoxContainer/Opciones"):
			parent.find_node("Opciones").grab_focus()

func on_show():
	_load_ui_values()
	_fit_to_viewport()
	back_button.grab_focus()

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back_pressed()
		get_tree().set_input_as_handled()

# El panel trae un rect_min_size de 560x400 pensado para la resolucion nominal, pero
# con stretch "viewport" bajar la escala de render encoge el espacio de coordenadas
# de la UI: al 60% sobre 640x480 quedan 384x288 y el panel ya no entra, con lo que
# VOLVER cae fuera de la pantalla y no hay forma de salir del menu con el dedo.
# Lo acotamos al viewport (el ScrollContainer del medio absorbe el resto), asi el
# boton queda siempre alcanzable a cualquier escala.
func _fit_to_viewport() -> void:
	var panel := get_node_or_null("CenterContainer/PanelContainer") as Control
	if panel == null:
		return
	# El area del padre, no el viewport: bajo un UIScaleCompensator el menu vive en el
	# espacio nominal (mas grande que el viewport real) y medir contra el viewport lo
	# encogeria de mas.
	var available: Vector2 = get_parent_area_size() - Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN) * 2.0
	panel.rect_min_size = Vector2(
		min(PANEL_PREFERRED_SIZE.x, max(available.x, MIN_PANEL_SIZE.x)),
		min(PANEL_PREFERRED_SIZE.y, max(available.y, MIN_PANEL_SIZE.y))
	)
