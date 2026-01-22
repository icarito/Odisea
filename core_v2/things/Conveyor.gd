extends Area
tool

export(float) var speed_x := 2.0 setget set_speed_x
export(bool) var is_active := true setget set_active
export(float) var acceleration := 4.0 # Units per second^2
export(bool) var require_on_floor := false
export(float) var rigid_force_multiplier := 10.0
export(bool) var debug := false
export(Color) var stripe_dark_color = Color(0.18, 0.18, 0.18, 1.0) setget set_stripe_dark_color
export(Color) var stripe_light_color = Color(0.32, 0.32, 0.30, 1.0) setget set_stripe_light_color
export(float) var stripe_emission = 0.04 setget set_stripe_emission
export(float) var stripe_tiling = 4.0 setget set_stripe_tiling
export(float) var stripe_fill = 0.35 setget set_stripe_fill

export(float) var length := 8.0 setget set_length
export(float) var width := 2.0 setget set_width
export(float) var visual_speed_multiplier := 1.0 setget set_visual_speed_multiplier

# Legacy property bridge for scenes saved with old version (Godot sets properties alphabetically)
var push_velocity: Vector3 setget set_push_velocity
var _speed_x_initialized := false

var _bodies := []
var _pending_snapshot = null
var _snapshot_applied := false
var _internal_speed := 0.0 # Current smoothed speed
var _visual_phase := 0.0 # Accumulated shader phase

func _ready():
	add_to_group("replay_sync")
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)
		
	_update_scaling()
	_internal_speed = speed_x if is_active else 0.0
	
	if debug and mat:
		print("[Conveyor] Shader params updated speed_x=", speed_x)
	# Aplicar snapshot pendiente (restore puede haberse llamado antes de _ready)
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null


func _ensure_unique_material() -> Material:
	if not has_node("Belt"):
		return null
	var mesh_instance = $Belt
	
	# We want a UNIQUE material for THIS instance.
	# If we already have a material_override, it might be shared (duplicated from another node).
	# If we don't, we grab it from the mesh.
	var mat = mesh_instance.material_override
	if not mat and mesh_instance.mesh:
		mat = mesh_instance.mesh.surface_get_material(0)
	
	if mat:
		# Always duplicate to ensure this instance doesn't affect others
		if not mat.resource_local_to_scene:
			mat = mat.duplicate()
			mesh_instance.material_override = mat
		return mat
	return null

func _update_shader_params(mat: ShaderMaterial) -> void:
	if not mat:
		return
	
	# Simplificamos: asumimos flujo en eje X local que mapea a UV.y (o UV.x según mesh)
	# Basado en el fix anterior de 90 grados:
	mat.set_shader_param("dir", Vector2(0, 1))
	
	# 1. Correct speed calculation for UV.y scrolling:
	# Patterns repeat every 1.0/tiling in UV space.
	# In world space, one cycle is exactly (8.0 / stripe_tiling) meters, 
	# because we scale 'tiling' linearly with 'length'.
	# speed (shader) = speed_x / (8.0 / stripe_tiling) = (speed_x * stripe_tiling) / 8.0
	mat.set_shader_param("phase", _visual_phase)
	mat.set_shader_param("color_a", stripe_dark_color)
	mat.set_shader_param("color_b", stripe_light_color)
	mat.set_shader_param("emission", stripe_emission)
	
	# Adjust tiling proportionally to length to avoid stretching (8m is the reference mesh length)
	var effective_tiling = stripe_tiling * (length / 8.0)
	mat.set_shader_param("tiling", effective_tiling)
	
	mat.set_shader_param("fill", stripe_fill)

func set_speed_x(v: float) -> void:
	speed_x = v
	_speed_x_initialized = true
	_trigger_shader_update()

func set_active(v: bool) -> void:
	is_active = v
	_trigger_shader_update()

func set_stripe_dark_color(v: Color) -> void:
	stripe_dark_color = v
	_trigger_shader_update()

