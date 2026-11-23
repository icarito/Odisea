extends Reference

# FD-324 F7 — anclajes de cuerda visibles en todo el cilindro.
# Un único MultiMeshInstance emisivo (esferas cian-dorado) para que los anclajes
# se vean a simple vista sin coste apreciable: +1 draw call, cero writes/frame.

const ANCHOR_RADIUS := 2.2
const ANCHOR_COLOR := Color(0.4, 0.95, 0.9, 1.0)
const ANCHOR_EMISSION := Color(0.35, 0.9, 1.0, 1.0)

func build(root, anchors: Array):
	if root == null or anchors.empty():
		return null
	var previous = root.get_node_or_null("RopeAnchorVisuals")
	if previous != null:
		root.remove_child(previous)
		previous.free()
	var mesh := SphereMesh.new()
	mesh.radius = ANCHOR_RADIUS
	mesh.height = ANCHOR_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.albedo_color = ANCHOR_COLOR
	material.emission_enabled = true
	material.emission = ANCHOR_EMISSION
	material.emission_energy = 1.8
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = anchors.size()
	for index in range(anchors.size()):
		var anchor = anchors[index]
		var point: Vector3 = anchor.origin if typeof(anchor) == TYPE_TRANSFORM else anchor
		multimesh.set_instance_transform(index, Transform(Basis.IDENTITY, point))
	var instance := MultiMeshInstance.new()
	instance.name = "RopeAnchorVisuals"
	instance.multimesh = multimesh
	root.add_child(instance)
	return instance
