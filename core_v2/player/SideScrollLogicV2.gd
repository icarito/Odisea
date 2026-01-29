# /mnt/sdd/home/icarito/Proyectos/Odisea_Game/src/core_v2/sim/SideScrollLogicV2.gd
extends Node

# Componente para manejar el estado y las restricciones del modo 2.5D

export(float) var lerp_speed := 2.0
export(float) var target_fov := 45.0
export(float) var target_pitch_deg := 0.0
export(float) var target_y_offset := 0.0
export(float) var target_spring_length := 7.0
export(float) var spring_min := 4.0
export(float) var spring_max := 20.0

# Camera Dead Zone and Smoothing
export(float) var deadzone_x := 1.5 # Shift for Look-Ahead
export(float) var deadzone_y := 0.5 # More reactive
export(float) var camera_smoothing := 5.0 # Weight factor
export(float) var zoom_smoothing := 4.0 # Smoothing for spring length changes

# Mouse Pan Settings
export(float) var pan_sensitivity := 0.05
export(float) var pan_sensitivity_y_ratio := 0.5
export(float) var pan_max_offset := 4.0
export(float) var pan_return_speed := 1.0 # Smoother return
export(float) var min_rig_height := 0.5

var is_active := false
var lock_axis := 0 # 0: None, 1: X, 2: Z
var lock_value := 0.0
var invert_side := false
var transition_alpha := 0.0

# State for deterministic camera tracking
var virtual_center := Vector3.ZERO
var lagging_center := Vector3.ZERO
var pan_offset := Vector2.ZERO
var facing_sign := 1.0 # 1: Screen Right, -1: Screen Left
var _first_frame := true

func enter_mode(axis: int, value: float, invert: bool):
	is_active = true
	lock_axis = axis
	lock_value = value
	invert_side = invert
	_first_frame = true

func exit_mode():
	is_active = false

func step(dt: float):
	var target_alpha = 1.0 if is_active else 0.0
	if transition_alpha != target_alpha:
		var step_val = lerp_speed * dt
		if transition_alpha < target_alpha:
			transition_alpha = min(transition_alpha + step_val, target_alpha)
		else:
			transition_alpha = max(transition_alpha - step_val, target_alpha)

func get_constrained_input(move_vec: Vector2) -> Vector2:
	# Siempre bloqueamos la profundidad (Y del Vector2) para mantener el plano
	return Vector2(move_vec.x, 0.0)

func apply_spatial_constraints(body: KinematicBody):
	if transition_alpha <= 0: return
	
	var pos = body.global_transform.origin
	if lock_axis == 2: # LOCK Z
		# Usamos lerp para que la entrada al eje sea suave
		pos.z = lerp(pos.z, lock_value, transition_alpha)
	elif lock_axis == 1: # LOCK X
		pos.x = lerp(pos.x, lock_value, transition_alpha)
	
	body.global_transform.origin = pos

func get_target_basis() -> Basis:
	var target_basis = Basis.IDENTITY
	
	# Aplicar Pitch deseado
	target_basis = target_basis.rotated(Vector3.RIGHT, deg2rad(target_pitch_deg))
	
	if lock_axis == 2: # Z bloqueado
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	elif lock_axis == 1: # X bloqueado
		# Miramos hacia Z+ (Screen Right es Z+ si miramos desde X-) -> Rotamos 90 grados
		target_basis = Basis(Vector3.UP, -PI / 2.0) * target_basis
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	
	return target_basis

func calculate_camera_pos(player_pos: Vector3, dt: float) -> Vector3:
	if _first_frame:
		virtual_center = player_pos
		lagging_center = player_pos
		pan_offset = Vector2.ZERO
		_first_frame = false
		return lagging_center
	
	# Horizontal tracking (Simple smoothed follow for the virtual center)
	# We'll use the deadzone as a look-ahead offset instead of a gap.
	virtual_center = virtual_center.linear_interpolate(player_pos, camera_smoothing * dt)
	
	if lock_axis == 2:
		virtual_center.z = lock_value
	elif lock_axis == 1:
		virtual_center.x = lock_value
	
	# Apply Pan Return towards the look-ahead side
	# target_pan_x is 'deadzone_x' in the look direction
	var target_pan_x = facing_sign * deadzone_x
	pan_offset.x = lerp(pan_offset.x, target_pan_x, pan_return_speed * dt)
	pan_offset.y = lerp(pan_offset.y, 0.0, pan_return_speed * dt)
	
	# Final target includes pan offset and look-ahead
	var target_lag = virtual_center
	var basis = get_target_basis()
	
	# El pan offset se aplica en el plano de la pantalla (Right/Up locales del target cam)
	target_lag += basis.x * pan_offset.x
	target_lag -= basis.y * pan_offset.y
	
	# Lagging center smoothes the final target
	lagging_center = lagging_center.linear_interpolate(target_lag, camera_smoothing * dt)
	
	# Safety height check (prevent rig from going underground)
	if lagging_center.y < min_rig_height:
		lagging_center.y = min_rig_height
	
	return lagging_center

func update_facing(move_x: float):
	if abs(move_x) > 0.1:
		facing_sign = sign(move_x)

func apply_pan(mouse_delta: Vector2):
	# Negating input to match "pull" feel
	pan_offset.x -= mouse_delta.x * pan_sensitivity
	pan_offset.y -= (mouse_delta.y * pan_sensitivity) * pan_sensitivity_y_ratio
	
	# If mouse pan is significant, change facing direction
	if abs(mouse_delta.x) > 2.0: # Threshold to avoid jitter
		facing_sign = - sign(mouse_delta.x)
	
	pan_offset.x = clamp(pan_offset.x, -pan_max_offset, pan_max_offset)
	pan_offset.y = clamp(pan_offset.y, -pan_max_offset, pan_max_offset)

func get_full_snapshot() -> Dictionary:
	return {
		"active": is_active,
		"alpha": transition_alpha,
		"axis": lock_axis,
		"val": lock_value,
		"inv": invert_side,
		"tsl": target_spring_length,
		"vc": [virtual_center.x, virtual_center.y, virtual_center.z],
		"lc": [lagging_center.x, lagging_center.y, lagging_center.z],
		"po": [pan_offset.x, pan_offset.y],
		"fs": facing_sign,
		"ff": _first_frame
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("active", false)
	transition_alpha = data.get("alpha", 0.0)
	lock_axis = data.get("axis", 0)
	lock_value = data.get("val", 0.0)
	invert_side = data.get("inv", false)
	target_spring_length = data.get("tsl", target_spring_length)
	
	if data.has("vc"):
		var vc = data["vc"]
		virtual_center = Vector3(vc[0], vc[1], vc[2])
	if data.has("lc"):
		var lc = data["lc"]
		lagging_center = Vector3(lc[0], lc[1], lc[2])
	if data.has("po"):
		var po = data["po"]
		pan_offset = Vector2(po[0], po[1])
	facing_sign = data.get("fs", 1.0)
	_first_frame = data.get("ff", true)
