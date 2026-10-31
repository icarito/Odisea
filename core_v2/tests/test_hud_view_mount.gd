extends GdUnitTestSuite

# test_hud_view_mount.gd - El presentador con vista propia recibe el puntero del modo
# Pantalla. Antes nadie alimentaba su Viewport, asi que los controles de la Linterna (y de
# Traje/Protocolo/Rendimiento) quedaban mudos: se veian pero no respondian al click.
#
# Cubre el mecanismo de HudViewMount.forward_view_input(): mapeo uv [0,1] -> pixeles del
# Viewport y entrega del evento a la vista (Control por el pipeline de GUI; ImGuiCanvas por
# _input, que es lo que el pipeline no alcanza).

const HudViewMountScript = preload("res://core_v2/ui/hud/HudViewMount.gd")


class RecordingControl extends Control:
	var events := []

	func _gui_input(event: InputEvent) -> void:
		events.append(event)


func _mount_with_view(size: Vector2) -> Dictionary:
	var mount = auto_free(HudViewMountScript.new())
	var viewport = auto_free(Viewport.new())
	add_child(viewport)
	viewport.size = size
	var view = auto_free(RecordingControl.new())
	view.rect_size = size
	viewport.add_child(view)
	mount._presenter_view = view
	mount._presenter_viewport = viewport
	return {"mount": mount, "view": view}


func test_forward_maps_uv_to_viewport_pixels_and_delivers_the_click() -> void:
	var built: Dictionary = _mount_with_view(Vector2(200.0, 100.0))
	yield (await_idle_frame(), "completed")
	var mount = built["mount"]
	var view = built["view"]
	assert_bool(mount.has_own_view()).is_true()

	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	assert_bool(mount.forward_view_input(click, Vector2(0.5, 0.5))).is_true()
	assert_int(view.events.size()).is_equal(1)
	assert_int(int(view.events[0].button_index)).is_equal(BUTTON_LEFT)
	assert_vector2(view.events[0].position).is_equal(Vector2(100.0, 50.0))


func test_forward_carries_motion_in_viewport_pixels() -> void:
	var built: Dictionary = _mount_with_view(Vector2(200.0, 100.0))
	yield (await_idle_frame(), "completed")
	var motion := InputEventMouseMotion.new()
	assert_bool(built["mount"].forward_view_input(motion, Vector2(0.25, 0.75))).is_true()
	assert_vector2(built["view"].events[0].position).is_equal(Vector2(50.0, 75.0))


func test_forward_reports_no_view_without_a_presenter() -> void:
	var mount = auto_free(HudViewMountScript.new())
	assert_bool(mount.has_own_view()).is_false()
	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	assert_bool(mount.forward_view_input(click, Vector2(0.5, 0.5))).is_false()
