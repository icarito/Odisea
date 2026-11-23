extends Node

# FD-324 F7 — loop jugable real del Ark-Run.
# Arranca en ZERO_G (r=4, z=0, +Z), detona solo a los 3 s y desde ahí tickea
# handrails, propulsores (LT/F), cuerda (RT/E), ascensores, encendido y
# conversión; aplica cámara (un solo escritor), carrera/fantasma, sombra, LOD y
# HUD. Reinicio en Backspace/F5. Sin randf()/randomize().

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

const DETONATION_SEC := 3.0; const HUD_INTERVAL := 0.1
const RESTART_KEYS := [KEY_BACKSPACE, KEY_F5]; const SLICE_HALF := 1000.0
const FLIGHT_SPRING_LENGTH := 22.0; const GROUND_SPRING_LENGTH := 5.0; const SPRING_LERP_SPEED := 3.0
# La cuerda apunta +20 grados por encima de la mirada de camara para no elegir
# anclajes demasiado bajos en el campo visual (feedback de playtest).
const AIM_PITCH_DEG := 20.0
const EPSILON := 1e-6
# FD-325: split de la barra longitudinal del top bar: lanzamiento (-z_max) → meta (+SLICE).
const LAUNCH_Z := -940.0; const FINISH_Z := 1000.0
# Radio de llegada al Puente (sobre la superficie de la placa 48) tras detonar.
const BRIDGE_ARRIVAL_RADIUS := 45.0
# Radio de llegada al Motor (superficie de la placa 0): cierra la carrera por distancia.
const ENGINE_ARRIVAL_RADIUS := 45.0
const PresenterScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticPresenter.gd")

var wiring = null
var slice = null
var feedback = null
var _tick_time := 0.0
var _detonation_timer := 0.0
var _hud_accum := 0.0
var _restart_held := false
var _spring_arm = null
var _base_spring_length := 4.0
var _device := "keyboard"
var _tick_state: Dictionary = {}
var _presenter = null
# FD-325 polish: llegada real al Puente. `zone_at()` sólo cubre el tramo +Z completo, así
# que aterrizar en la placa 48 seguía pidiendo "vuela al puente"; este flag por corrida
# conmuta fase y marcador a MOTOR en cuanto el pilot toca el Puente.
var _bridge_reached := false

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
	_presenter = PresenterScript.new(); _presenter.name = "ArkRunDiegeticPresenter"
	add_child(_presenter); _presenter.setup(self, wiring)

func advance_play_loop(delta: float) -> void:
	var dt: float = max(delta, 0.0)
	_tick_time += dt
	if not slice.explosion.launched:
		_detonation_timer += dt
		if _detonation_timer >= DETONATION_SEC:
			slice.activate_spin_gravity()
			slice.explosion.trigger_explosion()
			_bridge_reached = false
			if wiring.race != null:
				wiring.race.start_run()
	_tick_modules(dt)
	_update_bridge_progress()
	present(dt)
	_hud_accum += dt
	if _hud_accum >= HUD_INTERVAL:
		_hud_accum = 0.0
		var data: Dictionary = _hud_data()
		if wiring.hud != null:
			wiring.hud.refresh(data)
		_update_touch_state(data)

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
	_poll_device_and_touch(pilot)
	if feedback != null:
		_tick_state = feedback.tick(dt, pilot, physics, pos)
	for spoke in slice.spokes:
		spoke.step_elevator(_tick_time)
	if wiring.ignition != null:
		wiring.ignition.tick(dt, pos.z)
	if wiring.conversion != null:
		wiring.conversion.advance(dt)

# Tras detonar, tocar el Puente (zona +Z, radio exacto de la placa 48 o contacto con la
# placa) marca la llegada: desde ese frame la fase y el marcador apuntan al Motor.
func _update_bridge_progress() -> void:
	if _bridge_reached or not slice.explosion.launched:
		return
	var pilot = slice.pilot
	if pilot == null or not is_instance_valid(pilot):
		return
	var pos: Vector3 = pilot.global_transform.origin
	if slice.is_in_bridge(pos) or pos.distance_to(slice.get_bridge_target()) <= BRIDGE_ARRIVAL_RADIUS:
		_bridge_reached = true

