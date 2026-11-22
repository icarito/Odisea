extends Node

# FD-324 F7 — cableado F5 (encendido/conversión) y F6 (carrera/cámara/sombra/LOD).
# Helper separado para que ArkRunSlice.gd quede por debajo de 200 líneas.
# Presentación + propagación de a_axial; no duplica física ni cámaras.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const IgnitionScript = preload("res://core_v2/levels/ark_run/ArkRunEngineIgnition.gd")
const ConversionScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceConversion.gd")
const RaceScript = preload("res://core_v2/levels/ark_run/ArkRunRaceController.gd")
const CylinderScript = preload("res://core_v2/camera/ArkRunCylindricalCamera.gd")
const ShadowScript = preload("res://core_v2/levels/ark_run/ArkRunGravityShadow.gd")
const LodScript = preload("res://core_v2/levels/ark_run/ArkRunLodTronPass.gd")
const ScenarioScript = preload("res://core_v2/levels/ark_run/ArkRunVerticalSliceScenario.gd")
const SLICE_SEED := 32401
const PROXY_PLATES := 4

var slice = null
var ignition = null
var conversion = null
var race = null
var cylindrical = null
var shadow = null
var lod = null
var _restart_key_held := false
var _determinism_state: Dictionary = {}

func setup(owner_slice) -> void:
	slice = owner_slice
	process_priority = 120
	_build_f5()
	_build_f6()

func _build_f5() -> void:
	var root: Node = slice.get_node("EngineIgnitionRoot")
	ignition = slice._attach(root, "ArkRunEngineIgnition", IgnitionScript)
	ignition.seed_value = SLICE_SEED
	ignition.set_industry_streamer(slice.industry_streamer)
	for spoke in slice.spokes:
		ignition.add_elevator(spoke.get_elevator())
	conversion = slice._attach(root, "ArkRunTerraceConversion", ConversionScript)
	conversion.omega = slice.spin_omega
	conversion.set_ignition(ignition)
	ignition.connect("ignition_triggered", self, "_on_ignition_triggered")
	conversion.add_spiral_plates(slice, slice.pilot.global_transform.origin, PROXY_PLATES)

func _on_ignition_triggered(_time_since_arm) -> void:
	conversion.start_conversion()
	if race != null and not race.running:
		race.start_run()

func _build_f6() -> void:
	var hud: Node = slice.get_node("RaceHudRoot")
	race = slice._attach(hud, "ArkRunRaceController", RaceScript)
	race.engine_z_max = slice.get_engine_z_max()
	cylindrical = slice._attach(hud, "ArkRunCylindricalCamera", CylinderScript)
	shadow = slice._attach(slice.get_node("TraversalRoot"), "ArkRunGravityShadow", ShadowScript)
	lod = slice._attach(slice.get_node("TraversalRoot"), "ArkRunLodTronPass", LodScript)
	lod.build_static()
	var world_env = slice.get_node_or_null("WorldEnvironment")
	if world_env != null and lod.get_environment() != null:
		world_env.environment = lod.get_environment()
	var points := []
	for waypoint in slice.get_canonical_route().get_waypoints():
		points.append(waypoint["position"] as Vector3)
	lod.add_emissive_polyline(points, LodScript.TRON_COLOR)

func _physics_process(delta: float) -> void:
	if slice == null or not is_instance_valid(slice) or not slice.is_physics_processing():
		return
	present(delta)

func present(dt: float) -> void:
	var pilot = slice.pilot
	if pilot == null or not is_instance_valid(pilot) or not pilot.is_spin_real_active():
		if pilot != null and is_instance_valid(pilot) and slice.spin_predictor != null \
				and is_instance_valid(slice.spin_predictor):
			slice.spin_predictor.visible = false
		return
	var pos: Vector3 = pilot.global_transform.origin
	var r_local: float = slice.r_local_for_position(pos)
	if slice.spin_camera != null and is_instance_valid(slice.spin_camera):
		slice.spin_camera.apply_to_pilot(pilot, r_local, dt)
	var a_axial: float = ignition.get_axial_accel() if ignition != null else 0.0
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if physics != null:
		physics.a_axial = a_axial
	_update_predictor(dt, pilot, pos, r_local, a_axial)
	_update_presentation(dt, pilot, pos, r_local, a_axial)

func _update_predictor(dt, pilot, pos: Vector3, r_local: float, a_axial: float) -> void:
	if slice.spin_predictor == null or not is_instance_valid(slice.spin_predictor):
		return
	# Performance F0/F6: en el idle ZERO_G del hub no se simula el preview.
	if slice.explosion != null and not slice.explosion.should_show_predictor_at(pos):
		slice.spin_predictor.visible = false
		return
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	var airborne: bool = not bool(physics._was_grounded) if physics != null else not pilot.is_on_floor()
	slice.spin_predictor.update_preview(
		pos, pilot.velocity, slice.spin_omega, r_local, airborne, dt, 1800, a_axial
	)

func _update_presentation(dt, pilot, pos: Vector3, r_local: float, a_axial: float) -> void:
	if cylindrical != null:
		var progress := 0.0
		if slice.explosion != null and slice.explosion.launched:
			progress = clamp(pos.z / max(slice.get_bridge_target().z, 1.0), 0.0, 1.0)
		var state: Dictionary = cylindrical.step_camera(pos, _up_of(pilot, pos), r_local, dt, progress)
		var rig: Spatial = pilot.get_node_or_null("CameraRig") as Spatial
		if rig != null:
			cylindrical.apply_to_rig(rig, state)
	if shadow != null:
		shadow.update_shadow(pos, slice.spin_omega, a_axial)
	if lod != null:
		lod.update_lod_for_position(pos)
	_update_race(dt, pilot)
	_poll_restart()

func _up_of(pilot, pos: Vector3) -> Vector3:
	if pilot.has_method("get_sim_up"):
		return pilot.get_sim_up()
	return SpinFrame.up(pos, Vector3.UP)

func _update_race(dt: float, pilot) -> void:
	if race == null:
		return
	if not race.running and not race.finished and slice.explosion != null and slice.explosion.launched:
		race.start_run()
	if race.running:
		race.tick(dt, pilot.global_transform.origin, pilot.global_transform.basis)
	if race.has_ghost_trace():
		race.update_ghost_visual(race.t_run)

func _poll_restart() -> void:
	var held: bool = Input.is_key_pressed(KEY_R)
	if held and not _restart_key_held:
		restart_run()
	_restart_key_held = held

# Reinicio instantáneo (1 botón: R) sin recargar la escena; conserva fantasma.
func restart_run() -> void:
	if slice.pilot != null:
		slice.spawn_at_hub_start()
	if slice.explosion != null and slice.explosion.has_method("reset"):
		slice.explosion.reset()
	if ignition != null:
		ignition.reset()
	if conversion != null:
		conversion.reset()
	if race != null:
		race.restart_run()

func run_determinism_scenario() -> Dictionary:
	_determinism_state = ScenarioScript.new().run(slice, self)
	return _determinism_state
