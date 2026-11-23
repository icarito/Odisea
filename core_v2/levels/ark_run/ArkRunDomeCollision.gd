extends Reference

# FD-324 F7 — colisión estática horneada de los domos monumentales.
# Un único StaticBody con un SphereShape por domo (envolvente ajustada), creado
# una sola vez al construir ArkRunTerraceProps. Cero writes por frame y cero
# draw calls. Elías puede apoyarse/caminar alrededor y no atraviesa los domos.

func rebuild(parent, entries: Array) -> StaticBody:
	if parent == null:
		return null
	var previous = parent.get_node_or_null("DomeCollision")
	if previous != null:
		parent.remove_child(previous)
		previous.free()
	var body := StaticBody.new()
	body.name = "DomeCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	for entry in entries:
		var xform: Transform = entry["transform"]
		var variant: Dictionary = entry["variant"]
		var radius: float = max(float(variant["radius"]), float(variant["height"]) * 0.5)
		var sphere := SphereShape.new()
		sphere.radius = radius
		var shape := CollisionShape.new()
		shape.name = "DomeShape_%d_%d" % [int(entry["spiral_index"]), int(entry["plate_index"])]
		shape.shape = sphere
		shape.transform = Transform(
			Basis.IDENTITY,
			xform.origin + xform.basis.y.normalized() * (float(variant["height"]) * 0.5)
		)
		body.add_child(shape)
	parent.add_child(body)
	return body
