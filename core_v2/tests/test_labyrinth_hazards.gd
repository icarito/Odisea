extends GdUnitTestSuite

# Fase 2 del spike de secciones laberínticas + hazards (2026-11-13).
# Cubre:
#  - determinismo de la generación MST (misma seed → misma malla; seed distinta → cambia)
#  - determinismo de la instanciación de la sección (mismos hijos/transforms)
#  - alineación de la celda de entrada con el piso de la bahía
#  - presencia del fuego y del gas, y efecto del hazard
#  - el fuego es posicional (compuerta X/Z), no daña fuera del laberinto
#  - el ciclo de protocolo es determinista y alterna FIRE/GAS con ventanas seguras

const SectionScene := preload("res://core_v2/levels/machines/LabyrinthSection.tscn")
const MSTGeneratorScript := preload("res://core_v2/systems/ScaffoldMSTGenerator.gd")

const STEP := 1.0 / 60.0

const PHASE_SAFE := 0
const PHASE_WARNING_FIRE := 1
const PHASE_FIRE := 2
const PHASE_WARNING_GAS := 3
const PHASE_GAS := 4

class DummyBody extends Spatial:
	var damage_received := 0.0
	func take_damage(amount: float) -> void:
		damage_received += amount
	func _init() -> void:
		add_to_group("fire_vulnerable")

# ── helpers ──────────────────────────────────────────────────────────────────

func _make_section(opts: Dictionary = {}) -> Node:
	var section = auto_free(SectionScene.instance())
	section.enable_fire_visual = false
	section.enable_protocol_cycle = bool(opts.get("protocol", false))
	section.enable_fire_hazard = bool(opts.get("fire", true))
	section.enable_gas_hazard = bool(opts.get("gas", true))
	section.generation_seed = int(opts.get("seed", 20261113))
	add_child(section)
	return section

func _generate_mst(seed_val: int) -> Array:
	var gen = MSTGeneratorScript.new()
	gen.apply_params({
		"grid_width": 4,
		"grid_depth": 8,
		"cell_size": 3.0,
		"mst_max_height_steps": 3,
		"mst_min_height_steps": 1,
		"room_count": 6,
		"extra_cycles": 2,
		"fixed_border_tiles": {"0,2": {"id": "E", "rotation": 270, "height": 0.0}}
	})
	return gen.generate_grid_data(seed_val)

func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for k in a.keys():
				if not b.has(k) or not _deep_equal(a[k], b[k]):
					return false
			return true
		TYPE_REAL, TYPE_INT:
			return abs(float(a) - float(b)) < 0.001
		_:
			return a == b

func _layout_signature(section: Node) -> Array:
	var sig: Array = []
	for child in section.get_children():
		var tag: String = child.get_class()
		if child.get_script():
			tag = str(child.get_script().resource_path)
		sig.append("%s|%.4f|%.4f|%.4f|%.4f" % [
			tag,
			child.translation.x,
			child.translation.y,
			child.translation.z,
			child.rotation_degrees.y
		])
	sig.sort()
	return sig

func _collect_contact(body: Node, dps: float, in_core: bool, sink: Array) -> void:
	sink.append({"body": body, "dps": dps, "in_core": in_core})

func _variant_base_height(state) -> float:
	if typeof(state) == TYPE_DICTIONARY:
		return float(state.get("base_height", 0.0))
	return 0.0

# ── 1. Determinismo de la generación ─────────────────────────────────────────

func test_mst_generation_is_deterministic() -> void:
	var a: Array = _generate_mst(20261113)
	var b: Array = _generate_mst(20261113)
	var c: Array = _generate_mst(20261114)
	assert_bool(_deep_equal(a, b)).is_true()
	assert_bool(_deep_equal(a, c)).is_false()

func test_labyrinth_instancing_is_deterministic() -> void:
	var a = _make_section({})
	var b = _make_section({})
	var sig_a: Array = _layout_signature(a)
	var sig_b: Array = _layout_signature(b)
	assert_int(sig_a.size()).is_equal(sig_b.size())
	for i in range(sig_a.size()):
		assert_str(sig_a[i]).is_equal(sig_b[i])

# ── 2. Entrada alineada con el piso de la bahía ──────────────────────────────

func test_entry_cell_aligned_with_entry_height() -> void:
	var section = _make_section({})
	var grid: Array = section.get_generation_grid()
	var idx: int = int(section.entry_cell.y) * section.grid_width + int(section.entry_cell.x)
	assert_bool(idx >= 0 and idx < grid.size() and grid[idx] != null).is_true()
	assert_float(_variant_base_height(grid[idx])).is_equal_approx(section.entry_height, 0.001)
	var east_idx: int = idx + 1
	assert_bool(east_idx < grid.size() and grid[east_idx] != null).is_true()

# ── 3. Presencia de hazards ──────────────────────────────────────────────────

func test_section_spawns_fire_and_gas_hazards() -> void:
	var section = _make_section({})
	assert_object(section.get_fire_hazard()).is_not_null()
	assert_object(section.get_gas_hazard()).is_not_null()

