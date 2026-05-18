extends Area

class_name ZeroGravityZone

func _ready() -> void:
	connect("body_entered", self, "_on_body_entered")
	connect("body_exited", self, "_on_body_exited")

func _on_body_entered(body: Node) -> void:
	print("[ZeroGravityZone] Body entered: ", body.name)
	if not body.is_in_group("player"):
		return
	
	var cm = body.get_node_or_null("ControllerManager")
	if cm and cm.has_method("switch_to"):
		cm.switch_to(cm.Mode.ZERO_GRAVITY)

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
		
	var cm = body.get_node_or_null("ControllerManager")
	if cm and cm.has_method("switch_to"):
		cm.switch_to(cm.Mode.STANDARD_1G)
