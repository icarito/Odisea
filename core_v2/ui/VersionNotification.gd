extends CanvasLayer

onready var panel = $Control/MarginContainer/PanelContainer
onready var label = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/Label
onready var downloads_button = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/DownloadsButton
onready var close_button = $Control/MarginContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CloseButton

var _downloads_url := ""
var _is_dismissed := false

func _ready():
	panel.hide()

	if not VersionChecker.is_connected("new_version_available", self, "_on_new_version_available"):
		VersionChecker.connect("new_version_available", self, "_on_new_version_available")

	close_button.connect("pressed", self, "_on_close_pressed")
	downloads_button.connect("pressed", self, "_on_downloads_pressed")

	# Check if VersionChecker already has an update found (it might have run before we were instanced)
	if VersionChecker.has_update and not _is_dismissed:
		_show_notification(VersionChecker.latest_version_data)

func _on_new_version_available(data: Dictionary):
	if not _is_dismissed:
		_show_notification(data)

func _show_notification(data: Dictionary):
	var new_ver = data.get("version", "v?.?.?")
	_downloads_url = data.get("downloads_page", "")

	if OS.get_name() == "HTML5":
		label.text = "v%s disponible — recarga para obtenerla" % new_ver
		downloads_button.hide()
	else:
		label.text = "v%s disponible" % new_ver
		downloads_button.show()

	panel.show()

	# Optional: Animation or Sound
	if has_node("AnimationPlayer"):
		$AnimationPlayer.play("show")

func _on_close_pressed():
	panel.hide()
	_is_dismissed = true

func _on_downloads_pressed():
	if _downloads_url != "":
		OS.shell_open(_downloads_url)
	_on_close_pressed()
