extends ColorRect

onready var resume_button = find_node("Resume")
onready var restart_button = find_node("Restart")
onready var options_button = find_node("Options")
onready var main_menu_button = find_node("MainMenu")
onready var quit_button = find_node("Quit")
onready var version_label = find_node("VersionLabel")
onready var options_menu = get_node_or_null("OptionsMenu")

func _ready():
	_connect_signals()
	_update_version_label()
	if resume_button:
		resume_button.grab_focus()

func _update_version_label():
	if version_label:
		var VersionLabelHelper = load("res://core_v2/ui/VersionLabel.gd")
		if VersionLabelHelper:
			version_label.text = VersionLabelHelper.get_formatted_version()

func _connect_signals():
	resume_button.connect("pressed", self, "_on_resume_pressed")
	restart_button.connect("pressed", self, "_on_restart_pressed")
	options_button.connect("pressed", self, "_on_options_pressed")
	main_menu_button.connect("pressed", self, "_on_main_menu_pressed")
	quit_button.connect("pressed", self, "_on_quit_pressed")

func _on_resume_pressed():
	var pm = get_node_or_null("/root/PauseManager")
	if pm:
		pm.resume()

func _on_restart_pressed():
	var pm = get_node_or_null("/root/PauseManager")
	if pm:
		pm.resume()
	get_tree().reload_current_scene()

func _on_options_pressed():
	if not is_instance_valid(options_menu):
		options_menu = get_node_or_null("OptionsMenu")
	if not is_instance_valid(options_menu):
		return
	options_menu.show()
	if options_menu.has_method("on_show"):
		options_menu.on_show()

func _on_main_menu_pressed():
	var pm = get_node_or_null("/root/PauseManager")
	if pm:
		pm.resume()
	get_tree().change_scene("res://scenes/Menu.tscn")

func _on_quit_pressed():
	if OS.get_name() == "HTML5":
		JavaScript.eval("window.close();", true)
	else:
		get_tree().quit()

func on_show():
	# on_show() can run before _ready() (e.g. PauseManager opens the menu in the same
	# frame it adds it to the tree), so options_menu (onready) may still be unset.
	if not is_instance_valid(options_menu):
		options_menu = get_node_or_null("OptionsMenu")
	if is_instance_valid(options_menu):
		options_menu.hide()
	if is_instance_valid(resume_button):
		resume_button.grab_focus()

func _input(event):
	var options_open: bool = is_instance_valid(options_menu) and options_menu.visible
	if visible and not options_open:
		if event.is_action_pressed("ui_cancel"):
			_on_resume_pressed()
			get_tree().set_input_as_handled()
