extends GdUnitTestSuite

# FD-320 pulido: streaming por estación del MachineLevel. Un chunk de proximidad por
# "station" (>0): la estación del jugador (± vecina) queda activa; el resto apaga
# visible/colisión/proceso y sus cuerpos rígidos quedan dormidos en MODE_STATIC.
# Headless-safe: no mide render, verifica el estado lógico y de colisión.

const MachineLevel = preload("res://core_v2/props/machines/MachineLevel.gd")


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "MachineStreamRoot"
	root.translation = Vector3(5000.0, 5000.0, 5000.0)
	get_tree().root.add_child(root)
	return root


func _layout() -> Dictionary:
	# Dos estaciones separadas 40 m: con radio ~10 + margen 14, cada una está fuera
	# del alcance de la otra.
	return {"items": [
		{"type": "block", "name": "Shell", "pos": [0, 0, 0], "size": [1, 1, 1]},
		{"type": "part", "name": "ArmA", "pos": [0, 0, 20], "size": [2, 0.2, 1], "density": 100.0, "station": 1},
		{"type": "part", "name": "ArmB", "pos": [0, 0, 60], "size": [2, 0.2, 1], "density": 100.0, "station": 2},
	]}


func test_streaming_creates_one_chunk_per_station_and_toggles_by_distance() -> void:
	var root := _setup_root()
	var level = MachineLevel.new()
	level.name = "StreamLevel"
	level.enable_station_streaming = true
	level.station_stream_margin = 14.0
	root.add_child(level)
	level.build(_layout())

	# Un chunk por estación (>0), no por item; la station 0 (shell) no se toca.
	assert_array(level.get_station_ids()).is_equal([0, 1, 2])
	assert_object(level.get_station_streamer()).is_not_null()
	assert_int(level.get_station_streamer().get_chunk_count()).is_equal(2)

	var player := Spatial.new()
	player.name = "StreamPlayer"
	level.add_child(player)
	player.add_to_group("player")
	player.translation = Vector3(0.0, 0.0, 20.0)
	level.get_station_streamer().player = player
	var arm_a = level.get_item("ArmA")
	var arm_b = level.get_item("ArmB")
	var shell = level.get_item("Shell")

	level.get_station_streamer().refresh()
	assert_bool(arm_a.visible).is_true()
	assert_bool(arm_b.visible).is_false()
	# El cuerpo fuera de área queda dormido y sin colisión.
	assert_int(arm_b.mode).is_equal(RigidBody.MODE_STATIC)
	assert_int(arm_b.collision_layer).is_equal(0)
	# El shell (station 0) nunca se apaga.
	assert_bool(shell.visible).is_true()

	# Viajar a la estación 2 invierte el estado sin rearmar nada.
	player.translation = Vector3(0.0, 0.0, 60.0)
	level.get_station_streamer().refresh()
	assert_bool(arm_a.visible).is_false()
	assert_bool(arm_b.visible).is_true()
	assert_int(arm_a.collision_layer).is_equal(0)

	# Desactivar el streaming reactiva todo.
	level.set_station_streaming_enabled(false)
	assert_bool(arm_a.visible).is_true()
	assert_bool(arm_b.visible).is_true()
	assert_int(arm_a.collision_layer).is_not_equal(0)

	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_cut_part_reactivates_hidden() -> void:
	var root := _setup_root()
	var level = MachineLevel.new()
	level.name = "StreamCutLevel"
	level.enable_station_streaming = true
	level.station_stream_margin = 5.0
	root.add_child(level)
	level.build({"items": [
		{"type": "part", "name": "Strut", "pos": [0, 2, 0], "size": [0.4, 1, 0.4],
			"cuttable": true, "cut_time": 0.2, "station": 1},
		{"type": "part", "name": "Far", "pos": [0, 2, 80], "size": [1, 1, 1], "station": 2},
	]})
	var player := Spatial.new()
	player.add_to_group("player")
	level.add_child(player)
	player.translation = Vector3(0.0, 0.0, 0.0)
	level.get_station_streamer().player = player
	var strut = level.get_item("Strut")
	# Cortar y luego apagar/encender el área: debe volver cortado, no visible.
	strut.cut_now()
	level.get_station_streamer().refresh()
	assert_bool(strut.is_cut()).is_true()
	# Alejar (desactiva station 1) y volver (reactiva): conserva el corte.
	player.translation = Vector3(0.0, 0.0, 60.0)
	level.get_station_streamer().refresh()
	player.translation = Vector3(0.0, 0.0, 0.0)
	level.get_station_streamer().refresh()
	assert_bool(strut.is_cut()).is_true()
	assert_bool(strut.visible).is_false()

	root.queue_free()
	yield(get_tree(), "idle_frame")