func present(dt: float) -> void:
	var pilot = slice.pilot
	if pilot == null or not is_instance_valid(pilot) or not pilot.is_spin_real_active():
		if pilot != null and is_instance_valid(pilot):
			if slice.spin_predictor != null:
				slice.spin_predictor.visible = false
			if wiring.shadow != null:
				wiring.shadow.set_legacy_shadow_hidden(pilot, false)
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
		wiring.shadow.update_shadow(pos, slice.spin_omega, a_axial, pilot)
	if wiring.lod != null:
		wiring.lod.update_lod_for_position(pos)
	_update_race(dt, pilot)
	if _presenter != null:
		_tick_state["device"] = _device
		_presenter.present(dt, _tick_state, pos)
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

# Eleva el vector de mirada `pitch_deg` grados alrededor del eje derecho de la
# camara, verificando el signo para que siempre incline hacia +sim_up (la
# rotacion de un vector alrededor de "right" cambia de sentido segun la base).
static func elevate_aim_dir(
	cam_fwd: Vector3, cam_right: Vector3, sim_up: Vector3,
	pitch_deg: float = AIM_PITCH_DEG
) -> Vector3:
	var forward: Vector3 = cam_fwd.normalized() if cam_fwd.length_squared() > EPSILON \
		else Vector3.FORWARD
	var right: Vector3 = cam_right.normalized() if cam_right.length_squared() > EPSILON \
		else Vector3.RIGHT
	var angle: float = deg2rad(pitch_deg)
	var rotated: Vector3 = forward.rotated(right, angle)
	if sim_up.length_squared() > EPSILON:
		var up: Vector3 = sim_up.normalized()
		if rotated.dot(up) < forward.dot(up):
			rotated = forward.rotated(right, -angle)
	return rotated.normalized()

# Aim de cuerda: el rayo CENTRAL exacto de la cámara (1:1 con el crosshair de pantalla).
# Sin elevación artificial: el anclaje elegido es el que el centro de mirilla señala.
func rope_aim_dir(pilot) -> Vector3:
	var forward: Vector3 = Vector3.FORWARD
	var camera: Camera = null
	var viewport = get_viewport()
	if viewport != null:
		camera = viewport.get_camera()
	if camera != null:
		forward = -camera.global_transform.basis.z
	elif pilot != null and is_instance_valid(pilot):
		forward = -pilot.global_transform.basis.z
	return forward.normalized() if forward.length_squared() > EPSILON else Vector3.FORWARD

func _update_race(dt: float, pilot) -> void:
	if wiring.race == null:
		return
	var pos: Vector3 = pilot.global_transform.origin
	if wiring.race.running:
		var result: Dictionary = wiring.race.tick(dt, pos, pilot.global_transform.basis)
		# El Motor es alcanzable en el centro de la placa 0 (z = -1000): cerrar también
		# por distancia al destino además del umbral z <= engine_z_max.
		if not bool(result.get("finished", false)) \
				and pos.distance_to(slice.get_engine_target()) <= ENGINE_ARRIVAL_RADIUS:
			wiring.race.finish_run(pilot.global_transform.basis)
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
	_bridge_reached = false
	if _presenter != null:
		_presenter.reset_fov()
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
	var motor_target: bool = slice.explosion.launched and (_bridge_reached or pos.z < 0.0)
	var finished: bool = wiring.race != null and wiring.race.finished
	var target_label := "MOTOR" if motor_target else "PUENTE"
	var target_pos: Vector3 = slice.get_engine_target() if motor_target else slice.get_bridge_target()
	var phase := "NÚCLEO ZERO-G · Explosión en %.1fs" % max(0.0, DETONATION_SEC - _detonation_timer)
	var target_visible := true
	if finished:
		# Meta alcanzada: se oculta el marcador y se muestran las instrucciones de reintento.
		phase = "¡META EN MOTOR! · Backspace para repetir"
		target_visible = false
	elif wiring.ignition != null and wiring.ignition.is_ignited():
		phase = "¡ENCENDIDO DE MOTORES!"
	elif slice.explosion.launched:
		phase = "BAJA AL MOTOR (-Z)" if motor_target else "VUELA AL PUENTE (+Z)"
	var data := {
		"phase": phase, "timer": wiring.race.t_run if wiring.race != null else 0.0,
		"best": wiring.race.best_time_sec if wiring.race != null else -1.0,
		"g": g, "g_dir_x": g_dir.x, "g_dir_z": g_dir.z, "dv": dv_ratio,
		"a_axial": a_axial,
		"thrusting": feedback.thrusting if feedback != null else false,
		"rope": feedback.rope_state if feedback != null else "IDLE",
		"rope_distance": feedback.rope_distance if feedback != null else 0.0,
		"radial": radial / max(slice.get_hull_radius(), 1.0), "z": pos.z / SLICE_HALF,
		"bridge": 1.0, "engine": 0.0,
		"target_pos": target_pos, "target_label": target_label,
		"target_visible": target_visible,
		"flashlight_on": _flashlight_on(), "autonav_active": _autonav_active(),
	}
	# Fantasma (mejor corrida): su z normalizado sólo viaja si hay traza grabada.
	var ghost_z = _ghost_z_norm()
	if ghost_z != null:
		data["ghost_z"] = float(ghost_z)
	return data


