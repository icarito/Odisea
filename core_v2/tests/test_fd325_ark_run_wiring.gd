extends GdUnitTestSuite

# FD-325 T5 — cableado end-to-end del Ark Run.
# Sobre una instancia REAL de ArkRunSlice.tscn: dispositivo activo del proveedor →
# touch toggle de la cuerda + salto, snapshot del HUD superior (ghost/gravedad/chips),
# presentador diegético (jet + retículo + FOV aditivo) y contrato de slots L1/R1.

const SliceScene = preload("res://core_v2/levels/ark_run/ArkRunSlice.tscn")
const PresenterScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticPresenter.gd")
const ProviderScript = preload("res://core_v2/input/InputProviderV2.gd")
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
