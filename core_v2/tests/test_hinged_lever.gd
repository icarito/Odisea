extends GdUnitTestSuite

# Props nuevos armados sobre modelos importados: la palanca de pedestal / la palanca
# industrial (HingedLeverV2) y la compuerta de esclusa (FreeAirlockDoor).
#
# Lo que importa verificar es que la pose sea funcion de anim_progress y que la bisagra
# quede quieta: el pivote de estos .glb esta en el origen del modelo, asi que un nodo
# rotado "a lo bruto" gira alrededor del piso en vez de alrededor de su eje.

const PalancaPedestalScene := preload("res://core_v2/props/controls/PalancaPedestal.tscn")
const IndustrialLeverScene := preload("res://core_v2/props/controls/IndustrialLever.tscn")
const FreeAirlockDoorScene := preload("res://core_v2/props/doors/FreeAirlockDoor.tscn")

func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_palanca_pedestal_rotates_around_its_hinge() -> void:
	yield(_assert_lever(PalancaPedestalScene), "completed")

func test_industrial_lever_rotates_around_its_hinge() -> void:
	yield(_assert_lever(IndustrialLeverScene), "completed")

func _assert_lever(scene: PackedScene) -> void:
	var host = _scene_host()
	var lever = auto_free(scene.instance())
	host.add_child(lever)
	yield(get_tree(), "idle_frame")

	var handle: Spatial = lever.get_node(lever.handle_path)
	var to_parent: Transform = handle.get_parent().global_transform.affine_inverse() * lever.global_transform
	var hinge: Vector3 = to_parent.xform(lever.hinge_origin)
	var rest: Transform = handle.transform
	# Preimagen del punto de bisagra en el espacio del propio nodo.
	var hinge_local: Vector3 = rest.affine_inverse().xform(hinge)

	var toggled := [false]
	lever.connect("lever_toggled", self, "_on_toggled", [toggled])

	lever.interact()
	assert_bool(lever.is_active).is_true()
	lever.step(10.0)
	assert_float(lever.anim_progress).is_equal(1.0)
	assert_bool(toggled[0]).is_true()

	# La palanca se movio...
	assert_bool(handle.transform.basis.is_equal_approx(rest.basis)).is_false()
	# ...pero la bisagra sigue en el mismo lugar.
	assert_float(handle.transform.xform(hinge_local).distance_to(hinge)).is_less(0.001)

	lever.interact()
	lever.step(10.0)
	assert_float(lever.anim_progress).is_equal(0.0)
	assert_bool(handle.transform.is_equal_approx(rest)).is_true()

func test_free_airlock_door_opens_and_frees_the_gap() -> void:
	var host = _scene_host()
	var door = auto_free(FreeAirlockDoorScene.instance())
	host.add_child(door)
	yield(get_tree(), "idle_frame")

	var blocker: CollisionShape = door.get_node("DoorBlocker/CollisionShape")
	var leaf: Spatial = door.get_node("AirlockDoorModel/Sketchfab_model/07305606f932475cbaf14d81da2d9920fbx/Object_2/RootNode/Left_Door")
	var closed: Transform = leaf.transform

	assert_bool(blocker.disabled).is_false()

	door.interact()
	assert_bool(door.is_active).is_true()
	door.step(10.0)
	assert_float(door.anim_progress).is_equal(1.0)

	# La animacion del .glb quedo aplicada (la hoja se corrio) y el hueco es transitable.
	assert_float(leaf.transform.origin.distance_to(closed.origin)).is_greater(0.5)
	assert_bool(blocker.disabled).is_true()

	door.interact()
	door.step(10.0)
	assert_bool(blocker.disabled).is_false()
	assert_float(leaf.transform.origin.distance_to(closed.origin)).is_less(0.001)

func _on_toggled(_is_on: bool, flag: Array) -> void:
	flag[0] = true
