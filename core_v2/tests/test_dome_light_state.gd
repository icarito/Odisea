extends GdUnitTestSuite

# FD-284 — estados de iluminación del domo.
#
# Se arma una escena sintética (BakedLightmap + un LightPathV2) en vez de
# instanciar Dome_Intro: la escena real son 3200 líneas de .tscn y su bake pesa
# 56 MB, y nada de eso hace falta para verificar el contrato de estados.

const DomeLightStateScript := preload("res://core_v2/systems/DomeLightState.gd")

var _loaded_paths := []
var _state_changes := []


func _on_state_changed(old, new) -> void:
	_state_changes.append([old, new])


func _make_state(root: Node) -> Node:
	var manager: Node = auto_free(DomeLightStateScript.new())
	manager.root_override = root
	# Mock del load: el .lmbake de cada modo puede no estar horneado todavía, y
	# cargar 56 MB dentro de una suite headless no aporta nada al contrato.
	manager.bake_loader = funcref(self, "_fake_load")
	add_child(manager)
	return manager


func _fake_load(path: String):
	_loaded_paths.append(path)
	var data := BakedLightmapData.new()
	data.set_meta("fake_path", path)
	return data


const SHIPPED_BAKE := "res://core_v2/levels/interiors/Dome_Intro.lmbake"


func _make_dome(dome_name: String) -> Node:
	var root: Spatial = auto_free(Spatial.new())
	root.name = dome_name
	var baked := BakedLightmap.new()
	baked.name = "BakedLightmap"
	# PLENO reusa el bake que la escena ya trae, asi que el nodo tiene que venir con uno.
	var shipped := BakedLightmapData.new()
	shipped.take_over_path(SHIPPED_BAKE)
	baked.light_data = shipped
	root.add_child(baked)
	var path := LightPathV2.new()
	path.name = "WallLights"
	path.auto_build = false
	path.light_pool_size = 3
	root.add_child(path)
	add_child(root)
	return root


func test_estados_cambian_el_bake_y_emiten_la_senal():
	_loaded_paths.clear()
	var root := _make_dome("Dome_Intro")
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	_state_changes.clear()
	manager.connect("state_changed", self, "_on_state_changed")
	manager.set_state(2)  # PLENO
	assert_int(manager.get_state()).is_equal(2)
	assert_array(_state_changes).is_equal([[1, 2]])
	assert_str(manager.get_active_bake_path()).is_equal(
		SHIPPED_BAKE)

	manager.set_state(0)  # OSCURAS
	assert_str(manager.get_active_bake_path()).is_equal(
		"res://core_v2/levels/interiors/lightmaps/dark/Dome_Intro.lmbake")

	# OSCURAS y BAJO comparten el bake oscuro: no debe recargarse al pasar de uno
	# al otro, que es justo lo que en iOS tendría los dos recursos en memoria.
	var loads_antes: int = _loaded_paths.size()
	manager.set_state(1)  # BAJO
	assert_int(_loaded_paths.size()).is_equal(loads_antes)


func test_el_bake_nunca_queda_con_dos_recursos_a_la_vez():
	_loaded_paths.clear()
	var root := _make_dome("Dome_Intro")
	var baked: BakedLightmap = root.get_node("BakedLightmap")
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	manager.set_state(2)
	var pleno = baked.light_data
	assert_object(pleno).is_not_null()

	manager.set_state(0)
	# El recurso quedó reemplazado, no acumulado: el nodo referencia uno solo y es
	# el del modo nuevo.
	assert_object(baked.light_data).is_not_same(pleno)
	assert_str(String(baked.light_data.get_meta("fake_path"))).contains("/dark/")


func test_presupuesto_de_luces_runtime_por_estado():
	var root := _make_dome("Dome_Intro")
	var pool: LightPathV2 = root.get_node("WallLights")
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	# PLENO: todo lo ilumina el bake, cero luces runtime.
	manager.set_state(2)
	assert_int(pool.light_pool_size).is_equal(0)

	# OSCURAS: tampoco hay fixtures encendidos.
	manager.set_state(0)
	assert_int(pool.light_pool_size).is_equal(0)

	# BAJO: vuelve el pool original, sin inventarle un tamaño nuevo.
	manager.set_state(1)
	assert_int(pool.light_pool_size).is_equal(3)


func test_escena_sin_lightmap_no_rompe_y_conserva_los_estados_de_pool():
	_loaded_paths.clear()
	# Dome_Prologue comparte Dome_Base con Dome_Intro pero no tiene BakedLightmap.
	var root: Spatial = auto_free(Spatial.new())
	root.name = "Dome_Prologue"
	var pool := LightPathV2.new()
	pool.name = "WallLights"
	pool.auto_build = false
	pool.light_pool_size = 2
	root.add_child(pool)
	add_child(root)

	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	manager.set_state(2)
	assert_array(_loaded_paths).is_empty()
	assert_str(manager.get_active_bake_path()).is_empty()
	assert_int(pool.light_pool_size).is_equal(0)

	manager.set_state(1)
	assert_int(pool.light_pool_size).is_equal(2)


func test_snapshot_lleva_el_enum_y_el_hash_del_bake():
	var root := _make_dome("Dome_Intro")
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	manager.set_state(2)
	var snap: Dictionary = manager.get_snapshot()
	assert_int(int(snap["dome_light_state"])).is_equal(2)
	assert_int(int(snap["dome_bake_hash"])).is_equal(
		SHIPPED_BAKE.hash())

	manager.set_state(0)
	assert_int(int(manager.get_snapshot()["dome_bake_hash"])).is_not_equal(int(snap["dome_bake_hash"]))

	manager.restore_snapshot(snap)
	assert_int(manager.get_state()).is_equal(2)


func test_pleno_no_deja_luces_ni_sonido_de_cambio_de_luz():
	var root := _make_dome("Dome_Intro")
	var pool: LightPathV2 = root.get_node("WallLights")
	pool.light_pool_size = 3
	pool.activation_sound = AudioStreamSample.new()
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	# BAJO: el pool existe, y con el pool existe el sonido de activación.
	manager.set_state(1)
	pool.call("_ensure_light_pool")
	assert_int(_omni_count(pool)).is_equal(3)

	# PLENO: la pared la ilumina el bake. Sin luces del pool no hay cambio de luz que
	# anunciar — el sonido se dispara dentro de _drive_lights(), que corta en pool 0.
	manager.set_state(2)
	assert_int(pool.light_pool_size).is_equal(0)
	assert_int(_omni_count(pool)).is_equal(0)


func _omni_count(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is OmniLight:
			n += 1
	return n


func test_bajo_restaura_el_pool_que_dejo_el_presupuesto_no_el_original():
	# MobileLightBudget puede haber subido el pool a 3 (mejora progresiva) despues de
	# que DomeLightState leyo el valor autorizado. Al volver de PLENO tiene que
	# devolver el presupuesto vigente, no el que vio la primera vez.
	var root := _make_dome("Dome_Intro")
	var pool: LightPathV2 = root.get_node("WallLights")
	pool.light_pool_size = 1
	var manager := _make_state(root)
	yield(get_tree(), "idle_frame")

	manager.set_state(1)
	assert_int(pool.light_pool_size).is_equal(1)

	pool.light_pool_size = 3  # el presupuesto sube por su cuenta
	manager.set_state(2)
	assert_int(pool.light_pool_size).is_equal(0)

	manager.set_state(1)
	assert_int(pool.light_pool_size).is_equal(3)
