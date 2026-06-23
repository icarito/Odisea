extends Control

# CargolHUD.gd
# Minimal HUD overlay showing Cargol Drone status and distance.

var _drone: Node = null
var _player: Node = null

onready var status_label = get_node_or_null("VBoxContainer/Status")
onready var distance_label = get_node_or_null("VBoxContainer/Distance")

func _ready():
	add_to_group("hud")
	# Initial search
	_drone = _find_drone()
	_player = _find_player()
	
	if not status_label:
		# Fallback if tscn wasn't used or nodes are missing
		var vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		add_child(vbox)
		status_label = Label.new()
		status_label.name = "Status"
		vbox.add_child(status_label)
		distance_label = Label.new()
		distance_label.name = "Distance"
		vbox.add_child(distance_label)
		
		# Position top right
		vbox.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)

func _process(_delta):
	if not _drone or not is_instance_valid(_drone):
		_drone = _find_drone()
		if not _drone:
			visible = false
			return
	
	visible = true
	if not _player or not is_instance_valid(_player):
		_player = _find_player()
	
	_update_ui()

func _update_ui():
	var state_text = "IDLE"
	var state_color = Color.white
	
	# Map states to text/color
	if "current_state" in _drone:
		var state = _drone.current_state
		match state:
			0: # IDLE
				state_text = "IDLE"
				state_color = Color(0.5, 0.7, 1.0)
			1: # FOLLOW_PATH
				state_text = "FOLLOWING PATH"
				state_color = Color(0.5, 1.0, 0.7)
			2: # FOLLOW_TARGET
				state_text = "FOLLOWING PLAYER"
				state_color = Color(0.5, 0.7, 1.0)
			3: # RETURN_HOME
				state_text = "RETURNING HOME"
				state_color = Color(0.5, 1.0, 0.7)
			4: # ALERT
				state_text = "ALERT"
				state_color = Color(1.0, 0.5, 0.5)
			5: # SEARCH
				state_text = "SEARCHING"
				state_color = Color(1.0, 0.8, 0.5)
			6: # MOVE_TO
				state_text = "MOVING TO"
				state_color = Color(0.5, 0.7, 1.0)
	
	status_label.text = "CARGOL: " + state_text
	status_label.add_color_override("font_color", state_color)
	
	if _player and is_instance_valid(_player):
		var dist = _drone.global_transform.origin.distance_to(_player.global_transform.origin)
		distance_label.text = "DIST: %.1fm" % dist
	else:
		distance_label.text = ""

func _find_drone() -> Node:
	var drones = get_tree().get_nodes_in_group("cargol_drone")
	if not drones.empty():
		return drones[0]
	return null

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if not players.empty():
		return players[0]
	return null
