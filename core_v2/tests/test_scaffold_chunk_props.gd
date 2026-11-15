extends GdUnitTestSuite

# Atajos de herramienta de los chunks de andamio con sus props REALES: el mamparo de
# scaffold_laser_choke es un LaserGate y el hueco de scaffold_catenary_span un GlooSpan.
# Cerrados bloquean; con la herramienta se abren.

const DIR := "res://core_v2/props/scaffold/chunks/"
const ORIGIN := Vector3(3000.0, 3000.0, -3000.0)

var _scene: Spatial = null


func _spawn(id: String) -> void:
	_scene = load(DIR + id + ".tscn").instance()
	_scene.translation = ORIGIN
	get_tree().root.add_child(_scene)


func after_test() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
	yield(get_tree(), "idle_frame")


func _ray_blocked(from_local: Vector3, to_local: Vector3) -> bool:
	var space := _scene.get_world().direct_space_state
	return not space.intersect_ray(ORIGIN + from_local, ORIGIN + to_local, [], 1).empty()


func test_laser_choke_bulkhead_blocks_until_cut() -> void:
	_spawn("scaffold_laser_choke")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	var gate: Node = _scene.get_node("Blocker_bulkhead")
	# A la altura del pecho y por encima del salto maximo: el paso recto esta cerrado.
	assert_bool(_ray_blocked(Vector3(0.0, 1.0, 4.0), Vector3(0.0, 1.0, 8.0))).is_true()
	assert_bool(_ray_blocked(Vector3(0.0, 3.9, 4.0), Vector3(0.0, 3.9, 8.0))).is_true()
	assert_bool(gate.is_opened()).is_false()
	# El laser del multi-tool llama laser_hit() una vez por tick mientras apunta.
	for _i in range(int(gate.cut_time * 60.0) + 2):
		gate.laser_hit()
	assert_bool(gate.is_opened()).is_true()
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	assert_bool(_ray_blocked(Vector3(0.0, 1.0, 4.0), Vector3(0.0, 1.0, 8.0))).is_false()


func test_catenary_gap_is_bridged_by_gloo() -> void:
	_spawn("scaffold_catenary_span")
	yield(get_tree(), "physics_frame")
	var span: Node = _scene.get_node("Span_gloo_bridge")
	assert_bool(span.is_opened()).is_false()
	# Hay hueco: nada que pisar a media luz.
	assert_bool(_ray_blocked(Vector3(0.0, 1.0, 6.0), Vector3(0.0, -1.0, 6.0))).is_false()
	# Blobs de gloo (grupo publico del multi-tool) pegados dentro del tramo.
	for i in range(int(span.required_blobs)):
		var blob := Spatial.new()
		blob.add_to_group("gloo_blob")
		_scene.add_child(blob)
		blob.translation = Vector3(0.0, 0.2, 3.0 + float(i) * 2.0)
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	assert_bool(span.is_opened()).is_true()
	var bridge: StaticBody = span.get_node("GlooSpanPlatform")
	bridge.collision_layer = 1 | 64
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	# La pasarela curada cubre el hueco a la altura de las plataformas.
	assert_bool(_ray_blocked(Vector3(0.0, 1.0, 6.0), Vector3(0.0, -1.0, 6.0))).is_true()
	assert_float(abs(span.global_transform.origin.y - ORIGIN.y)).is_less(0.05)
