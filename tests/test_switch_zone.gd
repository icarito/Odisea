extends SceneTree

func _init():
	print("Starting SwitchZone tests...")

	test_momentary()
	test_toggle()
	test_one_shot()
	test_requirements()
	test_active_flag()

	print("All tests passed!")
	quit()

func test_momentary():
	print("Testing MOMENTARY mode...")
	var zone = load("res://core_v2/props/zones/SwitchZone.gd").new()
	zone.switch_mode = zone.SwitchMode.MOMENTARY
	zone.is_switched_on = false

	var body = Node.new()
	body.name = "Body1"

	# Enter
	zone._on_body_entered(body)
	assert(zone.is_switched_on == true, "MOMENTARY: Should turn on when body enters")

	# Exit
	zone._on_body_exited(body)
	assert(zone.is_switched_on == false, "MOMENTARY: Should turn off when body exits")

	body.free()
	zone.free()

func test_toggle():
	print("Testing TOGGLE mode...")
	var zone = load("res://core_v2/props/zones/SwitchZone.gd").new()
	zone.switch_mode = zone.SwitchMode.TOGGLE
	zone.is_switched_on = false

	var body = Node.new()

	# Enter 1 (Toggle ON)
	zone._on_body_entered(body)
	assert(zone.is_switched_on == true, "TOGGLE: Should turn on first entry")

	# Exit 1 (No Change)
	zone._on_body_exited(body)
	assert(zone.is_switched_on == true, "TOGGLE: Should not change on exit")

	# Enter 2 (Toggle OFF)
	zone._on_body_entered(body)
	assert(zone.is_switched_on == false, "TOGGLE: Should turn off second entry")

	body.free()
	zone.free()

func test_one_shot():
	print("Testing ONE_SHOT mode...")
	var zone = load("res://core_v2/props/zones/SwitchZone.gd").new()
	zone.switch_mode = zone.SwitchMode.ONE_SHOT
	zone.is_switched_on = false
	zone.active = true

	var body = Node.new()

	# Enter
	zone._on_body_entered(body)
	assert(zone.is_switched_on == true, "ONE_SHOT: Should turn on")
	assert(zone.active == false, "ONE_SHOT: Should deactivate zone")

	# Exit (Should do nothing as inactive)
	zone._on_body_exited(body)
	assert(zone.is_switched_on == true, "ONE_SHOT: Should remain on")

	body.free()
	zone.free()

func test_requirements():
	print("Testing Requirements...")
	var zone = load("res://core_v2/props/zones/SwitchZone.gd").new()
	zone.switch_mode = zone.SwitchMode.MOMENTARY
	zone.target_groups = ["groupA", "groupB"]
	zone.require_all_groups = true

	var bodyA = Node.new()
	bodyA.add_to_group("groupA")

	var bodyB = Node.new()
	bodyB.add_to_group("groupB")

	# Enter A only
	zone._on_body_entered(bodyA)
	assert(zone.is_switched_on == false, "REQ: Should stay off with only A")

	# Enter B
	zone._on_body_entered(bodyB)
	assert(zone.is_switched_on == true, "REQ: Should turn on with A and B")

	# Exit A
	zone._on_body_exited(bodyA)
	assert(zone.is_switched_on == false, "REQ: Should turn off when A leaves")

	bodyA.free()
	bodyB.free()
	zone.free()

func test_active_flag():
	print("Testing Active Flag...")
	var zone = load("res://core_v2/props/zones/SwitchZone.gd").new()
	zone.switch_mode = zone.SwitchMode.MOMENTARY
	zone.active = true

	var body = Node.new()

	# Enter
	zone._on_body_entered(body)
	assert(zone.is_switched_on == true, "ACTIVE: Should turn on")

	# Disable
	zone.active = false
	# MOMENTARY logic checks 'are_requirements_met'. If !active, returns false.
	# But _process_switch_logic needs to be called. BaseZone emits active_changed?
	# SwitchZone connects to active_changed.
	# But manual assignment 'zone.active = false' does NOT trigger setter if accessed directly in script unless 'self.active' or setget used properly.
	# In GDScript, direct property access bypasses setter inside the class, but from outside (here) it uses setter if defined?
	# Yes, 'zone.active = false' from outside uses setter.

	# Setter emits active_changed -> _on_active_changed -> _process_switch_logic
	# _process_switch_logic calls are_requirements_met -> returns false (inactive).
	# MOMENTARY: if not req_met and is_on -> Turn OFF.

	assert(zone.is_switched_on == false, "ACTIVE: Should turn off when deactivated")

	body.free()
	zone.free()
