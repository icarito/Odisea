extends GdUnitTestSuite

# FD-325 T3 — HUD superior unificado del Ark Run.
# Verifica: (1) zona segura — todo panel fijo vive en y in [0,140] y no pisa las
# zonas táctiles inferiores de MobileUI; (2) la barra longitudinal ubica Puente/
# centro/Motor y el fantasma; (3) el perfil radial mapea HUB/TERRAZA/CASCO; (4) la
# flecha de gravedad gira ~45° al encender (a_axial 0 -> 9.8).

const TopBar = preload("res://core_v2/ui/suit_os/ArkRunTopBarView.gd")
const HudScript = preload("res://core_v2/levels/ark_run/ArkRunHudOverlay.gd")
const EPS := 0.001
const TOUCH := 320.0
const STRIP_LIMIT := 140.0


func _fixed_panels(hud) -> Array:
	# Sólo cuenta paneles VISIBLES: en gameplay el mapa superior arranca oculto.
	var panels: Array = []
	var top_bar = hud.get_top_bar()
	if top_bar != null and top_bar.visible:
		panels.append(top_bar)
		panels = panels + top_bar.get_fixed_panels()
	if hud._phase_label.visible:
		panels.append(hud._phase_label)
	if hud._stats_label.visible:
		panels.append(hud._stats_label)
	if hud._timer_label.visible:
		panels.append(hud._timer_label)
	var minimap = hud.get_node_or_null("HudRoot/Minimap")
	if minimap != null and minimap.visible:
		panels.append(minimap)
	return panels


func _assert_zone(hud, viewport: Vector2) -> void:
	var w: float = viewport.x
	var h: float = viewport.y
	var panels := _fixed_panels(hud)
	# En gameplay sólo la fase compacta está visible arriba-centro.
	assert_int(panels.size()).is_greater_equal(1)
	for panel in panels:
		if panel == null:
			continue
		var rect: Rect2 = panel.get_global_rect()
		assert_float(rect.end.y).is_less_equal(STRIP_LIMIT)
		var lower_left := Rect2(0.0, h - TOUCH, TOUCH, TOUCH)
		var lower_right := Rect2(w - TOUCH, h - TOUCH, TOUCH, TOUCH)
		assert_bool(rect.intersects(lower_left)).is_false()
		assert_bool(rect.intersects(lower_right)).is_false()


func test_all_fixed_hud_panels_stay_in_top_strip_1280x720() -> void:
	var hud = auto_free(HudScript.new())
	add_child(hud)
	get_viewport().set_size_override(true, Vector2(1280, 720))
	hud.refresh({"phase": "TEST", "timer": 0.0, "best": -1.0})
	yield(get_tree(), "idle_frame")
	_assert_zone(hud, Vector2(1280.0, 720.0))
	get_viewport().set_size_override(false)


func test_all_fixed_hud_panels_stay_in_top_strip_800x480() -> void:
	var hud = auto_free(HudScript.new())
	add_child(hud)
	get_viewport().set_size_override(true, Vector2(800, 480))
	hud.refresh({"phase": "TEST", "timer": 0.0, "best": -1.0})
	yield(get_tree(), "idle_frame")
	_assert_zone(hud, Vector2(800.0, 480.0))
	get_viewport().set_size_override(false)


func test_longitudinal_bar_places_bridge_core_engine_and_ghost() -> void:
	assert_float(TopBar.z_norm_for(1000.0)).is_equal_approx(1.0, EPS)
	assert_float(TopBar.z_norm_for(0.0)).is_equal_approx(0.0, EPS)
	assert_float(TopBar.z_norm_for(-1000.0)).is_equal_approx(-1.0, EPS)
	var left := 100.0
	var right := 500.0
	# +1000 (Puente, +Z) -> extremo IZQUIERDO; 0 -> centro; -1000 (Motor) -> derecho.
	assert_float(TopBar.z_point_x(left, right, TopBar.z_norm_for(1000.0))) \
		.is_equal_approx(left, EPS)
	assert_float(TopBar.z_point_x(left, right, TopBar.z_norm_for(0.0))) \
		.is_equal_approx((left + right) * 0.5, EPS)
	assert_float(TopBar.z_point_x(left, right, TopBar.z_norm_for(-1000.0))) \
		.is_equal_approx(right, EPS)

	var hud = auto_free(HudScript.new())
	add_child(hud)
	hud.refresh({"phase": "RUN", "z": 0.5, "ghost_z": -0.25})
	assert_bool(hud.get_top_bar().center_bar.ghost_visible).is_true()
	assert_float(hud.get_top_bar().center_bar.ghost_z_norm).is_equal_approx(-0.25, EPS)
	assert_float(hud.get_top_bar().center_bar.z_norm).is_equal_approx(0.5, EPS)
	hud.refresh({"phase": "RUN", "z": 0.5})
	assert_bool(hud.get_top_bar().center_bar.ghost_visible).is_false()


