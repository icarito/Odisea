extends Reference

# FD-324 F7 — recorrido determinista integrado del vertical slice.
# Lo invoca `test_ark_run_vertical_slice.oys` (CALL ArkRunWiring) sobre instancias
# frescas de ArkRunSlice.tscn; el test GdUnit corre el .oys dos veces y compara el
# hash contra `ark_run_vertical_slice.hash`. Sin randf()/randomize() ni reloj.
# Cubre: hub ZERO_G + explosión/aterrizaje, cuerda de domo, ascensor radial,
# autonavegación + margen humano ≥25%, encendido z=0 + conversión 3 s + colapso
# cinemático, y meta + reinicio + fantasma.

const ExplosionScript = preload("res://core_v2/levels/ark_run/ArkRunExplosion.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const DT := 1.0 / 60.0
const FLIGHT_STEPS := 120
const CONVERSION_STEPS := 180
const RACE_REFERENCE_SEC := 3.0
const RESTART_Z := -950.0

func run(slice, wiring) -> Dictionary:
	var input := InputDataV2.new()
	var state: Dictionary = {}

	# 1) Hub ZERO_G → explosión al Puente → aterrizaje grande.
	slice.spawn_at_hub_start()
	state["hub_position"] = slice.pilot.global_transform.origin
	var launch: Dictionary = slice.explosion.detonate()
	state["launch_velocity"] = launch.get("velocity", Vector3.ZERO)
	for _i in range(FLIGHT_STEPS):
		slice.pilot.step(DT, input)
	state["flight_position"] = slice.pilot.global_transform.origin
	state["flight_velocity"] = slice.pilot.velocity
	var physics = slice.pilot.get_spin_physics() if slice.pilot.has_method("get_spin_physics") else null
	var up: Vector3 = slice.pilot.get_sim_up()
	var landing: Dictionary = ExplosionScript.resolve_bridge_landing(
		physics, slice.pilot, -up * 25.0, up
	)
	state["landing_speed"] = float(landing.get("applied_speed", 0.0))
	state["landing_kind"] = int(landing.get("landing", 0))

	# 2) Cuerda con anclaje de domo (DomeSpiralField/DomeRegistry).
	var anchors: Array = slice.collect_rope_anchors()
	state["anchor_count"] = anchors.size()
	var anchor: Transform = anchors[0] if not anchors.empty() else Transform(Basis.IDENTITY, Vector3(0.0, 0.0, 8.0))
	slice.pilot.global_transform.origin = anchor.origin + Vector3(0.0, 0.0, 8.0)
	slice.pilot.velocity = Vector3.ZERO
	var aim: Vector3 = (anchor.origin - slice.pilot.global_transform.origin).normalized()
	var rope_step: Dictionary = slice.rope_input.step(slice.pilot, anchors, aim, true, DT)
	state["rope_attached"] = bool(rope_step.get("attached", false))
	state["rope_length"] = float(rope_step.get("length", 0.0))
	slice.rope_input.step(slice.pilot, anchors, aim, false, DT)

	# 3) Ascensor radial determinista (6 m/s, 3 s en extremos).
	var elevator = slice.spokes[0].get_elevator()
	var ride: Dictionary = elevator.step_elevator(1.5)
	state["elevator_radius"] = float(ride.get("surface_radius", elevator.get_surface_radius()))
	state["elevator_phase"] = String(ride.get("phase", elevator.get_phase()))
	state["elevator_operational"] = bool(elevator.is_operational())

	# 4) Autonavegación al destino activo + margen humano ≥ 25%.
	var host = slice.get_node_or_null("RaceHudRoot/ArkRunSuitOSHost")
	var suit_os = slice.get_node_or_null("/root/SuitOS")
	var nav = suit_os.get_screen("ship:ark_nav") if suit_os != null else null
	if host != null and nav != null:
		host._sync_route(nav, slice)
		nav.set_destination("engine")
		host._sync_route(nav, slice)
		state["nav_destination"] = String(nav.get_destination_id())
		state["nav_route_size"] = nav.get_route().size()
	else:
		state["nav_destination"] = ""
		state["nav_route_size"] = 0
	var race = wiring.race
	race.set_reference_time(RACE_REFERENCE_SEC)
	race.start_run()
	for _i in range(120):
		race.tick(DT, Vector3(240.0, 0.0, 0.0), Basis.IDENTITY)
	race.tick(DT, Vector3(240.0, 0.0, RESTART_Z), Basis.IDENTITY)
	state["margin_pct"] = race.margin_pct
	state["margin_ok"] = race.meets_margin()
	state["ghost_samples_best"] = race.ghost_sample_count()

	# 5) Encendido al cruzar z=0 de regreso + conversión 3 s + colapso #9.
	var ignition = wiring.ignition
	var conversion = wiring.conversion
	ignition.reset()
	conversion.reset()
	conversion.start_conversion()
	ignition.advance(DT, 620.0)
	ignition.advance(DT, 100.0)
	ignition.advance(DT, 1.0)
	ignition.advance(DT, -1.0)
	ignition.advance(3.0, -1.0)
	for _i in range(CONVERSION_STEPS):
		conversion.advance(DT)
	var failures: Dictionary = ignition.get_failure_summary()
	state["ignition_state"] = ignition.get_ignition_state()
	state["a_axial"] = ignition.get_axial_accel()
	state["conversion_elapsed"] = conversion.get_elapsed()
	state["failure_hash"] = int(failures.get("hash", 0))
	state["failures"] = int(failures.get("failed", 0))
	state["collapses"] = ignition.get_collapse_keys().size()

	# 6) Meta, reinicio instantáneo y fantasma.
	var runs_before: int = race._run_count
	wiring.restart_run()
	state["restart_runs"] = race._run_count - runs_before
	state["restart_ignition"] = ignition.get_state_name()
	state["restart_position"] = slice.pilot.global_transform.origin
	state["ghost_samples_after_restart"] = race.ghost_sample_count()
	state["gravity_mode"] = _gravity_mode()
	return state

func _gravity_mode() -> int:
	var world = Engine.get_main_loop().root.get_node_or_null("GravityWorld")
	return int(world.get_current_gravity_mode()) if world != null else -1
