extends Spatial

export(bool) var settle_pushables_on_ready := true

func _ready() -> void:
	if settle_pushables_on_ready:
		call_deferred("_settle_pushables")

func _settle_pushables() -> void:
	_settle_pushables_recursive(self)

func _settle_pushables_recursive(root: Node) -> void:
	for child in root.get_children():
		if child is RigidBody:
			var body: RigidBody = child as RigidBody
			body.mode = RigidBody.MODE_KINEMATIC
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = false
			if body.has_method("_refresh_wake_area"):
				body.call("_refresh_wake_area")
		_settle_pushables_recursive(child)