func test_radial_profile_maps_hub_terrace_hull() -> void:
	assert_float(TopBar.radial_ratio_for(8.0)).is_equal_approx(8.0 / 340.0, EPS)
	assert_float(TopBar.radial_ratio_for(240.0)).is_equal_approx(240.0 / 340.0, EPS)
	assert_float(TopBar.radial_ratio_for(340.0)).is_equal_approx(1.0, EPS)
	assert_float(TopBar.radial_point_x(0.0, 340.0, TopBar.radial_ratio_for(240.0))) \
		.is_equal_approx(240.0, EPS)


func test_gravity_arrow_rotates_45_degrees_on_ignition() -> void:
	var idle: Vector2 = TopBar.gravity_arrow(0.0, 9.8)
	assert_float(idle.x).is_equal_approx(0.0, EPS)
	assert_float(idle.y).is_equal_approx(1.0, EPS)
	var burning_mag: float = sqrt(9.8 * 9.8 + 9.8 * 9.8)
	var burning: Vector2 = TopBar.gravity_arrow(9.8, burning_mag)
	assert_float(burning.x).is_equal_approx(0.7071, EPS)
	assert_float(burning.y).is_equal_approx(0.7071, EPS)
	assert_float(TopBar.gravity_rotation_deg(9.8, burning_mag)).is_equal_approx(45.0, 0.01)
	assert_float(TopBar.gravity_rotation_deg(0.0, 9.8)).is_equal_approx(0.0, EPS)

# FD-325 polish (playtest): en gameplay el mapa superior arranca OCULTO (navegación
# diegética, cero solape con los widgets de slots de SuitOSWidgetHost). El mapa completo
# sigue disponible para Suit OS `ship:ark_nav` y encendiendo `set_top_map_visible(true)`.
func test_top_map_hidden_by_default_and_toggleable() -> void:
	var hud = auto_free(HudScript.new())
	add_child(hud)
	yield(get_tree(), "idle_frame")
	assert_bool(hud.show_top_map).is_false()
	assert_bool(hud.get_top_bar().visible).is_false()
	assert_bool(hud._stats_label.visible).is_false()
	var minimap = hud.get_node_or_null("HudRoot/Minimap")
	assert_object(minimap).is_not_null()
	assert_bool(minimap.visible).is_false()
	# La fase compacta sigue visible y arriba-centro (no invade esquinas ni slots).
	assert_bool(hud._phase_label.visible).is_true()
	var view: Vector2 = Vector2(1280.0, 720.0)
	var phase_rect: Rect2 = hud._phase_label.get_global_rect()
	assert_float(phase_rect.position.y).is_less_equal(24.0)
	assert_float(phase_rect.position.x).is_greater_equal(TOUCH)
	assert_float(phase_rect.end.x).is_less_equal(view.x - TOUCH)

	# Encender el mapa devuelve los paneles fijos al layout superior original.
	hud.set_top_map_visible(true)
	yield(get_tree(), "idle_frame")
	get_viewport().set_size_override(true, view)
	hud.refresh({"phase": "TEST", "timer": 0.0, "best": -1.0})
	yield(get_tree(), "idle_frame")
	assert_bool(hud.get_top_bar().visible).is_true()
	assert_bool(hud._stats_label.visible).is_true()
	hud.refresh({"phase": "RUN", "z": 0.25, "ghost_z": 0.0})
	assert_float(hud.get_top_bar().center_bar.z_norm).is_equal_approx(0.25, EPS)
	get_viewport().set_size_override(false)

	hud.set_top_map_visible(false)
	assert_bool(hud.get_top_bar().visible).is_false()