# --- FD-325: dispositivo activo, touch y HUD superior ---

func _input_provider(pilot):
	if pilot == null or not is_instance_valid(pilot):
		return null
	return pilot.get("input_provider")

# En touch la cuerda es toggle (tap engancha/suelta) y saltar la suelta conservando el momento;
# en mando/teclado sigue siendo hold. El aim vive 20° sobre la mirada de la cámara.
func _poll_device_and_touch(pilot) -> void:
	var provider = _input_provider(pilot)
	_device = String(provider.get_active_input_device()) \
		if provider != null and provider.has_method("get_active_input_device") else "keyboard"
	if slice.rope_input == null:
		return
	slice.rope_input.touch_toggle_mode = _device == "touch"
	if wiring.is_live_loop_running():
		slice.rope_input.set_aim_dir_override(rope_aim_dir(pilot))

# Espejo de estado a los botones táctiles (Δv, cuerda, anclaje en vista) al ritmo del HUD.
func _update_touch_state(data: Dictionary) -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui == null or not mobile_ui.has_method("update_spin_touch_state"):
		return
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	var ready: bool = attached
	if not attached and _presenter != null:
		var best: Dictionary = _presenter.best_anchor(rope_aim_dir(slice.pilot))
		ready = bool(best.get("hit", false)) \
			and _presenter.anchor_in_viewport(best.get("anchor_position", Vector3.ZERO), _presenter.camera())
	mobile_ui.update_spin_touch_state({
		"dv_ratio": float(data.get("dv", 0.0)), "rope_attached": attached,
		"anchor_ready": ready, "anchor_distance": float(data.get("rope_distance", 0.0)),
	})

func _ghost_z_norm():
	if wiring.race == null or not wiring.race.has_ghost_trace():
		return null
	var ghost_pos: Vector3 = wiring.race.get_ghost_pose(wiring.race.t_run).get("position", Vector3.ZERO)
	return clamp((ghost_pos.z - LAUNCH_Z) / (FINISH_Z - LAUNCH_Z), 0.0, 1.0)

# Chips del top bar: estado real de las apps rápidas L1 (linterna) y R1 (autonavegador).
func _flashlight_on() -> bool:
	var suit_os = get_node_or_null("/root/SuitOS")
	var screen = suit_os.get_screen("player:flashlight") \
		if suit_os != null and suit_os.has_method("get_screen") else null
	if screen == null:
		return false
	if screen.has_method("widget_snapshot"):
		return bool(screen.widget_snapshot().get("on", false))
	return bool(screen.enabled) if "enabled" in screen else false

func _autonav_active() -> bool:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null or not suit_os.has_method("get_screen"):
		return false
	var screen = suit_os.get_screen("player:autonav")
	return screen != null and screen.has_method("is_nav_assist_held") and bool(screen.is_nav_assist_held())
