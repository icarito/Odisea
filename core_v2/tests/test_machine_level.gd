extends GdUnitTestSuite

# FD-320: el cargador de niveles por datos (MachineLevel) arma escenas desde un layout JSON.
# Esta suite cubre build(), get_item(), export_layout(), save/load y los links con "delay".

const MachineLevel = preload("res://core_v2/props/machines/MachineLevel.gd")

const LAYOUT_PATH := "user://test_machine_level.json"


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "MachineLevelRoot"
	root.translation = Vector3(5000.0, 5000.0, 5000.0)
	get_tree().root.add_child(root)
	return root


func _new_level(root: Node, level_name: String):
	var level = MachineLevel.new()
	level.name = level_name
	root.add_child(level)
	return level


func _settle(frames: int) -> void:
	for _i in range(frames):
		yield(get_tree(), "physics_frame")


func _find_item(items: Array, item_name: String):
	for it in items:
		if str((it as Dictionary).get("name", "")) == item_name:
			return it
	return null


func test_build_creates_block_part_and_hinge() -> void:
	var root := _setup_root()
	var level = _new_level(root, "BuildLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "pos": [0, 0, 0], "size": [1, 1, 1]},
		{"type": "part", "name": "Part", "pos": [2, 0, 0], "size": [2, 1, 3], "density": 100.0},
		{"type": "hinge", "name": "Hinge", "pos": [2, 1, 0], "a": "Part"},
	]})
	var block = level.get_item("Block")
	var part = level.get_item("Part")
	var hinge = level.get_item("Hinge")
	assert_object(block).is_not_null()
	assert_bool(block is StaticBody).is_true()
	assert_object(part).is_not_null()
	assert_object(hinge).is_not_null()
	assert_vector3(part.size).is_equal(Vector3(2, 1, 3))
	assert_float(part.mass).is_equal_approx(600.0, 0.01)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_unknown_item_type_is_ignored() -> void:
	var root := _setup_root()
	var level = _new_level(root, "UnknownLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "size": [1, 1, 1]},
		{"type": "banana", "name": "Weird"},
	]})
	assert_object(level.get_item("Weird")).is_null()
	assert_object(level.get_item("Block")).is_not_null()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_link_with_delay_releases_part() -> void:
	var root := _setup_root()
	var level = _new_level(root, "DelayLevel")
	level.build({"items": [
		{"type": "scene", "name": "Lever", "pos": [0, 0, 0], "path": "res://core_v2/props/controls/LeverV2.tscn"},
		{"type": "part", "name": "Door", "pos": [3, 1, 0], "size": [1, 1, 1], "density": 100.0, "held": true},
		{"type": "link", "from": "Lever", "signal": "activated", "to": "Door", "method": "set_active", "args": [true], "delay": 0.5},
	]})
	var lever = level.get_item("Lever")
	var door = level.get_item("Door")
	assert_object(lever).is_not_null()
	assert_object(door).is_not_null()
	assert_int(door.mode).is_equal(RigidBody.MODE_STATIC)
	lever.interact()
	# Antes de que dispare el link (animacion + delay): sigue retenida.
	yield(_settle(30), "completed")
	assert_int(door.mode).is_equal(RigidBody.MODE_STATIC)
	# Con margen suficiente para animacion + 30 ticks de delay.
	yield(_settle(240), "completed")
	assert_int(door.mode).is_equal(RigidBody.MODE_RIGID)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_layout_round_trip_preserves_items_and_positions() -> void:
	var root := _setup_root()
	var level = _new_level(root, "SaveLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "pos": [1, 2, 3], "size": [1, 1, 1]},
		{"type": "part", "name": "Part", "pos": [-2, 0.5, 4], "size": [2, 1, 3], "density": 80.0, "held": true},
	]})
	assert_bool(level.save_layout_file(LAYOUT_PATH)).is_true()
	var level2 = _new_level(root, "LoadLevel")
	assert_bool(level2.load_layout_file(LAYOUT_PATH)).is_true()
	for item_name in ["Block", "Part"]:
		var original = level.get_item(item_name)
		var loaded = level2.get_item(item_name)
		assert_object(loaded).is_not_null()
		assert_vector3(loaded.translation).is_equal_approx(original.translation, Vector3(0.01, 0.01, 0.01))
	var dir := Directory.new()
	dir.remove(LAYOUT_PATH)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_export_layout_reflects_moved_piece() -> void:
	var root := _setup_root()
	var level = _new_level(root, "ExportLevel")
	level.build({"items": [
		{"type": "part", "name": "Part", "pos": [0, 0, 0], "size": [1, 1, 1], "density": 100.0, "held": true},
	]})
	var part = level.get_item("Part")
	part.translation = Vector3(7, 8, 9)
	var layout: Dictionary = level.export_layout()
	var moved = _find_item(layout["items"], "Part")
	assert_object(moved).is_not_null()
	assert_float(moved["pos"][0]).is_equal_approx(7.0, 0.01)
	assert_float(moved["pos"][1]).is_equal_approx(8.0, 0.01)
	assert_float(moved["pos"][2]).is_equal_approx(9.0, 0.01)
	root.queue_free()
	yield(get_tree(), "idle_frame")
