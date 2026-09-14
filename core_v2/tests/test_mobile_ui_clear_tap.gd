extends GdUnitTestSuite

# Un toque corto en una zona vacia oculta la UI tactil (como la inactividad); arrastrar la vuelve a
# mostrar, y un toque sobre un widget o con algo con que interactuar no la oculta.

const HUDableComponentScript = preload("res://core_v2/components/HUDableComponent.gd")

var _was_active := false
var _was_mobile := false


func before_test() -> void:
	_was_active = MobileUIManager._is_touch_active
	_was_mobile = MobileUIManager._is_mobile
	MobileUIManager._is_mobile = true


func after_test() -> void:
	MobileUIManager._is_mobile = _was_mobile
	MobileUIManager._is_touch_active = _was_active
	MobileUIManager._clear_tap_index = -1
	SuitOS.clear_slots()


func _touch(pressed: bool, at: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.position = at
	return ev


func _drag(at: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.position = at
	return ev


func test_tap_on_empty_screen_hides_the_touch_ui_and_a_drag_brings_it_back() -> void:
	var empty := Vector2(400, 300)
	MobileUIManager._input(_touch(true, empty))
	assert_bool(MobileUIManager.is_touch_active()).is_true()
	MobileUIManager._input(_touch(false, empty))
	assert_bool(MobileUIManager.is_touch_active()).is_false()
	# Arrastrar vuelve a mostrarla, y un arrastre no es un toque: al soltar no la oculta.
	MobileUIManager._input(_touch(true, empty))
	MobileUIManager._input(_drag(empty + Vector2(80, 0)))
	MobileUIManager._input(_touch(false, empty + Vector2(80, 0)))
	assert_bool(MobileUIManager.is_touch_active()).is_true()


func test_tap_on_a_widget_does_not_hide_the_touch_ui() -> void:
	var screen = auto_free(HUDableComponentScript.new())
	screen.hud_screen_id = "test:a"
	add_child(screen)
	SuitOS.pin_to_slot(0, "test:a")
	var host = SuitOS.get_node("SuitOSWidgetHost")
	MobileUIManager._is_touch_active = true
	host.refresh_visibility()
	var widget: Control = host.get_widget_root().get_node("SuitOS_Widget_slot_1")
	var xf: Transform2D = widget.get_global_transform_with_canvas()
	var on_widget: Vector2 = xf.origin + Vector2(4, 4) * xf.get_scale()
	assert_bool(host.widget_at(on_widget)).is_true()
	MobileUIManager._input(_touch(true, on_widget))
	MobileUIManager._input(_touch(false, on_widget))
	assert_bool(MobileUIManager.is_touch_active()).is_true()
	SuitOS.unregister_screen(screen)