func set_stripe_light_color(v: Color) -> void:
	stripe_light_color = v
	_trigger_shader_update()

func set_stripe_emission(v: float) -> void:
	stripe_emission = v
	_trigger_shader_update()

func set_stripe_tiling(v: float) -> void:
	stripe_tiling = max(v, 0.01)
	_trigger_shader_update()

func set_stripe_fill(v: float) -> void:
	stripe_fill = clamp(v, 0.0, 1.0)
	_trigger_shader_update()

func set_visual_speed_multiplier(v: float) -> void:
	visual_speed_multiplier = v
	_trigger_shader_update()

func set_length(v: float) -> void:
	length = max(v, 0.1)
	_update_scaling()
	_trigger_shader_update()

func set_width(v: float) -> void:
	width = max(v, 0.1)
	_update_scaling()
	_trigger_shader_update()

func _trigger_shader_update() -> void:
	if not is_inside_tree():
		return
	var mat = _ensure_unique_material()
	if mat and mat is ShaderMaterial:
		_update_shader_params(mat)

func set_push_velocity(v: Vector3) -> void:
	# Capture legacy data and convert to speed_x ONLY if speed_x hasn't been set by inspector/snapshot
	if not _speed_x_initialized and v.length() > 0.001:
		speed_x = v.length()
		if debug:
			print("[Conveyor] Captured legacy push_velocity: ", v, " -> speed_x: ", speed_x)
	_trigger_shader_update()

func _update_scaling() -> void:
	if not is_inside_tree():
		return
		
	var col = get_node_or_null("CollisionShape")
	if col and col.shape is BoxShape:
		# CRITICAL: CollisionShapes are shared resources by default. Must duplicate!
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
		# extents is 1/2 of full size. Original was 4, 0.6, 1 (Total 8, 1.2, 2)
		col.shape.extents = Vector3(length / 2.0, 0.6, width / 2.0)
		
	var ground_col = get_node_or_null("Ground/GroundCollision")
	if ground_col and ground_col.shape is BoxShape:
		if not ground_col.shape.resource_local_to_scene:
			ground_col.shape = ground_col.shape.duplicate()
		ground_col.shape.extents = Vector3(length / 2.0, 0.1, width / 2.0)
		
	var belt = get_node_or_null("Belt")
	if belt:
		# Belt original mesh size is 8m (X) x 2m (Z)
		belt.scale = Vector3(length / 8.0, 1.0, width / 2.0)
		
	# Update guardrails positions
	var gl = get_node_or_null("GuardrailSegmentLeft")
	if gl:
		gl.translation.z = (width / 2.0) + 0.2
		gl.scale.x = (length / 8.0) * 1.9755 # Scaling relative to original reference
		
	var gr = get_node_or_null("GuardrailSegmentRight")
	if gr:
		gr.translation.z = - ((width / 2.0) + 0.0) # Original was -1 for width 2
		gr.scale.x = (length / 8.0) * 1.976


func _get_conveyor_length() -> float:
	return length


func get_snapshot() -> Dictionary:
	return {
		"pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"speed_x": speed_x,
		"length": length,
		"width": width,
		"require_on_floor": require_on_floor,
		"rigid_force_multiplier": rigid_force_multiplier,
		"stripe_dark_color": [stripe_dark_color.r, stripe_dark_color.g, stripe_dark_color.b, stripe_dark_color.a],
		"stripe_light_color": [stripe_light_color.r, stripe_light_color.g, stripe_light_color.b, stripe_light_color.a],
		"stripe_emission": stripe_emission,
		"stripe_tiling": stripe_tiling,
		"stripe_fill": stripe_fill,
		"is_active": is_active,
		"internal_speed": _internal_speed,
		"visual_phase": _visual_phase
	}


