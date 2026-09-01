extends GdUnitTestSuite

const LightSwitchScene := preload("res://core_v2/props/controls/LightSwitchV2.tscn")
const LightGroupScript := preload("res://core_v2/components/LightGroup.gd")
const SciFiStaticLightScene := preload("res://core_v2/props/scifi_lights/SciFiStaticLightV2.tscn")

func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_light_switch_interact_and_animation() -> void:
	var host = _scene_host()
	var switch: LightSwitchV2 = auto_free(LightSwitchScene.instance())
	host.add_child(switch)
	yield(get_tree(), "idle_frame")

	assert_str(switch.interaction_text).is_equal("accionar")
	assert_bool(switch.is_active).is_false()
	assert_float(switch.anim_progress).is_equal(0.0)

	var activated_emitted := [false]
	var deactivated_emitted := [false]
	switch.connect("activated", self, "_on_activated", [activated_emitted])
	switch.connect("deactivated", self, "_on_deactivated", [deactivated_emitted])

	# Interact to activate
	switch.interact()
	assert_bool(switch.is_active).is_true()

	# Step physics animation to completion
	switch.step(1.0)
	assert_float(switch.anim_progress).is_equal(1.0)
	assert_bool(activated_emitted[0]).is_true()
	assert_bool(deactivated_emitted[0]).is_false()

	# Interact to deactivate
	activated_emitted[0] = false
	switch.interact()
	assert_bool(switch.is_active).is_false()

	switch.step(1.0)
	assert_float(switch.anim_progress).is_equal(0.0)
	assert_bool(deactivated_emitted[0]).is_true()

func test_light_group_explicit_light_paths_propagation() -> void:
	var host = _scene_host()
	var switch: LightSwitchV2 = auto_free(LightSwitchScene.instance())
	var light1: SciFiStaticLightV2 = auto_free(SciFiStaticLightScene.instance())
	var light2: SciFiStaticLightV2 = auto_free(SciFiStaticLightScene.instance())
	var group: LightGroup = auto_free(LightGroupScript.new())

	host.add_child(switch)
	host.add_child(light1)
	host.add_child(light2)

	group.switch_path = switch.get_path()
	group.light_paths = [light1.get_path(), light2.get_path()]
	host.add_child(group)

	yield(get_tree(), "idle_frame")

	# Initial state propagation
	assert_bool(light1.is_active).is_false()
	assert_bool(light2.is_active).is_false()

	# Toggle switch -> ON
	switch.interact()
	switch.step(1.0)

	assert_bool(light1.is_active).is_true()
	assert_bool(light2.is_active).is_true()

	# Toggle switch -> OFF
	switch.interact()
	switch.step(1.0)

	assert_bool(light1.is_active).is_false()
	assert_bool(light2.is_active).is_false()

func test_light_group_scene_group_propagation() -> void:
	var host = _scene_host()
	var switch: LightSwitchV2 = auto_free(LightSwitchScene.instance())
	var light1: SciFiStaticLightV2 = auto_free(SciFiStaticLightScene.instance())
	var light2: SciFiStaticLightV2 = auto_free(SciFiStaticLightScene.instance())
	var group: LightGroup = auto_free(LightGroupScript.new())

	light1.add_to_group("dome_test_lights")
	light2.add_to_group("dome_test_lights")

	host.add_child(switch)
	host.add_child(light1)
	host.add_child(light2)

	group.switch_path = switch.get_path()
	group.scene_group = "dome_test_lights"
	host.add_child(group)

	yield(get_tree(), "idle_frame")

	# Toggle switch -> ON
	switch.interact()
	switch.step(1.0)

	assert_bool(light1.is_active).is_true()
	assert_bool(light2.is_active).is_true()

	# Toggle switch -> OFF
	switch.interact()
	switch.step(1.0)

	assert_bool(light1.is_active).is_false()
	assert_bool(light2.is_active).is_false()

func test_light_group_plain_light_support() -> void:
	var host = _scene_host()
	var switch: LightSwitchV2 = auto_free(LightSwitchScene.instance())
	var plain_light: OmniLight = auto_free(OmniLight.new())
	var group: LightGroup = auto_free(LightGroupScript.new())

	host.add_child(switch)
	host.add_child(plain_light)

	group.switch_path = switch.get_path()
	group.light_paths = [plain_light.get_path()]
	host.add_child(group)

	yield(get_tree(), "idle_frame")

	# Switch initial state is false -> plain light visible is false
	assert_bool(plain_light.visible).is_false()

	# Activate switch
	switch.interact()
	switch.step(1.0)
	assert_bool(plain_light.visible).is_true()

	# Deactivate switch
	switch.interact()
	switch.step(1.0)
	assert_bool(plain_light.visible).is_false()

func test_light_switch_and_group_determinism_snapshots() -> void:
	var host = _scene_host()
	var switch: LightSwitchV2 = auto_free(LightSwitchScene.instance())
	var light: SciFiStaticLightV2 = auto_free(SciFiStaticLightScene.instance())
	var group: LightGroup = auto_free(LightGroupScript.new())

	host.add_child(switch)
	host.add_child(light)

	group.switch_path = switch.get_path()
	group.light_paths = [light.get_path()]
	host.add_child(group)

	yield(get_tree(), "idle_frame")

	# Set switch active and step animation
	switch.set_active(true, true)
	assert_bool(switch.is_active).is_true()

	var switch_snap = switch.get_snapshot()
	assert_bool(switch_snap.get("active", false)).is_true()

	var group_snap = group.get_snapshot()
	assert_bool(group_snap.get("switch_active", false)).is_true()

	# Reset switch & group to false state
	switch.set_active(false, true)
	assert_bool(switch.is_active).is_false()

	# Restore snapshot on group & switch
	group.restore_snapshot(group_snap)
	assert_bool(switch.is_active).is_true()
	assert_bool(light.is_active).is_true()

func _on_activated(state: Array) -> void:
	state[0] = true

func _on_deactivated(state: Array) -> void:
	state[0] = true
