tool
extends EditorSpatialGizmoPlugin

const OcclusionArea = preload("res://core/components/OcclusionZone.gd")

var undo_redo: UndoRedo

func _init():
	create_material("main", Color(1, 1, 0))
	create_handle_material("handles")

func get_name():
	return "AreaResizeGizmo"

func has_gizmo(spatial):
	return spatial is BaseZone

func _get_target_shape(spatial):
	if not spatial is BaseZone: return null
	
	var host = null
	var raw_host = spatial.get("_host_area")
	if raw_host is Object:
		host = raw_host
	
	if not host:
		# Fallback detection if _host_area isn't set yet
		if spatial is Area: host = spatial
		elif spatial.get_parent() is Area: host = spatial.get_parent()
	
	if not (host is Object) or not (host is Node): return null
	
	for child in host.get_children():
		if child is CollisionShape and child.shape is BoxShape:
			return child
	return null

func redraw(gizmo):
	gizmo.clear()
	var spatial = gizmo.get_spatial_node()
	var shape_node = _get_target_shape(spatial)
	if not shape_node: return
	
	var box = shape_node.shape
	var extents = box.extents

	var lines = PoolVector3Array()
	var center = Vector3.ZERO # Local to the shape node

	# Draw box wireframe relative to the shape node's transform
	for i in range(8):
		var p1 = center + Vector3(extents.x if i & 1 else -extents.x, extents.y if i & 2 else -extents.y, extents.z if i & 4 else -extents.z)
		for j in [1, 2, 4]:
			if not (i & j):
				var p2 = p1
				if j == 1: p2.x += extents.x * 2.0
				if j == 2: p2.y += extents.y * 2.0
				if j == 4: p2.z += extents.z * 2.0
				
				# Convert to spatial-local space for gizmo drawing
				var world_p1 = shape_node.to_global(p1)
				var world_p2 = shape_node.to_global(p2)
				lines.push_back(spatial.to_local(world_p1))
				lines.push_back(spatial.to_local(world_p2))

	gizmo.add_lines(lines, get_material("main", gizmo), false)

	# Add handles
	var handles = PoolVector3Array()
	# Order: +X, -X, +Y, -Y, +Z, -Z
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(extents.x, 0, 0))))
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(-extents.x, 0, 0))))
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(0, extents.y, 0))))
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(0, -extents.y, 0))))
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(0, 0, extents.z))))
	handles.push_back(spatial.to_local(shape_node.to_global(center + Vector3(0, 0, -extents.z))))
	
	gizmo.add_handles(handles, get_material("handles", gizmo))

func get_handle_name(gizmo, index):
	match index:
		0: return "Length +"
		1: return "Length -"
		2: return "Height +"
		3: return "Height -"
		4: return "Width +"
		5: return "Width -"
	return ""

func get_handle_value(gizmo, index):
	var spatial = gizmo.get_spatial_node()
	var shape_node = _get_target_shape(spatial)
	if not shape_node: return 0.0
	var extents = shape_node.shape.extents
	match index:
		0, 1: return extents.x * 2.0
		2, 3: return extents.y * 2.0
		4, 5: return extents.z * 2.0
	return 0.0

func set_handle(gizmo, index, camera, point):
	var spatial = gizmo.get_spatial_node()
	var shape_node = _get_target_shape(spatial)
	if not shape_node: return
	
	var gt = shape_node.global_transform
	
	var ray_from = camera.project_ray_origin(point)
	var ray_dir = camera.project_ray_normal(point)
	var ray_to = ray_from + ray_dir * 4096
	
	var axis = Vector3.ZERO
	var line_origin = gt.origin
	
	match index:
		0, 1: axis = gt.basis.x
		2, 3: axis = gt.basis.y
		4, 5: axis = gt.basis.z
			
	var line_from = line_origin - axis * 4096
	var line_to = line_origin + axis * 4096
	
	var closest_points = Geometry.get_closest_points_between_segments(ray_from, ray_to, line_from, line_to)
	var local_point = gt.affine_inverse().xform(closest_points[1])
	
	var extents = shape_node.shape.extents
	var new_extents = extents
	
	match index:
		0: new_extents.x = abs(local_point.x)
		1: new_extents.x = abs(local_point.x)
		2: new_extents.y = abs(local_point.y)
		3: new_extents.y = abs(local_point.y)
		4: new_extents.z = abs(local_point.z)
		5: new_extents.z = abs(local_point.z)

	# Apply Snapping
	if Input.is_key_pressed(KEY_CONTROL):
		var snap_step = 0.5 # Snapping for extents
		if Input.is_key_pressed(KEY_SHIFT):
			snap_step = 0.05
		
		new_extents.x = stepify(new_extents.x, snap_step)
		new_extents.y = stepify(new_extents.y, snap_step)
		new_extents.z = stepify(new_extents.z, snap_step)

	shape_node.shape.extents = Vector3(max(0.05, new_extents.x), max(0.05, new_extents.y), max(0.05, new_extents.z))

	shape_node.property_list_changed_notify()
	redraw(gizmo)

func commit_handle(gizmo, index, restore, cancel = false):
	var spatial = gizmo.get_spatial_node()
	var shape_node = _get_target_shape(spatial)
	if not shape_node: return
	
	var box = shape_node.shape
	
	if cancel:
		box.extents = restore
		return
 
	if not undo_redo:
		return
 
	undo_redo.create_action("Resize Zone Collision")
	undo_redo.add_do_property(box, "extents", box.extents)
	undo_redo.add_undo_property(box, "extents", restore)
	undo_redo.commit_action()
