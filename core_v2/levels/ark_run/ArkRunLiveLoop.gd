extends Node

# FD-324 F7 — loop jugable real del Ark-Run.
# Arranca en ZERO_G (r=4, z=0, +Z), detona solo a los 3 s y desde ahí tickea
# handrails, propulsores (LT/F), cuerda (RT/E), ascensores, encendido y
# conversión; aplica cámara (un solo escritor), carrera/fantasma, sombra, LOD y
# HUD. Reinicio en Backspace/F5. Sin randf()/randomize().

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

const DETONATION_SEC := 3.0
const HUD_INTERVAL := 0.1
const RESTART_KEYS := [KEY_BACKSPACE, KEY_F5]
const SLICE_HALF := 1000.0
const FLIGHT_SPRING_LENGTH := 22.0; const GROUND_SPRING_LENGTH := 5.0; const SPRING_LERP_SPEED := 3.0

var wiring = null
var slice = null
var feedback = null
var _tick_time := 0.0
var _detonation_timer := 0.0
var _hud_accum := 0.0
var _restart_held := false
var _spring_arm = null
var _base_spring_length := 4.0

func setup(owner_wiring) -> void:
	wiring = owner_wiring
	slice = wiring.slice
	feedback = wiring.feedback
	process_priority = 130
	_hud_accum = HUD_INTERVAL
	var rig = slice.pilot.get_node_or_null("CameraRig") if slice.pilot != null else null
	if rig != null:
		_spring_arm = rig.find_node("SpringArm", true, false)
	if _spring_arm != null:
		_base_spring_length = float(_spring_arm.spring_length)

func advance_play_loop(delta: float) -> void:
	var dt: float = max(delta, 0.0)
	_tick_time += dt
	if not slice.explosion.launched:
		_detonation_timer += dt
		if _detonation_timer >= DETONATION_SEC:
			slice.activate_spin_gravity()
			slice.explosion.trigger_explosion()
			if wiring.race != null:
				wiring.race.start_run()
	_tick_modules(dt)
	present(dt)
	_hud_accum += dt
	if wiring.hud != null and _hud_accum >= HUD_INTERVAL:
		_hud_accum = 0.0
		wiring.hud.refresh(_hud_data())

func _tick_modules(dt: float) -> void:
	var pilot = slice.pilot
	if pilot == null or not is_instance_valid(pilot):
		return
	var pos: Vector3 = pilot.global_transform.origin
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if slice.handrails != null:
		if not slice.explosion.launched and slice.handrails.is_in_core(pos):
			slice.handrails.grab(pilot)
		else:
			slice.handrails.release()
	if feedback != null:
		feedback.tick(dt, pilot, physics, pos)
	for spoke in slice.spokes:
		spoke.step_elevator(_tick_time)
	if wiring.ignition != null:
		wiring.ignition.tick(dt, pos.z)
	if wiring.conversion != null:
		wiring.conversion.advance(dt)

func present(dt: float) -> void:
	var pilot = slice.pilot
	if pilot == null or not is_instance_valid(pilot) or not pilot.is_spin_real_active():
		if pilot != null and is_instance_valid(pilot) and slice.spin_predictor != null:
			slice.spin_predictor.visible = false
		return
	if wiring.ignition == null:
		return
	var pos: Vector3 = pilot.global_transform.origin
	var r_local: float = slice.r_local_for_position(pos)
	var a_axial: float = wiring.ignition.get_axial_accel()
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if physics != null:
		physics.a_axial = a_axial
	_apply_camera(dt, pilot, pos, r_local, physics)
	_update_predictor(dt, pilot, pos, r_local, a_axial, physics)
	if wiring.shadow != null:
		wiring.shadow.update_shadow(pos, slice.spin_omega, a_axial)
	if wiring.lod != null:
		wiring.lod.update_lod_for_position(pos)
	_update_race(dt, pilot)
	_poll_restart()

# Un solo escritor: la 3ra persona natural de SpinLab manda. El SpringArm queda
# SIEMPRE con basis identidad (sin basis_extra de mundo) y en vuelo libre sólo se
# aleja suavemente su spring_length; al aterrizar vuelve solo. Sin jalones.
func _apply_camera(dt: float, pilot, pos: Vector3, r_local: float, physics) -> void:
	var airborne: bool = not bool(physics._was_grounded) if physics != null else not pilot.is_on_floor()
	if _spring_arm == null:
		var rig: Spatial = pilot.get_node_or_null("CameraRig") as Spatial
		if rig != null:
			_spring_arm = rig.find_node("SpringArm", true, false)
	if _spring_arm != null:
		_spring_arm.transform.basis = Basis.IDENTITY
		var flying: bool = slice.explosion.launched and airborne
		var target_length: float = FLIGHT_SPRING_LENGTH if flying else max(_base_spring_length, GROUND_SPRING_LENGTH)
		var current: float = float(_spring_arm.spring_length)
		_spring_arm.spring_length = lerp(current, target_length, clamp(dt * SPRING_LERP_SPEED, 0.0, 1.0))
	if slice.spin_camera != null:
		slice.spin_camera.apply_to_pilot(pilot, r_local, dt)

