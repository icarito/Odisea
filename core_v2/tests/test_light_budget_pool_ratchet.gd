extends GdUnitTestSuite

# FD-284 — el pool de luces ahora sube ademas de bajar ("mejora progresiva"), pero con
# trinquete: una sola bajada cancela la subida para el resto de la sesion, porque cada
# cambio del conteo recompila variantes de shader en GLES2.

const BudgetScript := preload("res://core_v2/systems/MobileLightBudget.gd")


func _make_budget(paths: Array) -> Node:
	var budget: Node = auto_free(BudgetScript.new())
	budget.set("_paths", paths)
	add_child(budget)
	return budget


func _make_path(size: int) -> LightPathV2:
	var path := LightPathV2.new()
	path.auto_build = false
	path.light_pool_size = size
	add_child(auto_free(path))
	return path


func test_sube_de_a_una_hasta_el_techo():
	var path := _make_path(1)
	var budget := _make_budget([path])
	for _i in range(5):
		budget.call("_ajustar_pool", 1)
	assert_int(path.light_pool_size).is_equal(budget.max_pool_size)


func test_una_bajada_cancela_la_subida_para_siempre():
	var path := _make_path(3)
	var budget := _make_budget([path])
	budget.call("_ajustar_pool", -1)
	assert_int(path.light_pool_size).is_equal(2)
	assert_bool(budget.get("_degradado")).is_true()
	# El trinquete vive en _process; _ajustar_pool sigue siendo la primitiva. Lo que se
	# fija aca es que la bajada deja la marca que _process consulta para no volver a subir.
	assert_bool(budget.call("_puede_cambiar")).is_false()


func test_no_pisa_un_pool_apagado_a_proposito():
	# DomeLightState pone el pool en 0 en PLENO y OSCURAS. Eso no es falta de
	# presupuesto: es una decision del nivel, y el budget no la revierte.
	var path := _make_path(0)
	var budget := _make_budget([path])
	budget.call("_ajustar_pool", 1)
	assert_int(path.light_pool_size).is_equal(0)


func test_no_baja_por_debajo_de_lo_autorizado_cuando_ya_esta_bajo():
	# WallLights viene autorizado en 1, por debajo de min_pool_size (2). Bajar no debe
	# tocarlo: min_pool_size es un piso para el adelgazamiento, no un valor a imponer.
	var path := _make_path(1)
	var budget := _make_budget([path])
	budget.call("_ajustar_pool", -1)
	assert_int(path.light_pool_size).is_equal(1)
