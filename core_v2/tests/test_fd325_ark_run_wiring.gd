extends GdUnitTestSuite

# FD-325 T5 — cableado end-to-end del Ark Run.
# Sobre una instancia REAL de ArkRunSlice.tscn: dispositivo activo del proveedor →
# touch toggle de la cuerda + salto, snapshot del HUD superior (ghost/gravedad/chips),
# presentador diegético (jet + retículo + FOV aditivo) y contrato de slots L1/R1.

const SliceScene = preload("res://core_v2/levels/ark_run/ArkRunSlice.tscn")
const PresenterScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticPresenter.gd")
const ProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const DT := 1.0 / 60.0

func _instantiate_slice():
	var slice = auto_free(SliceScene.instance())
	add_child(slice)
	slice.set_physics_process(false)
	if slice.pilot != null:
		slice.pilot.set_physics_process(false)
	return slice

func _provider(slice):
	if slice.pilot != null and slice.pilot.has_method("ensure_input_provider"):
		slice.pilot.ensure_input_provider()
	return slice.pilot.get("input_provider") if slice.pilot != null else null

func test_touch_device_enables_rope_toggle_and_jump_releases() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	var provider = _provider(slice)
	if provider == null:
		return # sin proveedor en headless: nada que cablear
	var saved := String(provider.get_active_input_device())
	provider.add_touch_camera_drag(Vector2(4.0, 0.0))
	wiring.loop._poll_device_and_touch(slice.pilot)
	assert_str(String(wiring.loop._device)).is_equal("touch")
	assert_bool(slice.rope_input.touch_toggle_mode).is_true()

	# Tap 2 (toggle) engancha en headless sin anclaje; sólo verificamos el contrato de modo
	# y que un salto no rompe (release sin velocidad escrita).
	var state: Dictionary = slice.rope_input.step(slice.pilot, [], Vector3.FORWARD, true, DT,
		false, false, false, true)
	assert_bool(state.has("attached")).is_true()
	provider.last_input_device = saved
	wiring.loop._poll_device_and_touch(slice.pilot)
	assert_bool(slice.rope_input.touch_toggle_mode).is_equal(false)

func test_hud_data_includes_ghost_gravity_and_quick_slots() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	# Sin traza de fantasma: la clave ghost_z NO viaja (barra sin fantasma).
	assert_bool(wiring.race.has_ghost_trace()).is_false()
	var data: Dictionary = wiring.loop._hud_data()
	assert_bool(data.has("ghost_z")).is_false()
	assert_bool(data.has("a_axial")).is_true()
	assert_bool(data.has("flashlight_on")).is_true()
	assert_bool(data.has("autonav_active")).is_true()
	assert_bool(bool(data["flashlight_on"])).is_false()
	assert_bool(bool(data["autonav_active"])).is_false()

	# Con una corrida grabada, el fantasma aporta su z normalizado en [-1, 1].
	wiring.race.start_run()
	wiring.race.tick(DT, Vector3(240.0, 0.0, 0.0))
	wiring.race.finish_run()
	var with_ghost: Dictionary = wiring.loop._hud_data()
	assert_bool(with_ghost.has("ghost_z")).is_true()
	assert_float(float(with_ghost["ghost_z"])).is_between(-1.0, 1.0)

func test_presenter_mounts_one_jet_and_one_tether_with_fov_offset() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	var presenter = wiring.loop._presenter
	assert_object(presenter).is_not_null()
	# Un solo jet y un solo tether bajo el presentador (sin doble visual con la pluma/marcador
	# viejos que dibujaba ArkRunControlsFeedback).
	assert_object(presenter.jet).is_not_null()
	assert_object(presenter.rope).is_not_null()
	assert_int(presenter.get_child_count()).is_equal(3) # jet + rope + overlay 2D
	assert_int(presenter.jet.get_child_count()).is_equal(2) # dos boquillas, un jet
	assert_object(slice.find_node("ThrusterPlume", true, false)).is_null()
	assert_object(slice.find_node("RopeAnchorMarker", true, false)).is_null()
	assert_object(slice.find_node("RopeTether", true, false)).is_null()
	# Crosshair central propio del presentador (cruz cortada), no un nodo nuevo en el rope.
	var overlay = presenter.get_node("DiegeticOverlay")
	assert_object(overlay.get_node_or_null("Crosshair")).is_not_null()

	# FOV de catapulta: offset aditivo sobre el rig existente (pilot.base_fov), acotado.
	var fov_before: float = float(presenter._fov_offset)
	assert_float(fov_before).is_equal_approx(0.0, 1e-6)
	var clean_fov: float = float(slice.pilot.base_fov)
	presenter._apply_fov(slice.pilot, 5.0)
	assert_float(float(presenter._fov_offset)).is_equal_approx(5.0, 1e-6)
	assert_float(float(slice.pilot.base_fov)).is_equal_approx(clean_fov + 5.0, 1e-4)
	presenter.reset_fov()
	assert_float(float(presenter._fov_offset)).is_equal_approx(0.0, 1e-6)
	assert_float(float(slice.pilot.base_fov)).is_equal_approx(clean_fov, 1e-4)

