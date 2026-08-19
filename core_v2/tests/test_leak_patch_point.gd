extends GdUnitTestSuite

const LeakPatchPointScript := preload("res://core_v2/systems/cryo/LeakPatchPoint.gd")

class MockFlowAdapter extends Node:
	var pressurized: bool = true

	func is_pressurized_at(_node: Node) -> bool:
		return pressurized


class DummyLeak extends Node:
	signal state_changed(new_state)

	var is_sealed: bool = false
	var is_provisionally_patched: bool = false

	func seal() -> void:
		is_sealed = true

	func set_provisionally_patched(val: bool) -> void:
		is_provisionally_patched = val

	func trigger_leak() -> void:
		pass

	func reset() -> void:
		pass


func test_firm_patch_requires_zero_flow() -> void:
	var root: Node = auto_free(Node.new())
	add_child(root)

	var leak: DummyLeak = DummyLeak.new()
	leak.name = "Leak"
	root.add_child(leak)

	var adapter: MockFlowAdapter = MockFlowAdapter.new()
	adapter.name = "FlowAdapter"
	root.add_child(adapter)

	var patch_point = LeakPatchPointScript.new()
	patch_point.name = "LeakPatchPoint"
	patch_point.leak_path = leak.get_path()
	patch_point.flow_adapter_path = adapter.get_path()
	root.add_child(patch_point)

	# 1. When adapter reports pressurized = true -> provisional patch
	adapter.pressurized = true
	var result_pressurized: bool = patch_point.patch_with_gloo()
	assert_bool(result_pressurized).is_true()
	assert_bool(patch_point.is_patched()).is_true()
	assert_bool(patch_point.is_firmly_patched()).is_false()
	assert_bool(leak.is_provisionally_patched).is_true()
	assert_bool(leak.is_sealed).is_false()

	# Reset patch point state for second test
	patch_point.remove_patch()
	leak.is_sealed = false
	leak.is_provisionally_patched = false

	# 2. When adapter reports pressurized = false -> firm patch
	adapter.pressurized = false
	var result_unpressurized: bool = patch_point.patch_with_gloo()
	assert_bool(result_unpressurized).is_true()
	assert_bool(patch_point.is_patched()).is_true()
	assert_bool(patch_point.is_firmly_patched()).is_true()
	assert_bool(leak.is_sealed).is_true()
