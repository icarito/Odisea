# /mnt/sdd/home/icarito/Proyectos/Odisea_Game/src/core_v2/sim/SideScrollLogicV2.gd
extends Node

# Componente para manejar el estado y las restricciones del modo 2.5D

export(float) var lerp_speed := 2.0
export(float) var target_fov := 45.0
export(float) var target_pitch_deg := 0.0
export(float) var target_y_offset := 0.0
export(float) var target_spring_length := 7.0

var is_active := false
var lock_axis := 0 # 0: None, 1: X, 2: Z
var lock_value := 0.0
var invert_side := false
var transition_alpha := 0.0

func enter_mode(axis: int, value: float, invert: bool):
	is_active = true
	lock_axis = axis
	lock_value = value
	invert_side = invert

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
		pos.z = lock_value
	elif lock_axis == 1: # LOCK X
		pos.x = lock_value
	
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

func get_full_snapshot() -> Dictionary:
	return {
		"active": is_active,
		"alpha": transition_alpha,
		"axis": lock_axis,
		"val": lock_value,
		"inv": invert_side
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("active", false)
	transition_alpha = data.get("alpha", 0.0)
	lock_axis = data.get("axis", 0)
	lock_value = data.get("val", 0.0)
	invert_side = data.get("inv", false)