func test_live_loop_presents_jet_reticle_and_catapult_fov() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	var presenter = wiring.loop._presenter
	var cam := Camera.new()
	add_child(cam)
	cam.global_transform = Transform(Basis.IDENTITY, Vector3(-6.0, 1.0, 2.0))
	# Estado de un tick propulsando: jet visible por -thrust_dir, camión real para proyectar.
	var tick := {"thrusting": true, "thrust_dir": Vector3(0.0, 0.0, -1.0), "reeling": true,
		"attached": false, "device": "gamepad"}
	var pos: Vector3 = slice.pilot.global_transform.origin
	var clean_fov: float = float(slice.pilot.base_fov)
	presenter.present(DT, tick, pos)
	assert_bool(presenter.jet.is_jet_visible()).is_true()
	# FOV de catapulta como offset aditivo (retención) acotado a [0, 5] sobre base_fov.
	assert_float(float(presenter._fov_offset)).is_between(0.0, 5.0 + 1e-6)
	assert_float(float(slice.pilot.base_fov)).is_equal_approx(
		clean_fov + float(presenter._fov_offset), 1e-4)
	# Salir del empuje: el jet se apaga y el FOV vuelve a su base limpia.
	presenter.present(DT, {"thrusting": false, "reeling": false, "device": "keyboard"}, pos)
	assert_bool(presenter.jet.is_jet_visible()).is_false()
	presenter.reset_fov()
	assert_float(float(slice.pilot.base_fov)).is_equal_approx(clean_fov, 1e-4)
	remove_child(cam)
	cam.free()

func test_quick_slots_l1_r1_published_and_triggers_free() -> void:
	# Contrato FD-325: con gatillos reservados, L1/R1 son los únicos slots de gameplay.
	assert_array(ProviderScript.HUD_TRIGGER_SLOTS).is_equal([2, 4])
	assert_int(int(SuitOS.ARK_RUN_AUTONAV_SLOT)).is_equal(2)
	assert_str(SuitOS.slot_label_for_screen("player:flashlight")).is_equal("L1")

# FD-325 polish (playtest): el tick real del loop debe enganchar la cuerda con
# `rope_grapple`. El `_physics_process` del rope input está apagado y antes del fix
# `ArkRunControlsFeedback.tick` no llamaba a `rope_input.step`: la cuerda nunca enganchaba.
func test_rope_grapple_attaches_and_thruster_reels_through_live_loop() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	# Aim forzado a la mirada del pilot (sin cámara de testport) y anclaje exacto sobre ese
	# rayo: el punto bajo prueba es que el loop llame a step() y enganche, no la geometría.
	var origin: Vector3 = slice.pilot.global_transform.origin
	var aim: Vector3 = -slice.pilot.global_transform.basis.z.normalized()
	var anchor: Vector3 = origin + aim * 20.0
	wiring.anchors = [anchor]
	slice.rope_input.set_anchors(wiring.anchors)
	wiring.feedback.loop = null # fuerza fallback al forward del pilot en aim_dir()
	assert_bool(slice.rope_input.is_attached()).is_false()
	var _sp = get_tree().root.get_world().direct_space_state
	var _hit: Dictionary = _sp.intersect_ray(origin, anchor, [slice.pilot], 0x7FFFFFFF, true, false)

	# Tick de gameplay con la cuerda sostenida: queda enganchada sin llamar a step a mano.
	Input.action_press("rope_grapple")
	wiring.loop.advance_play_loop(DT)
	assert_bool(slice.rope_input.is_attached()).is_true()
	assert_str(wiring.feedback.rope_state).is_equal("ATTACHED")

	# Con la cuerda enganchada, `thruster_boost` retrae (la cuerda se acorta).
	var length_before: float = float(slice.rope_input.get_rope().get_rope_length())
	Input.action_press("thruster_boost")
	wiring.loop.advance_play_loop(DT)
	assert_bool(wiring.feedback.rope_reeling).is_true()
	assert_float(float(slice.rope_input.get_rope().get_rope_length())).is_less(length_before)

	# Soltar el gatillo suelta la cuerda (hold) sin romper el tick.
	Input.action_release("rope_grapple")
	Input.action_release("thruster_boost")
	wiring.loop.advance_play_loop(DT)
	assert_bool(slice.rope_input.is_attached()).is_false()

