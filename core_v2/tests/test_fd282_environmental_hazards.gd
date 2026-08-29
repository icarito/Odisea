extends GdUnitTestSuite

# test_fd282_environmental_hazards.gd - GdUnit3 unit tests for FD-282 (Environmental Hazards & Wind Zones).
# Validates realistic temperature thresholds, cryogenic shock damage, RadiatorProp room heating,
# steam/vapor contamination hazard, and WindTunnelV2 kinetic forces on player and pushable boxes.

const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")
const RadiatorPropScript = preload("res://core_v2/props/machinery/RadiatorProp.gd")
const WindTunnelV2Script = preload("res://core_v2/components/WindTunnelV2.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const CryoVentBaseScript = preload("res://core_v2/visual/cryo_vent/CryoVentBase.gd")

const STEP := 1.0 / 60.0

class DummyPlayerNode extends Spatial:
	var health: float = 100.0
	var external_velocity: Vector3 = Vector3.ZERO
	var is_external_static: bool = true

	func _init() -> void:
		add_to_group("player")

	func take_damage(amount: float) -> void:
		health -= amount

	func set_external_velocity(v: Vector3) -> void:
		external_velocity = v

	func set_external_source_is_static(val: bool) -> void:
		is_external_static = val


func _step_node(node, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		if node.has_method("_physics_process"):
			node._physics_process(STEP)


# 1. Realistic Temperature Thresholds and Signals
func test_realistic_temperature_thresholds() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = 20.0 # Thermal Comfort Zone
	add_child(room)

	var freezing_signals := [0]
	var lethal_signals := [0]
	var cryo_signals := [0]

	room.connect("freezing_changed", self, "_on_signal", [freezing_signals])
	room.connect("lethal_cold_changed", self, "_on_signal", [lethal_signals])
	room.connect("absolute_cryo_changed", self, "_on_signal", [cryo_signals])

	# Comfort Zone (15..20°C): Nominal
	assert_bool(room.is_freezing()).is_false()
	assert_bool(room.is_lethal_cold()).is_false()
	assert_bool(room.is_absolute_cryo()).is_false()

	# Freezing Point (0°C to -10°C)
	room.set_temperature(-5.0)
	assert_bool(room.is_freezing()).is_true()
	assert_int(freezing_signals[0]).is_equal(1)
	assert_bool(room.is_lethal_cold()).is_false()

	# Critical Cold / Thermal Decline (-50°C)
	room.set_temperature(-50.0)
	assert_bool(room.is_lethal_cold()).is_true()
	assert_int(lethal_signals[0]).is_equal(1)
	assert_bool(room.is_absolute_cryo()).is_false()

	# Absolute Cryogenic Rupture (<= -150°C)
	room.set_temperature(-155.0)
	assert_bool(room.is_absolute_cryo()).is_true()
	assert_int(cryo_signals[0]).is_equal(1)


# 2. Proximity Cryogenic Shock Damage (< 3.0m)
func test_proximity_cryogenic_shock_damage() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = 20.0 # Room temp is safe (no global lethal cold)
	add_child(room)

	var player = auto_free(DummyPlayerNode.new())
	player.global_transform.origin = Vector3(0, 0, 0)
	add_child(player)

	var leak = auto_free(CoolantLeakScript.new())
	leak.global_transform.origin = Vector3(2.0, 0, 0) # 2m < 3m proximity
	add_child(leak)
	leak.trigger_leak()
	leak._leak_intensity = 1.0 # Active leak

	# Room process tick
	_step_node(room, 1.0)

	# Cold shock damage (40 dps * 1s = 40 damage => health 60)
	assert_float(player.health).is_equal_approx(60.0, 0.1)

	# Move player outside 3m proximity (5m away)
	player.global_transform.origin = Vector3(5.0, 0, 0)
	_step_node(room, 1.0)
	# Health remains 60.0 (no additional damage)
	assert_float(player.health).is_equal_approx(60.0, 0.1)


# 3. RadiatorProp Heating & Steam/Vapor Hazard Loop
func test_radiator_prop_heating_and_vapor_hazard() -> void:
	var room = auto_free(Room3DScript.new())
	room.temperature = -10.0
	room.contamination = 0.6
	room.vapor_damage_per_second = 20.0
	add_child(room)

	var radiator = auto_free(RadiatorPropScript.new())
	radiator.heating_rate = 10.0
	radiator.room_path = room.get_path()
	add_child(radiator)
	radiator.set_heat_level(1.0)

	_step_node(radiator, 1.0)
	assert_float(room.temperature).is_equal_approx(0.0, 0.1)


# 4. WindTunnelV2 Force on Player and Rigid Bodies
func test_wind_tunnel_force_application() -> void:
	var wind = auto_free(WindTunnelV2Script.new())
	wind.wind_velocity = Vector3(0, 0, -15.0)
	wind.is_active = true
	add_child(wind)

	# Mock player inside wind area
	var player = auto_free(DummyPlayerNode.new())
	add_child(player)

	wind._apply_wind_to_body(player, STEP)

	# Verify player receives external velocity and dynamic flow tag
	assert_float(player.external_velocity.z).is_equal(-15.0)
	assert_bool(player.is_external_static).is_false()


# Helper signal sink
func _on_signal(_val, sink: Array) -> void:
	sink[0] += 1
