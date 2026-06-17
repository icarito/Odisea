extends ColorRect

onready var master_slider = find_node("MasterSlider")
onready var music_slider = find_node("MusicSlider")
onready var sfx_slider = find_node("SFXSlider")
onready var invert_y_toggle = find_node("InvertYToggle")
onready var vibration_toggle = find_node("VibrationToggle")
onready var fullscreen_option = find_node("FullscreenOption")
onready var resolution_option = find_node("ResolutionOption")
onready var vsync_option = find_node("VsyncOption")
onready var back_button = find_node("Back")

var resolutions = [
	Vector2(1280, 720),
	Vector2(1366, 768),
	Vector2(1600, 900),
	Vector2(1920, 1080),
	Vector2(2560, 1440),
	Vector2(3840, 2160)
]

func _ready():
	_setup_options()
	_load_ui_values()
	_connect_signals()
	back_button.grab_focus()

func _setup_options():
	resolution_option.clear()
	for res in resolutions:
		resolution_option.add_item("%dx%d" % [res.x, res.y])

	fullscreen_option.clear()
	fullscreen_option.add_item("Ventana")
	fullscreen_option.add_item("Pantalla Completa")

	vsync_option.clear()
	vsync_option.add_item("Desactivado")
	vsync_option.add_item("Activado")

func _load_ui_values():
	var sm = get_node_or_null("/root/SettingsManager")
	if not sm: return

	master_slider.value = sm.master_volume
	music_slider.value = sm.music_volume
	sfx_slider.value = sm.sfx_volume
	invert_y_toggle.pressed = sm.invert_y
	vibration_toggle.pressed = sm.vibration

	fullscreen_option.selected = 1 if sm.fullscreen else 0
	vsync_option.selected = 1 if sm.vsync else 0

	# Select resolution in dropdown
	for i in range(resolutions.size()):
		if resolutions[i] == sm.resolution:
			resolution_option.selected = i
			break

func _connect_signals():
	master_slider.connect("value_changed", self, "_on_master_volume_changed")
	music_slider.connect("value_changed", self, "_on_music_volume_changed")
	sfx_slider.connect("value_changed", self, "_on_sfx_volume_changed")
	invert_y_toggle.connect("toggled", self, "_on_invert_y_toggled")
	vibration_toggle.connect("toggled", self, "_on_vibration_toggled")
	fullscreen_option.connect("item_selected", self, "_on_fullscreen_selected")
	resolution_option.connect("item_selected", self, "_on_resolution_selected")
	vsync_option.connect("item_selected", self, "_on_vsync_selected")
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
		sm.resolution = resolutions[index]
		sm.apply_display_settings()

func _on_vsync_selected(index):
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.vsync = (index == 1)
		sm.apply_display_settings()

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
	back_button.grab_focus()

func _input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back_pressed()
		get_tree().set_input_as_handled()
