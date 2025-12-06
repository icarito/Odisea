extends VBoxContainer

onready var host_button = $HBoxContainer/HostButton
onready var join_ip_button = $HBoxContainer/JoinIPButton
onready var ip_line_edit = $HBoxContainer/IPLineEdit
onready var server_list = $ServerList
onready var join_server_button = $JoinServerButton

func _ready():
	host_button.connect("pressed", self, "_on_HostButton_pressed")
	join_ip_button.connect("pressed", self, "_on_JoinIPButton_pressed")
	join_server_button.connect("pressed", self, "_on_JoinServerButton_pressed")

	MultiplayerManager.connect("server_discovered", self, "_on_server_discovered")
	MultiplayerManager.start_lan_discovery()

func _on_HostButton_pressed():
	MultiplayerManager.create_server()
	MultiplayerManager.start_game()

func _on_JoinIPButton_pressed():
	var ip = ip_line_edit.text
	if ip:
		MultiplayerManager.join_server(ip)

func _on_JoinServerButton_pressed():
	var selected = server_list.get_selected_items()
	if selected.size() > 0:
		var server_ip = server_list.get_item_text(selected[0])
		MultiplayerManager.join_server(server_ip)

func _on_server_discovered(ip):
	server_list.add_item(ip)

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		MultiplayerManager.stop_lan_discovery()
