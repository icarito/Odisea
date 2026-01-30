# core_v2/components/OYSTrigger.gd
extends Area

class_name OYSTrigger

export(String, FILE, "*.oys") var script_file
export(bool) var trigger_once = true
export(bool) var auto_pause_player = true

func _ready():
	var _res = connect("body_entered", self, "_on_body_entered")

func _on_body_entered(body):
	if body.is_in_group("player"):
		var comp = body.get_node_or_null("OYSComponent")
		if not comp:
			# Use the preloaded class or load it
			var OYSComponentClass = load("res://core_v2/components/OYSComponent.gd")
			comp = OYSComponentClass.new()
			comp.name = "OYSComponent"
			body.add_child(comp)

		comp.auto_pause_player = auto_pause_player
		if script_file != "":
			comp.load_and_start(script_file)

		if trigger_once:
			disconnect("body_entered", self, "_on_body_entered")
