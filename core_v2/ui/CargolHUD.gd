extends Control

# core_v2/ui/CargolHUD.gd
# Circular progress bar and defensive status HUD for Cargol.

var _drone: Node = null
var _last_state := -1
var _notification_text := ""
var _notification_timer := 0.0

onready var notification_label: Label = get_node_or_null("NotificationLabel")

func _ready() -> void:
	add_to_group("hud")
	set_process(true)
	
	# Fallback if tscn wasn't used or nodes are missing
	if not notification_label:
		notification_label = Label.new()
		notification_label.name = "NotificationLabel"
		add_child(notification_label)
		notification_label.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
		notification_label.margin_bottom = -110
		notification_label.margin_right = -20
		notification_label.align = Label.ALIGN_RIGHT
		
	# Minimal size for drawing
	rect_min_size = Vector2(120, 120)
	set_anchors_and_margins_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)

func _find_drone() -> Node:
	var cargols = get_tree().get_nodes_in_group("cargol_defensive")
	if not cargols.empty():
		return cargols[0]
	return null

func _process(delta: float) -> void:
	if not _drone or not is_instance_valid(_drone):
		_drone = _find_drone()
		if not _drone:
			visible = false
			return
	
	visible = true
	
	# State change notifications
	var current_state = _drone.state if "state" in _drone else 0
	if current_state != _last_state:
		_on_state_changed(_last_state, current_state)
		_last_state = current_state
		
	# Update notification fade
	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			notification_label.text = ""
		else:
			# Gentle fade
			var alpha = clamp(_notification_timer / 1.0, 0.0, 1.0)
			notification_label.modulate.a = alpha
			
	update() # Redraw circular progress

func _on_state_changed(old_state: int, new_state: int) -> void:
	# Notification texts: "EMP LISTO", "SEÑUELO ACTIVO", "CARGOL CAÍDO"
	# States: IDLE=0, EMP_CHARGING=1, EMP_FIRING=2, EMP_COOLDOWN=3, LURE_DEPLOYED=4, STUNNED=5, RETURNING=6
	var text = ""
	if new_state == 5: # STUNNED
		text = "CARGOL CAÍDO"
	elif new_state == 4: # LURE_DEPLOYED
		text = "SEÑUELO ACTIVO"
	elif new_state == 0 and old_state != 0: # Returned to IDLE (or EMP list)
		text = "EMP LISTO"
	elif new_state == 3: # COOLDOWN
		text = "EMP ACTIVADO"
	elif new_state == 6: # RETURNING
		text = "RETORNANDO"
		
	if text != "":
		notification_label.text = text
		notification_label.modulate.a = 1.0
		_notification_timer = 3.0 # Show for 3 seconds

func _draw() -> void:
	if not _drone or not is_instance_valid(_drone):
		return
		
	var center = rect_size / 2.0
	var radius = 40.0
	
	# Draw background circle
	draw_circle(center, radius, Color(0.1, 0.1, 0.15, 0.6))
	
	# Cooldown calculation
	var remaining_cooldown = _drone.cooldown_timer if "cooldown_timer" in _drone else 0.0
	var current_state = _drone.state if "state" in _drone else 0
	
	var max_cooldown = 1.0
	if current_state == 4 or current_state == 5: # Lure or Stunned
		max_cooldown = _drone.lure_cooldown
	else:
		max_cooldown = _drone.emp_cooldown
		
	if remaining_cooldown > 0.0:
		var pct = remaining_cooldown / max_cooldown
		var start_angle = -PI / 2.0
		var end_angle = start_angle + pct * TAU
		# Draw orange circular arc representing remaining cooldown
		draw_arc(center, radius, start_angle, end_angle, 64, Color(1.0, 0.5, 0.0, 0.9), 4.0, true)
	else:
		# Draw solid blue outline when ready
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.2, 0.6, 1.0, 0.5), 2.0, true)
		
	# Draw Cargol State-colored Drone Icon
	var state_color = Color(0.2, 0.4, 1.0) # IDLE (Blue)
	match current_state:
		1: # EMP_CHARGING
			state_color = Color(1.0, 0.6, 0.0) # Pulse/Pulse
		2: # EMP_FIRING
			state_color = Color(1.0, 1.0, 1.0) # White
		3: # EMP_COOLDOWN
			state_color = Color(0.8, 0.4, 0.0) # Amber
		4: # LURE_DEPLOYED
			state_color = Color(0.2, 1.0, 0.2) # Green
		5: # STUNNED
			state_color = Color(1.0, 0.1, 0.1) # Red
		6: # RETURNING
			state_color = Color(0.2, 1.0, 1.0) # Cian
			
	# Center dot
	draw_circle(center, 8.0, state_color)
	# Wings
	draw_line(center + Vector2(-16, 0), center + Vector2(16, 0), state_color, 3.0, true)
	# Side thrusters dots
	draw_circle(center + Vector2(-16, 0), 3.0, state_color)
	draw_circle(center + Vector2(16, 0), 3.0, state_color)