# ── 4. Fuego posicional (compuerta X/Z) ──────────────────────────────────────

func test_fire_hazard_is_position_gated() -> void:
	var section = _make_section({})
	var fire: Node = section.get_fire_hazard()
	assert_object(fire).is_not_null()
	# Protocolo apagado → fire quedó corriendo (auto_start) y escanea.
	var inside = auto_free(DummyBody.new())
	var outside = auto_free(DummyBody.new())
	add_child(inside)
	add_child(outside)
	var entry_world: Vector3 = section.get_entry_world_position()
	inside.global_transform.origin = Vector3(entry_world.x + 3.0, entry_world.y + 0.65, entry_world.z + 3.0)
	outside.global_transform.origin = Vector3(entry_world.x + 80.0, entry_world.y + 0.65, entry_world.z)
	var contacts: Array = []
	fire.connect("heat_contact", self, "_collect_contact", [contacts])
	fire._scan_vulnerable_bodies(STEP)
	assert_int(contacts.size()).is_equal(1)
	assert_bool(contacts[0]["body"] == inside).is_true()
	assert_float(contacts[0]["dps"]).is_greater(0.0)

# ── 5. Gas: daña al cuerpo registrado en zona densa ──────────────────────────

func test_gas_hazard_damages_player_body() -> void:
	var section = _make_section({})
	var gas: Node = section.get_gas_hazard()
	assert_object(gas).is_not_null()
	var player = auto_free(DummyBody.new())
	player.name = "PlayerDummy"
	add_child(player)
	player.global_transform.origin = gas.global_transform.origin
	gas._on_body_entered(player)
	var cell: int = gas._world_position_to_cell_index(player.global_transform.origin)
	assert_int(cell).is_greater_equal(0)
	var grid_cell: Dictionary = gas._grid[cell]
	grid_cell["density"] = 3.0
	gas._grid[cell] = grid_cell
	gas._apply_player_damage(STEP)
	assert_float(player.damage_received).is_greater(0.0)

# ── 6. Ciclo de protocolo: determinista y aplica a hazards ───────────────────

func test_protocol_cycle_deterministic_and_applies() -> void:
	var a = _make_section({"protocol": true})
	var b = _make_section({"protocol": true})
	# El motor también llama _physics_process (están en el tree): lo deshabilito
	# para que solo avancen los pasos manuales y el test sea determinista.
	a.set_physics_process(false)
	b.set_physics_process(false)
	# Ciclo corto para cubrir FIRE y GAS en pocos ticks (0.5+0.25+0.75)*2 = 3s.
	a.protocol_safe_duration = 0.5
	a.protocol_warning_duration = 0.25
	a.protocol_hazard_duration = 0.75
	b.protocol_safe_duration = 0.5
	b.protocol_warning_duration = 0.25
	b.protocol_hazard_duration = 0.75
	var seq_a: Array = []
	var seq_b: Array = []
	var fire_run_a: Array = []
	var gas_dps_a: Array = []
	for i in range(240):
		a._physics_process(STEP)
		b._physics_process(STEP)
		seq_a.append(a.get_hazard_phase())
		seq_b.append(b.get_hazard_phase())
		fire_run_a.append(a.get_fire_hazard().is_running)
		gas_dps_a.append(a.get_gas_hazard().damage_per_second)
	assert_int(seq_a.size()).is_equal(seq_b.size())
	for i in range(seq_a.size()):
		assert_int(seq_a[i]).is_equal(seq_b[i])
	var saw_change := false
	for i in range(1, seq_a.size()):
		if seq_a[i] != seq_a[i - 1]:
			saw_change = true
			break
	assert_bool(saw_change).is_true()
	assert_bool(seq_a.has(PHASE_FIRE)).is_true()
	assert_bool(seq_a.has(PHASE_GAS)).is_true()
	var bad: Array = []
	for i in range(seq_a.size()):
		if seq_a[i] == PHASE_FIRE:
			if not fire_run_a[i]:
				bad.append("i=%d FIRE fire no corre" % i)
			if abs(gas_dps_a[i]) > 0.0001:
				bad.append("i=%d FIRE gas dps=%.4f" % [i, gas_dps_a[i]])
		elif seq_a[i] == PHASE_GAS:
			if fire_run_a[i]:
				bad.append("i=%d GAS fire corre" % i)
			if abs(gas_dps_a[i] - a.gas_damage_per_second) > 0.0001:
				bad.append("i=%d GAS dps=%.4f" % [i, gas_dps_a[i]])
		elif seq_a[i] == PHASE_SAFE:
			if fire_run_a[i]:
				bad.append("i=%d SAFE fire corre" % i)
			if abs(gas_dps_a[i]) > 0.0001:
				bad.append("i=%d SAFE gas dps=%.4f" % [i, gas_dps_a[i]])
	assert_str(str(bad)).is_equal("[]")
