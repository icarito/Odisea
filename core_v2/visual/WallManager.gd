extends Node

# WallManager.gd
# Updates the 'player_pos' parameter in all relevant materials.
# Now handles automatic conversion of SpatialMaterials to dithered ShaderMaterials.

export(NodePath) var target_node_path
export(Material) var walls_material # Optional: template material to update if used directly
export(float) var hole_radius = 1.5
export(float) var softness = 1.0
export(bool) var debug_visualization = false

var _player: Spatial
var _last_pos: Vector3 = Vector3.ZERO
var _last_cam_pos: Vector3 = Vector3.ZERO
var _threshold: float = 0.05 # Only update if moved more than 5cm
var _materials: Array = []
var _target_node: Node
var _camera: Camera

func _ready():
	# Sync initial values from walls_material if it's a ShaderMaterial
	if walls_material is ShaderMaterial:
		var r = walls_material.get_shader_param("hole_radius")
		if r != null: hole_radius = r
		var s = walls_material.get_shader_param("softness")
		if s != null: softness = s
	_find_player()
	_find_camera()
	
	if target_node_path:
		if has_node(target_node_path):
			_target_node = get_node(target_node_path)
		else:
			# Fallback search by name
			var node_name = str(target_node_path).get_file()
			_target_node = get_tree().current_scene.find_node(node_name, true, false)
			if _target_node:
				print("[WallManager] Target node not found at path, but found by name: ", _target_node.get_path())
			else:
				printerr("[WallManager] Could not find target node: ", target_node_path)
	
	# Delay material collection to ensure Qodot has built everything
	yield (get_tree().create_timer(1.0), "timeout")
	_collect_materials()

func _find_player():
	var sm = get_node_or_null("/root/SessionManager")
	if sm and "player" in sm and sm.player:
		_player = sm.player
	else:
		# Fallback search
		_player = get_tree().get_root().find_node("Pilot", true, false)

func _find_camera():
	_camera = get_viewport().get_camera()
	if not _camera:
		# Fallback: search in scene
		_camera = get_tree().current_scene.find_node("Camera", true, false)

func _collect_materials():
	_materials.clear()
	if walls_material:
		if walls_material is ShaderMaterial:
			_materials.append(walls_material)
	
	if _target_node:
		var meshes = []
		_find_all_meshes(_target_node, meshes)
		print("[WallManager] Scanning ", meshes.size(), " meshes for materials...")
		for mesh_instance in meshes:
			# Check surface materials
			for i in range(mesh_instance.get_surface_material_count()):
				_process_material(mesh_instance, i)
			
			# Check material override
			if mesh_instance.material_override:
				_process_material(mesh_instance, -1)
	
	print("[WallManager] Collected ", _materials.size(), " total materials to update.")

func _process_material(mesh_instance: MeshInstance, index: int):
	var mat
	if index == -1:
		mat = mesh_instance.material_override
	else:
		mat = mesh_instance.get_surface_material(index)
		# If no override in MeshInstance, check the Mesh resource
		if not mat:
			var mesh = mesh_instance.mesh
			if mesh:
				mat = mesh.surface_get_material(index)
	
	if not mat:
		return

	# If it's a SpatialMaterial, convert it to our Dither ShaderMaterial
	if mat is SpatialMaterial:
		var new_mat = ShaderMaterial.new()
		new_mat.shader = preload("res://shaders/dither_hiding.shader")
		new_mat.set_shader_param("albedo_texture", mat.albedo_texture)
		new_mat.set_shader_param("use_triplanar", mat.uv1_triplanar)
		new_mat.set_shader_param("uv_scale", mat.uv1_scale.x)
		
		# Apply converted material as an override in MeshInstance to not touch the shared Mesh resource
		if index == -1:
			mesh_instance.material_override = new_mat
		else:
			mesh_instance.set_surface_material(index, new_mat)
		
		mat = new_mat
	
	if mat is ShaderMaterial and not _materials.has(mat):
		# Sync all params initially
		mat.set_shader_param("debug_mode", debug_visualization)
		mat.set_shader_param("hole_radius", hole_radius)
		mat.set_shader_param("softness", softness)
		if _player:
			mat.set_shader_param("player_pos", _player.global_transform.origin)
		if _camera:
			mat.set_shader_param("camera_pos", _camera.global_transform.origin)
		_materials.append(mat)

func _find_all_meshes(node: Node, result: Array):
	if node is MeshInstance:
		result.append(node)
	for child in node.get_children():
		_find_all_meshes(child, result)

func _physics_process(_delta):
	if not _player or not is_instance_valid(_player):
		_find_player()
		if not _player:
			return
	
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
		if not _camera:
			return
			
	var current_pos = _player.global_transform.origin
	var current_cam_pos = _camera.global_transform.origin
	
	var player_moved = current_pos.distance_to(_last_pos) > _threshold
	var cam_moved = current_cam_pos.distance_to(_last_cam_pos) > _threshold
	
	# We update if player/cam moved, or if we want to ensure settings stay synced
	# To make the export variables reactive in the editor/runtime, we could check for changes,
	# but for now, player/cam movement is a good enough trigger.
	if player_moved or cam_moved:
		for mat in _materials:
			if mat is ShaderMaterial:
				mat.set_shader_param("player_pos", current_pos)
				mat.set_shader_param("camera_pos", current_cam_pos)
				mat.set_shader_param("hole_radius", hole_radius)
				mat.set_shader_param("softness", softness)
				mat.set_shader_param("debug_mode", debug_visualization)
		_last_pos = current_pos
		_last_cam_pos = current_cam_pos

# Call this if the map is rebuilt at runtime
func refresh():
	_collect_materials()
