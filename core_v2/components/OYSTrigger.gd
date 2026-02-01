tool
extends BaseZoneV2

class_name OYSTrigger

signal trigger_activated(body)

export(String, FILE, "*.oys") var script_file
export(String, FILE, "*.oys") var exit_script_file
export(String) var label_text: String = "" setget set_label_text
export(bool) var trigger_once = true
export(bool) var auto_pause_player = true

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
	if script_file != "":
		_run_oys_on_body(body, script_file)
	
	if trigger_once:
		# We don't disconnect signals here because BaseZoneV2 handles them
		# and we might want exit_script to still work? 
		# But "trigger_once" usually means the whole thing dies.
		# For now, let's just make sure we don't trigger ENTER again.
		script_file = ""

func _on_zone_exited(body: Node):
	if exit_script_file != "":
		_run_oys_on_body(body, exit_script_file)
		if trigger_once:
			exit_script_file = ""

func _run_oys_on_body(body: Node, path: String):
	var comp = body.get_node_or_null("OYSComponent")
	if not comp:
		var OYSComponentClass = load("res://core_v2/components/OYSComponent.gd")
		comp = OYSComponentClass.new()
		comp.name = "OYSComponent"
		body.add_child(comp)

	comp.auto_pause_player = auto_pause_player
	comp.load_and_start(path)