# FD-325 polish (playtest): al aterrizar en el Puente la fase y el marcador deben cambiar
# de inmediato a MOTOR. Antes `_hud_data` sólo miraba `pos.z < 0`, así que parado sobre la
# placa 48 seguía pidiendo "VUELA AL PUENTE (+Z)".
func test_bridge_arrival_switches_phase_and_target_to_engine() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	var loop = wiring.loop
	# Estado post-detonación sin correr la simulación completa.
	slice.explosion.launched = true
	loop._bridge_reached = false
	loop._detonation_timer = 3.0

	# La superficie caminable del Puente está SOBRE el centro de la placa (feet-level).
	var target: Vector3 = slice.get_bridge_target()
	var plate_origin: Vector3 = SpiralGeometry.plate_transform(
		slice.get_spiral_config(), int(slice.get_bridge_plate_indices()[1])).origin
	assert_float(target.distance_to(plate_origin)).is_equal_approx(1.5, 1e-3)

	# Aterrizado en la placa, todavía en +Z: el loop reconoce la llegada.
	slice.pilot.global_transform.origin = target
	loop.advance_play_loop(DT)
	assert_bool(loop._bridge_reached).is_true()
	var data: Dictionary = loop._hud_data()
	assert_str(String(data["phase"])).is_equal("BAJA AL MOTOR (-Z)")
	assert_str(String(data["target_label"])).is_equal("MOTOR")
	assert_float((data["target_pos"] as Vector3).distance_to(slice.get_engine_target())) \
		.is_less_equal(1e-3)
	# El destino del Motor también es superficie caminable (placa 0, -Z).
	assert_float(slice.get_engine_target().z).is_less(float(target.z))

	# `restart_run` limpia el flag y vuelve a pedir el Puente (fase de cuenta regresiva).
	loop.restart_run()
	assert_bool(loop._bridge_reached).is_false()

# FD-325 polish: línea de visión. Un obstáculo sólido entre el ojo y un anclaje lo
# descarta (has_line_of_sight=false); un anclaje sin nada delante sigue libre. Se fija el
# ojo en el pilot (loop=null) para no depender de la cámara de testport.
func test_rope_los_filter_rejects_obstructed_anchor() -> void:
	var slice = _instantiate_slice()
	var wiring = slice.get_node("ArkRunWiring")
	wiring.feedback.loop = null
	var pilot = slice.pilot
	var eye: Vector3 = wiring.feedback.camera_origin(pilot)
	var aim: Vector3 = wiring.feedback.aim_dir(pilot)
	var anchor_a: Vector3 = eye + aim * 30.0
	# Bloqueador sólido justo sobre el segmento ojo→A (caja de 2 m centrada a 10 m).
	var blocker := StaticBody.new()
	blocker.name = "LosBlocker"
	var shape := BoxShape.new()
	shape.extents = Vector3(1.0, 1.0, 1.0)
	var coll := CollisionShape.new()
	coll.shape = shape
	blocker.add_child(coll)
	blocker.global_transform = Transform(Basis.IDENTITY, eye + aim * 10.0)
	slice.add_child(blocker)
	yield (get_tree(), "physics_frame")
	yield (get_tree(), "physics_frame")

	var space = get_tree().root.get_world().direct_space_state
	assert_bool(wiring.feedback.has_line_of_sight(space, eye, anchor_a, pilot)).is_false()
	# Un anclaje desplazado de lado (+8 m) y sin nada delante sí tiene línea de visión.
	var side: Vector3 = aim.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var anchor_b: Vector3 = eye + aim * 30.0 + side * 8.0
	assert_bool(wiring.feedback.has_line_of_sight(space, eye, anchor_b, pilot)).is_true()