func _update_predictor(dt: float, pilot, pos: Vector3, r_local: float, a_axial: float, physics) -> void:
	if slice.spin_predictor == null or not is_instance_valid(slice.spin_predictor):
		return
	if slice.explosion != null and not slice.explosion.should_show_predictor_at(pos):
		slice.spin_predictor.visible = false
		return
	var airborne: bool = not bool(physics._was_grounded) if physics != null else not pilot.is_on_floor()
	slice.spin_predictor.update_preview(
		pos, pilot.velocity, slice.spin_omega, r_local, airborne, dt, 1800, a_axial)

func _up_of(pilot, pos: Vector3) -> Vector3:
	if pilot.has_method("get_sim_up"):
		return pilot.get_sim_up()
	return SpinFrame.up(pos, Vector3.UP)

func _update_race(dt: float, pilot) -> void:
	if wiring.race == null:
		return
	if wiring.race.running:
		wiring.race.tick(dt, pilot.global_transform.origin, pilot.global_transform.basis)
	if wiring.race.has_ghost_trace():
		wiring.race.update_ghost_visual(wiring.race.t_run)

func _poll_restart() -> void:
	var held: bool = false
	for key in RESTART_KEYS:
		held = held or Input.is_key_pressed(key)
	if held and not _restart_held:
		restart_run()
	_restart_held = held

# Reinicio instantáneo: ZERO_G + cuenta regresiva + placas restauradas; conserva
# best_time y fantasma. Sin recargar la escena.
func restart_run() -> void:
	if slice.pilot != null:
		slice.pilot.set_spin_real_enabled(false)
		slice.deactivate_spin_gravity()
		slice.spawn_at_hub_start()
	if slice.explosion != null and slice.explosion.has_method("reset"):
		slice.explosion.reset()
	if wiring.ignition != null:
		wiring.ignition.reset()
	if wiring.conversion != null:
		wiring.conversion.reset()
	if wiring.race != null:
		wiring.race.restart_run()
	if slice.handrails != null:
		slice.handrails.release()
	_tick_time = 0.0
	_detonation_timer = 0.0
	_hud_accum = HUD_INTERVAL
	if wiring.hud != null:
		wiring.hud.refresh(_hud_data())

func _hud_data() -> Dictionary:
	var pilot = slice.pilot
	var pos: Vector3 = pilot.global_transform.origin if pilot != null else Vector3.ZERO
	var physics = pilot.get_spin_physics() if pilot != null and pilot.has_method("get_spin_physics") else null
	var a_axial: float = wiring.ignition.get_axial_accel() if wiring.ignition != null else 0.0
	var radial: float = SpinFrame.r_perp(pos).length()
	var g: float = sqrt(pow(SpinFrame.a_centrif(pos, slice.spin_omega).length(), 2.0) + a_axial * a_axial)
	var g_dir: Vector3 = (SpinFrame.a_centrif(pos, slice.spin_omega) + Vector3(0.0, 0.0, a_axial)).normalized()
	var dv_ratio: float = 0.0
	if physics != null and float(physics.spin_thruster_dv_max) > 0.0:
		dv_ratio = float(physics.spin_thruster_dv_remaining) / float(physics.spin_thruster_dv_max)
	var phase := "NÚCLEO ZERO-G · Explosión en %.1fs" % max(0.0, DETONATION_SEC - _detonation_timer)
	if wiring.race != null and wiring.race.finished:
		phase = "¡META EN MOTOR!"
	elif wiring.ignition != null and wiring.ignition.is_ignited():
		phase = "¡ENCENDIDO DE MOTORES!"
	elif slice.explosion.launched:
		phase = "VUELA AL PUENTE (+Z)" if pos.z >= 0.0 else "BAJA AL MOTOR (-Z)"
	return {
		"phase": phase, "timer": wiring.race.t_run if wiring.race != null else 0.0,
		"best": wiring.race.best_time_sec if wiring.race != null else -1.0,
		"g": g, "g_dir_x": g_dir.x, "g_dir_z": g_dir.z, "dv": dv_ratio,
		"thrusting": feedback.thrusting if feedback != null else false,
		"rope": feedback.rope_state if feedback != null else "IDLE",
		"rope_distance": feedback.rope_distance if feedback != null else 0.0,
		"radial": radial / max(slice.get_hull_radius(), 1.0), "z": pos.z / SLICE_HALF,
		"bridge": 1.0, "engine": 0.0,
	}
