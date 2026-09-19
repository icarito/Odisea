extends GdUnitTestSuite

# test_hud_drawer.gd - El drawer de apps y la curaduria de favoritos (FD-305).
#
# Dos cosas distintas que se prueban juntas porque solo juntas significan algo: SuitOS guarda
# QUE es favorito (y cuando sembrar los defaults), y el drawer es donde el jugador lo decide.
# El scroll se prueba como fisica, no como pixeles: acelera, decae, rebota y se alinea.

const DrawerScript = preload("res://core_v2/ui/hud/SuitOSDrawer.gd")
const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")

const DT := 1.0 / 60.0


func before_test() -> void:
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)
	SuitOS.clear_slots()
	SuitOS.clear_favorites()
	SuitOS._last_snapshots_cache.clear()


func after_test() -> void:
	SuitOS.clear_favorites()
	SuitOS._last_snapshots_cache.clear()


func _screen(id: String, title: String, relevance: float = 0.0) -> Node:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = id
	screen.hud_screen_title = title
	screen.default_relevance = relevance
	add_child(screen)
	return screen


func _drawer(rows: Array) -> Control:
	var drawer = auto_free(DrawerScript.new())
	add_child(drawer)
	drawer.rect_size = Vector2(800, 600)
	drawer.set_rows(rows)
	return drawer


func _rows_from_titles(titles: Array) -> Array:
	var rows: Array = []
	for title in titles:
		rows.append({"id": "test:" + String(title).to_lower(), "title": title, "source": "online"})
	return rows


func _titles(drawer: Control) -> Array:
	var out: Array = []
	for row in drawer._rows:
		out.append(String(row["title"]))
	return out


# --- Orden (FD-305 §3.2) ---

func test_the_list_is_alphabetical_and_ignores_accents() -> void:
	# El jugador busca por nombre: "Área" va con la A, no despues de la Z.
	var drawer = _drawer(_rows_from_titles(["Zona", "Área", "criogenia", "Bahía"]))
	assert_array(_titles(drawer)).is_equal(["Área", "Bahía", "criogenia", "Zona"])


func test_the_order_does_not_depend_on_registration_order() -> void:
	var a = _drawer(_rows_from_titles(["Sistemas", "Linterna"]))
	var b = _drawer(_rows_from_titles(["Linterna", "Sistemas"]))
	assert_array(_titles(a)).is_equal(_titles(b))


# --- Curaduria (FD-305 §2) ---

func test_the_seventh_favourite_is_denied_and_nothing_is_replaced() -> void:
	for i in range(6):
		assert_bool(SuitOS.toggle_favorite("test:%d" % i)).is_true()
	assert_bool(SuitOS.favorites_are_full()).is_true()
	var before: Array = SuitOS.get_favorites()
	# El 7mo no reemplaza nada en silencio: la curaduria es explicita.
	assert_bool(SuitOS.toggle_favorite("test:seven")).is_false()
	assert_array(SuitOS.get_favorites()).is_equal(before)

	var drawer = _drawer([{"id": "test:seven", "title": "Septima", "source": "online"}])
	drawer.toggle_favorite(SuitOS)
	assert_bool(drawer.is_denying()).is_true()
	assert_bool(drawer._rows[0].get("favorite", false)).is_false()
	assert_array(SuitOS.get_favorites()).is_equal(before)


func test_x_toggles_the_favourite_of_the_focused_row() -> void:
	_screen("test:a", "Alpha")
	SuitOS.clear_favorites()
	var drawer = _drawer([{"id": "test:a", "title": "Alpha", "source": "online"}])
	drawer.toggle_favorite(SuitOS)
	assert_bool(SuitOS.is_favorite("test:a")).is_true()
	assert_bool(drawer._rows[0]["favorite"]).is_true()
	drawer.toggle_favorite(SuitOS)
	assert_bool(SuitOS.is_favorite("test:a")).is_false()


func test_the_defaults_are_seeded_once_and_never_come_back() -> void:
	SuitOS._favorites = []
	SuitOS._favorites_initialized = false
	assert_array(SuitOS.get_favorites()).is_equal(SuitOS.DEFAULT_FAVORITES)
	# Borrarlos a proposito tiene que quedar borrado: sin la bandera, el set por defecto
	# reaparecia cada vez que alguien limpiaba su lista, que es justo el bug a evitar.
	SuitOS.clear_favorites()
	assert_array(SuitOS.get_favorites()).is_empty()
	SuitOS.restore_state(SuitOS.save_state())
	assert_array(SuitOS.get_favorites()).is_empty()


func test_a_save_without_the_key_seeds_the_defaults_and_does_not_crash() -> void:
	SuitOS.clear_favorites()
	SuitOS.restore_state({"pinned_slots": ["", "", "", ""]})
	# Un save viejo se trata como "todavia no hay curaduria": siembra los defaults una vez.
	assert_array(SuitOS.get_favorites()).is_equal(SuitOS.DEFAULT_FAVORITES)


func test_favourites_survive_the_checkpoint() -> void:
	SuitOS.clear_favorites()
	SuitOS.toggle_favorite("ship:cryopods")
	var saved: Dictionary = SuitOS.get_snapshot()
	assert_str(to_json(parse_json(to_json(saved)))).is_equal(to_json(saved)) # JSON-safe
	SuitOS.clear_favorites()
	SuitOS.restore_snapshot(saved)
	assert_array(SuitOS.get_favorites()).is_equal(["ship:cryopods"])


# --- Favorito offline (FD-305 §2) ---