func _apply_snapshot(data: Dictionary) -> void:
	# Aplicar configuración determinística desde snapshot
	if data.has("speed_x"):
		speed_x = data["speed_x"]
	elif data.has("push_velocity"): # Compatibility
		var pv = data["push_velocity"]
		var mag = Vector3(pv[0], pv[1], pv[2]).length()
		if mag > 0.001:
			speed_x = mag
	
	if debug:
		print("[Conveyor] Snapshot applied: speed_x=", speed_x)
	
	if data.has("length"): length = data["length"]
	if data.has("width"): width = data["width"]
	if data.has("require_on_floor"): require_on_floor = data["require_on_floor"]
	if data.has("rigid_force_multiplier"): rigid_force_multiplier = data["rigid_force_multiplier"]
	
	if data.has("pos"):
		var p = data["pos"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	
	if data.has("stripe_dark_color"):
		var sd = data["stripe_dark_color"]
		stripe_dark_color = Color(sd[0], sd[1], sd[2], sd[3])
	if data.has("stripe_light_color"):
		var sl = data["stripe_light_color"]
		stripe_light_color = Color(sl[0], sl[1], sl[2], sl[3])
	if data.has("stripe_emission"):
		stripe_emission = data["stripe_emission"]
	if data.has("stripe_tiling"):
		stripe_tiling = data["stripe_tiling"]
	if data.has("stripe_fill"):
		stripe_fill = data["stripe_fill"]
	
	if data.has("is_active"):
		is_active = data["is_active"]
	
	if data.has("internal_speed"):
		_internal_speed = data["internal_speed"]
	
	if data.has("visual_phase"):
		_visual_phase = data["visual_phase"]
		
	# Snapshot forces a full update of all visual components
	_update_scaling()
	_trigger_shader_update()


func restore_snapshot(data: Dictionary) -> void:
	# IGNORE snapshots in editor mode to avoid overriding inspector changes
	if Engine.editor_hint:
		return
		
	# Guardar si aún no estamos en el árbol
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)


func _physics_process(delta):
	# Don't simulate physics in editor tool mode
	if Engine.editor_hint:
		return
	step(delta)

func step(dt: float) -> void:
	var target = speed_x if is_active else 0.0
	
	if abs(_internal_speed - target) > 0.001:
		_internal_speed = move_toward(_internal_speed, target, acceleration * dt)
	elif _internal_speed != target:
		_internal_speed = target
		
	# Update phase for visual animation
	# This avoids "jumps" when speed changes by integrating speed over time
	var visible_speed = (_internal_speed * stripe_tiling / 8.0) * visual_speed_multiplier
	_visual_phase = fmod(_visual_phase + visible_speed * dt, 100.0)
	_trigger_shader_update()
	
	if _internal_speed <= 0.001:
		return
		
	# Usar get_overlapping_bodies para determinismo (stateless per frame)
	_bodies = get_overlapping_bodies()
	
	# Use normalized basis to ignore node scaling in physics calculation
	var world_push = global_transform.basis.x.normalized() * _internal_speed
	
	if debug and Engine.get_frames_drawn() % 120 == 0:
		print("[Conveyor] ", name, " | speed:", _internal_speed, " | result:", world_push)
		var mat = _ensure_unique_material()
		if mat is ShaderMaterial:
			print("  -> shader speed:", mat.get_shader_param("speed"), " emission:", mat.get_shader_param("emission"))
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if require_on_floor and body.has_method("is_on_floor") and not body.is_on_floor():
			continue
		
		# Aplicar velocidad externa y marcar como NO estática
		if body.has_method("set_external_velocity"):
			body.set_external_velocity(world_push)
			if body.has_method("set_external_source_is_static"):
				body.set_external_source_is_static(false)
			if debug:
				print("[Conveyor] push to:", body.get_name() if body.has_method("get_name") else body, " vel:", world_push)
		elif body is RigidBody:
			# Use constant force for RigidBodies
			body.add_central_force(world_push * rigid_force_multiplier * 5.0)
			if debug and Engine.get_frames_drawn() % 120 == 0:
				print("[Conveyor] add_central_force ->", world_push * rigid_force_multiplier * 5.0, " for:", body)
