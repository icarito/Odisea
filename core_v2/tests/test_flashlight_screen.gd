extends GdUnitTestSuite

# test_flashlight_screen.gd - Unit tests for FlashlightScreen and battery integration (FD-298)

const HelmetFlashlightScript = preload("res://core_v2/props/lights/HelmetFlashlight.gd")
const FlashlightScreenScript = preload("res://core_v2/things/FlashlightScreen.gd")
const FlashlightWidgetScript = preload("res://core_v2/ui/hud/FlashlightWidget.gd")

var _flashlight = null
var _screen = null

func before_test() -> void:
	SuitOS.min_relevance_a = SuitOS.MIN_RELEVANCE_A
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

	var flashlight_packed = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	_flashlight = auto_free(flashlight_packed.instance())
	add_child(_flashlight)
	_screen = _flashlight.get_node_or_null("FlashlightScreen")

func test_flashlight_battery_drain_and_auto_shutoff() -> void:
	_flashlight.battery_max = 10.0
	_flashlight.battery = 10.0
	_flashlight.battery_drain_per_second = 5.0
	_flashlight.toggle() # Turns on
	assert_bool(_flashlight.enabled).is_true()

	# Process 1 second -> battery drops to 5.0
	_flashlight._process(1.0)
	assert_float(_flashlight.battery).is_equal_approx(5.0, 0.01)
	assert_bool(_flashlight.enabled).is_true()

	# Process 1.5 seconds -> battery reaches 0.0, flashlight auto-shuts off
	_flashlight._process(1.5)
	assert_float(_flashlight.battery).is_equal(0.0)
	assert_bool(_flashlight.enabled).is_false()

	# Attempt to turn on with 0 battery is blocked
	_flashlight.toggle()
	assert_bool(_flashlight.enabled).is_false()

func test_flashlight_screen_registration_and_snapshot() -> void:
	assert_bool(SuitOS.has_screen("player:flashlight")).is_true()

	var snap: Dictionary = _screen.widget_snapshot()
	assert_str(String(snap.get("id", ""))).is_equal("player:flashlight")
	assert_str(String(snap.get("title", ""))).is_equal("LINTERNA")
	assert_dict(snap).contains_keys(["proto", "on", "battery", "battery_max", "low", "source"])
	assert_bool(bool(snap.get("on", true))).is_false()

	# JSON-safety verification
	var json_text := JSON.print(snap)
	assert_bool(json_text.empty()).is_false()
	var parse_res := JSON.parse(json_text)
	assert_int(parse_res.error).is_equal(OK)

func test_flashlight_screen_actions_and_relevance() -> void:
	var base_rel: float = _screen.relevance()
	assert_float(base_rel).is_equal(0.1)

	# Action toggle via SuitOS
	var res: Dictionary = SuitOS.perform_action("player:flashlight", "toggle")
	assert_bool(bool(res.get("ok", false))).is_true()
	assert_bool(_flashlight.enabled).is_true()

	var rel_on: float = _screen.relevance()
	assert_float(rel_on).is_greater(base_rel)

	# Drain to low battery
	_flashlight.battery = 15.0 # <= battery_low_threshold (20.0)
	var rel_low: float = _screen.relevance()
	assert_float(rel_low).is_greater(rel_on)

func test_flashlight_widget_ui_snapshot() -> void:
	var widget = auto_free(FlashlightWidgetScript.new())
	var margin = MarginContainer.new()
	margin.name = "Margin"
	widget.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)

	var header = HBoxContainer.new()
	header.name = "Header"
	vbox.add_child(header)

	var dot = ColorRect.new()
	dot.name = "StatusDot"
	header.add_child(dot)

	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	header.add_child(title_lbl)

	var meter_lbl = Label.new()
	meter_lbl.name = "MeterLabel"
	vbox.add_child(meter_lbl)

	var status_row = HBoxContainer.new()
	status_row.name = "StatusRow"
	vbox.add_child(status_row)

	var status_lbl = Label.new()
	status_lbl.name = "StatusLabel"
	status_row.add_child(status_lbl)

	var btn = Button.new()
	btn.name = "ToggleButton"
	status_row.add_child(btn)

	add_child(widget)

	widget.update_snapshot({
		"title": "LINTERNA",
		"on": true,
		"battery": 50.0,
		"battery_max": 100.0,
		"low": false,
		"source": "online"
	})

	assert_str(title_lbl.text).is_equal("LINTERNA")
	assert_str(btn.text).is_equal("APAGAR")
	assert_bool(btn.disabled).is_false()
	assert_str(meter_lbl.text).is_equal("BAT: [█████░░░░░]")

	widget.update_snapshot({
		"title": "LINTERNA",
		"on": false,
		"battery": 0.0,
		"battery_max": 100.0,
		"low": true,
		"source": "online"
	})

	assert_str(btn.text).is_equal("ENCENDER")
	assert_str(status_lbl.text).is_equal("ESTADO: APAGADA")
	assert_str(meter_lbl.text).is_equal("BAT: [░░░░░░░░░░]")
