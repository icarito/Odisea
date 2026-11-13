extends GdUnitTestSuite

# Test focalizado de T5 (FD-289 §7.6): FusibleV2.
# No toca niveles reales: verifica contrato, verbo extraer/insertar, socket y snapshot.

const FusibleScene := preload("res://core_v2/props/controls/FusibleV2.tscn")
const STEP := 1.0 / 60.0


func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self


func _spawn_fusible() -> Node:
	var prop: Node = auto_free(FusibleScene.instance())
	_scene_host().add_child(prop)
	return prop


# Corre N pasos de física a mano, sin ceder el frame: el motor no intercala _physics_process,
# así que el avance del hold es exactamente el que pide el test.
func _run_steps(prop: Node, steps: int) -> void:
	for _i in range(steps):
		prop.step(STEP)


# Avanza hasta que la acción del hold cambia is_active (extraer o insertar). No depende del
# conteo exacto de pasos: el toggle puede caer uno antes o uno después según el redondeo.
func _run_until_toggle(prop: Node, max_steps: int) -> void:
	var before: bool = prop.is_active
	for _i in range(max_steps):
		prop.step(STEP)
		if prop.is_active != before:
			return


func test_fusible_contract_and_initial_installed_state() -> void:
	var prop = _spawn_fusible()
	yield(get_tree(), "idle_frame")

	assert_bool(prop.has_method("set_held")).is_true()
	assert_bool(prop.has_signal("hold_completed")).is_true() # heredada de HoldInteractableV2
	assert_bool(prop.has_method("get_snapshot")).is_true()
	assert_bool(prop.has_method("restore_snapshot")).is_true()
	assert_bool(prop.is_in_group("replay_sync")).is_true()

	# El fusible arranca insertado (starts_active = true) y con los verbos del vocabulario.
	assert_bool(prop.is_active).is_true()
	assert_str(prop.interaction_verb_active).is_equal("Extraer")
	assert_str(prop.interaction_verb_inactive).is_equal("Insertar")
	assert_bool(prop.has_signal("fuse_extracted")).is_true()
	assert_bool(prop.has_signal("fuse_inserted")).is_true()


func test_hold_extracts_then_hold_inserts_fuse() -> void:
	var prop = _spawn_fusible()
	yield(get_tree(), "idle_frame")
	prop.hold_duration = 0.25

	var fuse: Spatial = prop.get_node("Fuse")
	var rest: Vector3 = fuse.translation
	var extracted := [0]
	var inserted := [0]
	prop.connect("fuse_extracted", self, "_bump", [extracted])
	prop.connect("fuse_inserted", self, "_bump", [inserted])

	# Extraer: sostener hasta completar y luego drenar el progreso restante.
	prop.set_held(true)
	_run_until_toggle(prop, 60)
	prop.set_held(false)
	_run_steps(prop, 70)
	assert_bool(prop.is_active).is_false()
	assert_int(extracted[0]).is_equal(1)
	assert_int(inserted[0]).is_equal(0)
	assert_float(fuse.translation.distance_to(rest + prop.extract_offset)).is_less(0.001)

	# Insertar: sostener de nuevo hasta completar y drenar.
	prop.set_held(true)
	_run_until_toggle(prop, 60)
	prop.set_held(false)
	_run_steps(prop, 70)
	assert_bool(prop.is_active).is_true()
	assert_int(inserted[0]).is_equal(1)
	assert_int(extracted[0]).is_equal(1)
	assert_float(fuse.translation.distance_to(rest)).is_less(0.001)


func test_partial_hold_releases_and_keeps_fuse_installed() -> void:
	var prop = _spawn_fusible()
	yield(get_tree(), "idle_frame")
	prop.hold_duration = 0.5
	var fuse: Spatial = prop.get_node("Fuse")
	var rest: Vector3 = fuse.translation

	# Sostener poco (menos de la duración) y soltar: el fusible vuelve al socket.
	prop.set_held(true)
	_run_steps(prop, 10) # 10/60 ≈ 0.166s de 0.5s
	assert_bool(prop.is_active).is_true()
	assert_float(fuse.translation.distance_to(rest)).is_greater(0.0)

	prop.set_held(false)
	_run_steps(prop, 70)
	assert_bool(prop.is_active).is_true()
	assert_float(fuse.translation.distance_to(rest)).is_less(0.001)


func test_snapshot_roundtrip_preserves_extracted_state() -> void:
	var prop = _spawn_fusible()
	yield(get_tree(), "idle_frame")
	prop.hold_duration = 0.25

	prop.set_held(true)
	_run_steps(prop, 20)
	prop.set_held(false)
	assert_bool(prop.is_active).is_false()
	var extracted_pos: Vector3 = prop.get_node("Fuse").translation

	var snap: Dictionary = prop.get_snapshot()
	assert_bool(snap.has("fuse_installed")).is_true()
	assert_bool(snap["fuse_installed"]).is_false()
	assert_bool(snap.has("network_id")).is_true()

	var restored = _spawn_fusible()
	yield(get_tree(), "idle_frame")
	restored.restore_snapshot(snap)

	assert_bool(restored.is_active).is_false()
	var restored_fuse: Spatial = restored.get_node("Fuse")
	assert_float(restored_fuse.translation.distance_to(extracted_pos)).is_less(0.001)
	assert_bool(bool(restored.get_snapshot()["fuse_installed"])).is_false()


func _bump(sink: Array) -> void:
	sink[0] += 1
