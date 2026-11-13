extends GdUnitTestSuite

# FD-320: los carteles (tipo "sign") declaran "scale" (escalar o array de 3) en el layout.
# _place() debe re-aplicarlo DESPUES de asignar la transform de posicion/rotacion, porque
# node.transform = _calc_transform(item) pisa el scale que fija _make_sign. El bug dejaba a
# SignStation1 en (1,1,1) pese a "scale": 1.6. Esta suite cubre build() y reset_station()
# sin cargar la bahia completa ni tocar saves.

const MachineLevel = preload("res://core_v2/props/machines/MachineLevel.gd")


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "MachineSignScaleRoot"
	root.translation = Vector3(5000.0, 5000.0, 5000.0)
	get_tree().root.add_child(root)
	return root


func _new_level(root: Node, level_name: String):
	var level = MachineLevel.new()
	level.name = level_name
	root.add_child(level)
	return level


# Dos carteles de la misma estacion: uno con scale escalar y otro con scale array.
func _sign_items() -> Array:
	return [
		{"type": "sign", "name": "ScalarSign", "pos": [1.5, 2.0, -3.0], "rot": [0, 160, 0], "scale": 1.6, "station": 1},
		{"type": "sign", "name": "ArraySign", "pos": [-2.0, 0.5, 4.0], "rot": [0, 45, 0], "scale": [1.2, 0.8, 1.0], "station": 1},
	]


# La direccion de mirada (+Z local) no debe verse alterada por el scale re-aplicado.
func _assert_facing_yaw(sign_node: Spatial, yaw_deg: float) -> void:
	var rad := deg2rad(yaw_deg)
	assert_vector3(sign_node.transform.basis.z.normalized()).is_equal_approx(
		Vector3(sin(rad), 0.0, cos(rad)), Vector3(0.001, 0.001, 0.001))


func test_build_preserves_scalar_and_array_sign_scale() -> void:
	var root := _setup_root()
	var level = _new_level(root, "SignScaleBuild")
	level.build({"items": _sign_items()})
	var scalar: Spatial = level.get_item("ScalarSign")
	var array: Spatial = level.get_item("ArraySign")
	assert_object(scalar).is_not_null()
	assert_object(array).is_not_null()
	# Escalar => (f, f, 1), el mismo contrato que fijaba _make_sign antes de ser pisado.
	assert_vector3(scalar.scale).is_equal_approx(Vector3(1.6, 1.6, 1.0), Vector3(0.001, 0.001, 0.001))
	# Array => componente a componente, sin tocar Z.
	assert_vector3(array.scale).is_equal_approx(Vector3(1.2, 0.8, 1.0), Vector3(0.001, 0.001, 0.001))
	# Posicion y rotacion intactas.
	assert_vector3(scalar.translation).is_equal_approx(Vector3(1.5, 2.0, -3.0), Vector3(0.001, 0.001, 0.001))
	assert_vector3(array.translation).is_equal_approx(Vector3(-2.0, 0.5, 4.0), Vector3(0.001, 0.001, 0.001))
	_assert_facing_yaw(scalar, 160.0)
	_assert_facing_yaw(array, 45.0)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_reset_station_preserves_sign_scale_and_pose() -> void:
	var root := _setup_root()
	var level = _new_level(root, "SignScaleReset")
	level.build({"items": _sign_items()})
	var scalar: Spatial = level.get_item("ScalarSign")
	var array: Spatial = level.get_item("ArraySign")
	# Perturbar pose y escala como haria el jugador o un efecto: el rearme debe restaurar todo.
	scalar.translation = Vector3(9.0, 9.0, 9.0)
	scalar.scale = Vector3(0.1, 0.1, 0.1)
	array.rotation_degrees = Vector3(0, 90, 0)
	array.scale = Vector3.ONE
	level.reset_station(1)
	assert_vector3(scalar.scale).is_equal_approx(Vector3(1.6, 1.6, 1.0), Vector3(0.001, 0.001, 0.001))
	assert_vector3(array.scale).is_equal_approx(Vector3(1.2, 0.8, 1.0), Vector3(0.001, 0.001, 0.001))
	assert_vector3(scalar.translation).is_equal_approx(Vector3(1.5, 2.0, -3.0), Vector3(0.001, 0.001, 0.001))
	assert_vector3(array.translation).is_equal_approx(Vector3(-2.0, 0.5, 4.0), Vector3(0.001, 0.001, 0.001))
	_assert_facing_yaw(scalar, 160.0)
	_assert_facing_yaw(array, 45.0)
	root.queue_free()
	yield(get_tree(), "idle_frame")
