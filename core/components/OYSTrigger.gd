tool
extends BaseZone

class_name OYSTrigger

signal trigger_activated(body)

export(String, FILE, "*.oys") var script_file
export(String, FILE, "*.oys") var exit_script_file
export(String) var label_text: String = "" setget set_label_text
export(bool) var trigger_once = true
export(bool) var center_player_on_enter = false

func _ready():
	add_to_group("OYSTrigger")
	if debug_color == Color(0, 1, 0, 0.2): # Default Green
		set_debug_color(Color(0.8, 0.2, 0.8, 0.3)) # Magenta/Purple
	_update_label()

func set_label_text(val: String):
	label_text = val
	_update_label()

func _update_label():
	if not label_text or label_text == "":
		if has_node("_TriggerLabel"):
			get_node("_TriggerLabel").queue_free()
		return

	var label: Label3D
	if has_node("_TriggerLabel"):
		label = get_node("_TriggerLabel")
	else:
		label = Label3D.new()
		label.name = "_TriggerLabel"
		label.transform.origin = Vector3(0, 2, 0)
		label.billboard = SpatialMaterial.BILLBOARD_ENABLED
		label.no_depth_test = true
		add_child(label)
		label.owner = null
	
	label.text = label_text
	label.modulate = debug_color
	label.modulate.a = 1.0

func _on_zone_entered(body: Node):
	emit_signal("trigger_activated", body)
	
	# Durante JSON replay puro (is_replaying && !is_recording), NO ejecutar scripts
	# porque sus efectos ya están capturados en el input buffer.
	# Durante respawn, NO ejecutar scripts (el player está volviendo a un checkpoint)
	# Solo ejecutar durante OYS recording o gameplay normal.
	var session = get_node_or_null("/root/SessionManager")
	var is_json_replay = session and session.is_replaying and not session.is_recording
	var is_respawning = session and session.is_respawning
	
	if script_file != "" and not is_json_replay and not is_respawning:
		_run_oys_on_body(body, script_file)
	
	if trigger_once:
		# We don't disconnect signals here because BaseZone handles them
		# and we might want exit_script to still work? 
		# But "trigger_once" usually means the whole thing dies.
		# For now, let's just make sure we don't trigger ENTER again.
		script_file = ""

func _on_zone_exited(body: Node):
	var comp = body.get_node_or_null("OYSComponent")
	if comp and comp.has_method("on_trigger_exit"):
		comp.on_trigger_exit()
	
	# Durante JSON replay puro (is_replaying && !is_recording), NO ejecutar scripts
	var session = get_node_or_null("/root/SessionManager")
	var is_json_replay = session and session.is_replaying and not session.is_recording
	
	if exit_script_file != "" and not is_json_replay:
		_run_oys_on_body(body, exit_script_file)
		if trigger_once:
			exit_script_file = ""

func _run_oys_on_body(body: Node, path: String):
	var comp = body.get_node_or_null("OYSComponent")
	if not comp:
		var OYSComponentClass = load("res://core/components/OYSComponent.gd")
		comp = OYSComponentClass.new()
		comp.name = "OYSComponent"
		body.add_child(comp)
	
	# Posicionar el jugador en el centro XZ del trigger (mantener Y del jugador)
	# para que las repeticiones sean idénticas
	if body.is_in_group("player") and center_player_on_enter:
		var trigger_pos = global_transform.origin
		var player_pos = body.global_transform.origin
		
		# Solo ajustar X y Z, mantener Y del jugador
		var spawn_pos = Vector3(trigger_pos.x, player_pos.y, trigger_pos.z)
		
		# Preservar la rotación del jugador
		var player_yaw = body.yaw if "yaw" in body else 0.0
		var player_pitch = body.pitch if "pitch" in body else 0.0
		
		print("[OYSTrigger] Jugador posicionado en: ", spawn_pos)
		
		# Pasar la posición al componente para forzar posición y snapshot inicial
		comp.set_initial_position(spawn_pos, player_yaw, player_pitch)
	
	comp.load_and_start(path)
