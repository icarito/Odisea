extends GdUnitTestSuite

# FD-051: cubre la capa lógica del FireSystem, el traje y los props destructibles.
# La capa visual (FireVisualBand, HeatVignette) queda fuera a propósito: es downstream y
# no determinista por diseño.

const FireSystemScript = preload("res://core_v2/systems/fire/FireSystem.gd")
const SuitScript = preload("res://core_v2/player/components/SuitThermalResistance.gd")
const DestructibleScript = preload("res://core_v2/systems/fire/FireDestructible.gd")

const STEP := 1.0 / 60.0

class DummyBody extends Spatial:
	func _init() -> void:
		add_to_group("fire_vulnerable")

func _make_system(auto_start: bool = true) -> Node:
	var system = auto_free(FireSystemScript.new())
	system.auto_start = auto_start
	system.debug_draw = false
	add_child(system)
	return system

func _step_system(system: Node, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		system._physics_process(STEP)

# --- 1. Subida determinista ---

func test_fire_height_rise_is_deterministic() -> void:
	var run_a := []
	var run_b := []
	for run in [run_a, run_b]:
		var system = _make_system()
		system.base_speed = 0.5
		system.reset()
		for _i in range(120):
			system._physics_process(STEP)
			run.append(system.fire_height)
		remove_child(system)

	assert_int(run_a.size()).is_equal(run_b.size())
	for i in range(run_a.size()):
		assert_float(run_a[i]).is_equal_approx(run_b[i], 0.0000001)

func test_snapshot_roundtrip_restores_exact_state() -> void:
	var system = _make_system()
	system.base_speed = 0.4
	system.accel = 0.05
	_step_system(system, 2.0)

	var snapshot: Dictionary = system.get_snapshot()
	var height_at_snapshot: float = system.fire_height

	_step_system(system, 3.0)
	assert_float(system.fire_height).is_greater(height_at_snapshot)

	system.restore_snapshot(snapshot)
	assert_float(system.fire_height).is_equal_approx(height_at_snapshot, 0.0000001)
	assert_float(system.elapsed).is_equal_approx(float(snapshot["elapsed"]), 0.0000001)

func test_max_height_clamps_the_rise() -> void:
	var system = _make_system()
	system.base_speed = 5.0
	system.max_height = 3.0
	system.reset()
	_step_system(system, 5.0)
	assert_float(system.fire_height).is_equal_approx(3.0, 0.0001)

func test_respawn_safety_clamps_fire_below_checkpoint() -> void:
	var system = _make_system(false)
	system.heat_band = 2.0
	system.fire_contact_margin = 0.5
	system.respawn_safety_margin = 3.0
	system.fire_height = 20.0

	# El jugador murió y reaparece en Y=10: el fuego no puede quedar a menos de
	# 3 (margen) + 2 (heat_band) + 0.5 (contact_margin) = 5.5m bajo ese punto.
	system.ensure_safe_for_respawn(10.0)
	assert_float(system.fire_height).is_equal_approx(4.5, 0.0001)
	assert_float(system.get_heat_ceiling()).is_less_equal(10.0)

func test_respawn_safety_never_pushes_fire_upward() -> void:
	var system = _make_system(false)
	system.respawn_safety_margin = 3.0
	system.heat_band = 2.0
	system.fire_contact_margin = 0.5
	system.fire_height = 1.0

	# Si el fuego ya estaba bien por debajo del respawn, no se le regala altura extra.
	system.ensure_safe_for_respawn(50.0)
	assert_float(system.fire_height).is_equal_approx(1.0, 0.0001)

func test_stopped_system_does_not_rise() -> void:
	var system = _make_system(false)
	system.base_speed = 1.0
	system.reset()
	_step_system(system, 2.0)
	assert_float(system.fire_height).is_equal_approx(0.0, 0.0000001)

# --- 2 y 5. Umbrales de contacto: la zona de calor coincide con el debug ---

func test_heat_contact_only_below_ceiling() -> void:
	var system = _make_system(false)
	system.heat_band = 2.0
	system.fire_contact_margin = 0.5
	system.fire_height = 10.0

	var body = auto_free(DummyBody.new())
	add_child(body)

	# get_heat_ceiling() es exactamente la Y del gizmo naranja de debug.
	assert_float(system.get_heat_ceiling()).is_equal_approx(12.5, 0.0001)

	var contacts := []
	system.connect("heat_contact", self, "_collect_contact", [contacts])

	_place(body, 13.0)
	system._scan_vulnerable_bodies(STEP)
	assert_int(contacts.size()).is_equal(0)

	_place(body, 12.0)
	system._scan_vulnerable_bodies(STEP)
	assert_int(contacts.size()).is_equal(1)
	assert_bool(contacts[0]["in_core"]).is_false()
	assert_float(contacts[0]["dps"]).is_equal_approx(system.damage_per_second, 0.0001)

# --- 4. Núcleo letal: multiplicador, no one-shot ---

func test_core_applies_multiplier_not_instant_death() -> void:
	var system = _make_system(false)
	system.fire_height = 10.0
	system.damage_per_second = 25.0
	system.core_damage_multiplier = 4.0

	var body = auto_free(DummyBody.new())
	add_child(body)
	_place(body, 9.0)

	var contacts := []
	system.connect("heat_contact", self, "_collect_contact", [contacts])
	system._scan_vulnerable_bodies(STEP)

	assert_int(contacts.size()).is_equal(1)
	assert_bool(contacts[0]["in_core"]).is_true()
	assert_float(contacts[0]["dps"]).is_equal_approx(100.0, 0.0001)

# --- 2. Ventana del traje: no muere hasta integrity == 0 ---

func test_suit_absorbs_until_breach_and_emits_once() -> void:
	var suit = auto_free(SuitScript.new())
	suit.max_integrity = 100.0
	suit.regen_per_second = 0.0
	add_child(suit)

	var breaches := [0]
	suit.connect("suit_breached", self, "_count_breach", [breaches])

	# 25 dps durante 2s = 50 de daño: sobrevive con la mitad del traje.
	for _i in range(120):
		suit.apply_heat(25.0)
		suit._physics_process(STEP)

	assert_float(suit.integrity).is_equal_approx(50.0, 0.5)
	assert_bool(suit.is_breached).is_false()
	assert_int(breaches[0]).is_equal(0)

	# Otros 2s agotan el traje y disparan la muerte exactamente una vez.
	for _i in range(240):
		suit.apply_heat(25.0)
		suit._physics_process(STEP)

	assert_float(suit.integrity).is_equal_approx(0.0, 0.0001)
	assert_bool(suit.is_breached).is_true()
	assert_int(breaches[0]).is_equal(1)

# --- 3. Regeneración: rozar el fuego es recuperable ---

func test_suit_regenerates_after_delay() -> void:
	var suit = auto_free(SuitScript.new())
	suit.max_integrity = 100.0
	suit.regen_per_second = 10.0
	suit.regen_delay = 1.0
	add_child(suit)

	for _i in range(60):
		suit.apply_heat(25.0)
		suit._physics_process(STEP)
	var after_heat: float = suit.integrity
	assert_float(after_heat).is_less(100.0)

	# Durante el retardo no regenera.
	for _i in range(30):
		suit._physics_process(STEP)
	assert_float(suit.integrity).is_equal_approx(after_heat, 0.0001)

	# Pasado el retardo, sube.
	for _i in range(120):
		suit._physics_process(STEP)
	assert_float(suit.integrity).is_greater(after_heat)

func test_suit_ratio_tracks_integrity() -> void:
	var suit = auto_free(SuitScript.new())
	suit.max_integrity = 200.0
	suit.regen_per_second = 0.0
	add_child(suit)
	assert_float(suit.get_ratio()).is_equal_approx(1.0, 0.0001)

	suit.integrity = 50.0
	assert_float(suit.get_ratio()).is_equal_approx(0.25, 0.0001)

func test_suit_snapshot_roundtrip() -> void:
	var suit = auto_free(SuitScript.new())
	suit.regen_per_second = 0.0
	add_child(suit)

	for _i in range(60):
		suit.apply_heat(30.0)
		suit._physics_process(STEP)

	var snapshot: Dictionary = suit.get_snapshot()
	var integrity_at_snapshot: float = suit.integrity

	for _i in range(60):
		suit.apply_heat(30.0)
		suit._physics_process(STEP)
	assert_float(suit.integrity).is_less(integrity_at_snapshot)

	suit.restore_snapshot(snapshot)
	assert_float(suit.integrity).is_equal_approx(integrity_at_snapshot, 0.0000001)

# --- 6. Melt de props ---

func test_destructible_melts_after_delay_and_drops_collision() -> void:
	var system = _make_system(false)
	system.fire_height = 0.0

	var host = auto_free(Spatial.new())
	add_child(host)
	_place(host, 5.0)
	var shape := CollisionShape.new()
	shape.shape = BoxShape.new()
	host.add_child(shape)

	var destructible = DestructibleScript.new()
	destructible.melt_delay = 1.0
	destructible.hide_on_melt = true
	host.add_child(destructible)
	destructible._connect_fire_system()

	# El fuego aún no llega: no se derrite.
	destructible._physics_process(STEP)
	assert_bool(destructible.is_melting).is_false()
	assert_bool(shape.disabled).is_false()

	# El fuego cruza su Y: arranca el derretimiento, pero hay gracia visible.
	system.fire_height = 5.5
	destructible._physics_process(STEP)
	assert_bool(destructible.is_melting).is_true()
	assert_bool(destructible.is_melted).is_false()
	assert_bool(shape.disabled).is_false()

	# Agotada la gracia, colapsa.
	for _i in range(70):
		destructible._physics_process(STEP)
	assert_bool(destructible.is_melted).is_true()
	assert_bool(shape.disabled).is_true()
	assert_bool(host.visible).is_false()

func test_destructible_snapshot_roundtrip() -> void:
	var system = _make_system(false)
	system.fire_height = 100.0

	var host = auto_free(Spatial.new())
	add_child(host)
	_place(host, 1.0)
	var destructible = DestructibleScript.new()
	destructible.melt_delay = 1.0
	host.add_child(destructible)
	destructible._connect_fire_system()

	destructible._physics_process(STEP)
	var snapshot: Dictionary = destructible.get_snapshot()
	assert_bool(bool(snapshot["is_melting"])).is_true()
	assert_bool(bool(snapshot["is_melted"])).is_false()

	for _i in range(120):
		destructible._physics_process(STEP)
	assert_bool(destructible.is_melted).is_true()

	destructible.restore_snapshot(snapshot)
	assert_bool(destructible.is_melted).is_false()
	assert_bool(destructible.is_melting).is_true()

# --- helpers ---

func _place(node: Spatial, y: float) -> void:
	var t := node.global_transform
	t.origin = Vector3(0.0, y, 0.0)
	node.global_transform = t

func _collect_contact(body: Node, dps: float, in_core: bool, sink: Array) -> void:
	sink.append({"body": body, "dps": dps, "in_core": in_core})

func _count_breach(sink: Array) -> void:
	sink[0] += 1