func test_an_unregistered_favourite_stays_but_leaves_the_dial_until_it_is_known() -> void:
	SuitOS.clear_favorites()
	var screen = _screen("test:a", "Alpha")
	SuitOS.toggle_favorite("test:a")
	assert_array(SuitOS.get_favorites_ordered()).is_equal(["test:a"])

	# Sale de la escena: sigue siendo favorito y sigue en el arco, con el titulo que se le conoce.
	SuitOS.unregister_screen("test:a")
	assert_bool(SuitOS.is_favorite("test:a")).is_true()
	assert_array(SuitOS.get_favorites_ordered()).is_equal(["test:a"])
	assert_str(SuitOS.screen_title_of("test:a")).is_equal("Alpha")

	# Uno que nunca se vio (un default de una pantalla que esta partida no tiene) no ensucia el
	# dial, pero no se pierde de la lista guardada.
	SuitOS.toggle_favorite("never:seen")
	assert_bool(SuitOS.is_favorite("never:seen")).is_true()
	assert_array(SuitOS.get_favorites_ordered()).is_equal(["test:a"])
	screen.free()


# --- Orden por relevancia del arco (FD-306 §2) ---

func test_the_arc_is_sorted_by_relevance_with_a_stable_alphabetical_tie_break() -> void:
	_screen("test:c", "Charlie", 0.0)
	_screen("test:a", "Alpha", 0.0)
	_screen("test:b", "Bravo", 0.9)
	for id in ["test:a", "test:b", "test:c"]:
		SuitOS.toggle_favorite(id)
	# Relevancia alta al primer sector (el que el pulgar encuentra sin mirar).
	assert_array(SuitOS.get_favorites_ordered()).is_equal(["test:b", "test:a", "test:c"])
	# Empatados en 0.0, el desempate es el titulo y no cambia entre llamadas: sin el, dos
	# pantallas con la misma relevancia se intercambian de lugar entre frames.
	for _i in range(5):
		assert_array(SuitOS.get_favorites_ordered()).is_equal(["test:b", "test:a", "test:c"])


# --- Scroll analogico (FD-305 §3.3) ---

func test_the_stick_gives_velocity_and_it_decays_when_let_go() -> void:
	var drawer = _drawer(_rows_from_titles(["A", "B", "C", "D", "E", "F", "G", "H"]))
	for _i in range(10):
		drawer.drive(1.0, 0, DT)
	var moving: float = drawer._velocity
	assert_float(moving).is_greater(0.0)
	assert_float(drawer._scroll).is_greater(0.0)
	# Soltado: la lista acompaña y decae, no frena en seco.
	drawer.drive(0.0, 0, DT)
	assert_float(drawer._velocity).is_less(moving)
	for _i in range(120):
		drawer.drive(0.0, 0, DT)
	assert_float(drawer._velocity).is_equal_approx(0.0, 0.001)


func test_when_it_stops_the_nearest_row_lines_itself_up() -> void:
	var drawer = _drawer(_rows_from_titles(["A", "B", "C", "D", "E"]))
	drawer._scroll = drawer.ROW_HEIGHT * 2.0 + 9.0
	for _i in range(180):
		drawer.drive(0.0, 0, DT)
	assert_float(drawer._scroll).is_equal_approx(drawer.ROW_HEIGHT * 2.0, 1.0)
	assert_int(drawer.focused_index()).is_equal(2)


func test_the_ends_push_back_instead_of_clamping_dead() -> void:
	var drawer = _drawer(_rows_from_titles(["A", "B", "C"]))
	for _i in range(60):
		drawer.drive(1.0, 0, DT) # empuja mas alla del ultimo
	assert_float(drawer._scroll).is_less_equal(drawer._max_scroll() + drawer.ROW_HEIGHT)
	for _i in range(180):
		drawer.drive(0.0, 0, DT) # soltado: rebota a su sitio
	assert_float(drawer._scroll).is_equal_approx(drawer._max_scroll(), 1.0)


func test_the_dpad_steps_one_row_and_only_repeats_after_the_hold_threshold() -> void:
	var drawer = _drawer(_rows_from_titles(["A", "B", "C", "D"]))
	drawer.drive(0.0, 1, DT)
	assert_int(drawer.focused_index()).is_equal(1)
	# Sostenida, no dispara otra vez hasta pasar el umbral: un paso por pulsacion.
	for _i in range(5):
		drawer.drive(0.0, 1, DT)
	assert_int(drawer.focused_index()).is_equal(1)
	# Soltar y volver a pulsar si da otro paso.
	drawer.drive(0.0, 0, DT)
	drawer.drive(0.0, 1, DT)
	assert_int(drawer.focused_index()).is_equal(2)
	# Y no se pasa del final.
	for _i in range(6):
		drawer.drive(0.0, 0, DT)
		drawer.drive(0.0, 1, DT)
	assert_int(drawer.focused_index()).is_equal(3)


# --- Frescura (FD-305 §5) ---

func test_rebuilding_the_list_keeps_the_focused_row() -> void:
	var drawer = _drawer(_rows_from_titles(["Alpha", "Bravo", "Charlie"]))
	drawer.focus_row(2)
	assert_str(drawer.focused_screen_id()).is_equal("test:charlie")
	# Se registra una pantalla nueva con el drawer abierto: entra en su lugar alfabetico y el
	# foco sigue donde estaba.
	drawer.set_rows(_rows_from_titles(["Alpha", "Bravo", "Charlie", "Bahia"]))
	assert_int(drawer.row_count()).is_equal(4)
	assert_str(drawer.focused_screen_id()).is_equal("test:charlie")


func test_a_activates_the_focused_row() -> void:
	var drawer = _drawer(_rows_from_titles(["Alpha", "Bravo"]))
	drawer.connect("screen_chosen", self, "_on_chosen")
	_chosen = ""
	drawer.focus_row(1)
	drawer.activate()
	assert_str(_chosen).is_equal("test:bravo")


var _chosen := ""


func _on_chosen(id: String) -> void:
	_chosen = id
