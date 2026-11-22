extends GdUnitTestSuite

# FD-323 Fase 0 B — campo de espirales del cilindro.
# Geometría estática en marco canónico Z, colisión horneada, pool de detalle
# determinista y anclajes declarativos en DomeRegistry.

const DomeSpiralFieldScript = preload("res://core_v2/components/DomeSpiralField.gd")
const DomeSpiralFieldResourceScript = preload(
	"res://core_v2/components/DomeSpiralFieldResource.gd"
)

const HALF_HEIGHT := 4000.0

func _default_config() -> Dictionary:
	return DomeSpiralFieldResourceScript.default_spiral_config()

func _make_field(configs: Array = []) -> Spatial:
	var field = auto_free(DomeSpiralFieldScript.new())
	if not configs.empty():
		field.spirals = configs
	add_child(field)
	return field

func _is_plate_ordered(entries: Array) -> bool:
	for index in range(1, entries.size()):
		var previous: Dictionary = entries[index - 1]
		var current: Dictionary = entries[index]
		var previous_spiral: int = int(previous["spiral_index"])
		var current_spiral: int = int(current["spiral_index"])
		if previous_spiral > current_spiral:
			return false
		if previous_spiral == current_spiral:
			if int(previous["plate_index"]) >= int(current["plate_index"]):
				return false
	return true

func test_plate_transform_is_pure_and_canonical() -> void:
	var spiral := _default_config()
	var count: int = DomeSpiralFieldScript.plate_count_for(spiral)
	assert_int(count).is_equal(200)

	for i in range(count):
		var tx: Transform = DomeSpiralFieldScript.plate_transform(spiral, i)
		var repeated: Transform = DomeSpiralFieldScript.plate_transform(spiral, i)
		assert_bool(tx.is_equal_approx(repeated)).is_true()
		assert_float(abs(tx.origin.z)).is_less_equal(HALF_HEIGHT + 0.001)
		var radius: float = Vector2(tx.origin.x, tx.origin.y).length()
		assert_float(radius).is_between(220.0 - 0.001, 260.0 + 0.001)
		var expected_up: Vector3 = -Vector3(tx.origin.x, tx.origin.y, 0.0).normalized()
		assert_vector3(tx.basis.y).is_equal_approx(
			expected_up, Vector3(0.0001, 0.0001, 0.0001)
		)
		assert_float(tx.basis.determinant()).is_equal_approx(1.0, 0.0001)
		assert_float(tx.basis.z.dot(Vector3(0.0, 0.0, 1.0))).is_equal_approx(1.0, 0.0001)

	var first: Transform = DomeSpiralFieldScript.plate_transform(spiral, 0)
	var last: Transform = DomeSpiralFieldScript.plate_transform(spiral, count - 1)
	assert_float(first.origin.z).is_equal_approx(-HALF_HEIGHT, 0.001)
	assert_float(last.origin.z).is_equal_approx(-HALF_HEIGHT + 199.0 * 40.0, 0.001)
	assert_float(Vector2(first.origin.x, first.origin.y).length()).is_equal_approx(220.0, 0.001)
	assert_float(Vector2(last.origin.x, last.origin.y).length()).is_equal_approx(260.0, 0.001)

func test_collision_is_one_static_body_per_spiral_and_never_rewritten() -> void:
	var config := _default_config()
	var field := _make_field([config, config])
	assert_int(field.get_spiral_count()).is_equal(2)
	assert_int(field._collision_root.get_child_count()).is_equal(2)

	for spiral_index in range(2):
		var body: StaticBody = field.get_collision_body(spiral_index)
		assert_object(body).is_not_null()
		assert_int(body.get_child_count()).is_equal(200)
		for plate_index in range(body.get_child_count()):
			var collision := body.get_child(plate_index) as CollisionShape
			assert_object(collision).is_not_null()
			assert_bool(collision.shape is BoxShape).is_true()
			var expected: Transform = DomeSpiralFieldScript.plate_transform(
				config, plate_index
			)
			assert_bool(collision.transform.is_equal_approx(expected)).is_true()

	var recorded: Array = []
	var first_body: StaticBody = field.get_collision_body(0)
	for child in first_body.get_children():
		recorded.append((child as CollisionShape).transform)
	for _tick in range(25):
		field._physics_process(0.016)
	for plate_index in range(recorded.size()):
		var current: Transform = (first_body.get_child(plate_index) as CollisionShape).transform
		var before: Transform = recorded[plate_index]
		assert_bool(current.is_equal_approx(before)).is_true()

func test_detail_pool_selects_closest_plates_deterministically() -> void:
	var field := _make_field()
	var selection: Array = field.select_closest_plates(Vector3.ZERO, 4)
	assert_int(selection.size()).is_equal(4)
	assert_bool(_is_plate_ordered(selection)).is_true()
	for entry in selection:
		assert_int(int(entry["spiral_index"])).is_equal(0)

	# El conjunto sigue siendo el de las K placas más cercanas; sólo cambió el
	# orden de los slots a (spiral_index, plate_index).
	var spiral: Dictionary = field.get_spiral_configs()[0]
	var selected := {}
	var max_selected_distance: float = 0.0
	for entry in selection:
		selected[int(entry["plate_index"])] = true
		max_selected_distance = max(max_selected_distance, float(entry["distance"]))
	for plate_index in range(DomeSpiralFieldScript.plate_count_for(spiral)):
		if selected.has(plate_index):
			continue
		var origin: Vector3 = DomeSpiralFieldScript.plate_transform(spiral, plate_index).origin
		assert_float(origin.distance_to(Vector3.ZERO)).is_greater_equal(
			max_selected_distance - 0.0001
		)

	var repeated: Array = field.select_closest_plates(Vector3.ZERO, 4)
	for i in range(selection.size()):
		assert_int(int(repeated[i]["spiral_index"])).is_equal(
			int(selection[i]["spiral_index"])
		)
		assert_int(int(repeated[i]["plate_index"])).is_equal(
			int(selection[i]["plate_index"])
		)

	var pool_selection: Array = field.get_detail_selection()
	var slots: Array = field.get_detail_slots()
	assert_int(pool_selection.size()).is_equal(8)
	assert_int(slots.size()).is_equal(8)
	assert_bool(_is_plate_ordered(pool_selection)).is_true()
	for slot_index in range(pool_selection.size()):
		var selected_slot: Dictionary = pool_selection[slot_index]
		var expected: Transform = DomeSpiralFieldScript.plate_transform(
			spiral, int(selected_slot["plate_index"])
		)
		var slot: Spatial = slots[slot_index]
		assert_bool(slot.transform.is_equal_approx(expected)).is_true()
		assert_int(int(slot.get_meta("spiral_index"))).is_equal(
			int(selected_slot["spiral_index"])
		)
		assert_int(int(slot.get_meta("plate_index"))).is_equal(
			int(selected_slot["plate_index"])
		)

func test_detail_selection_orders_slots_by_spiral_and_plate() -> void:
	var config := _default_config()
	var field := _make_field([config, config])
	var reference: Vector3 = DomeSpiralFieldScript.plate_transform(config, 100).origin
	var selection: Array = field.select_closest_plates(reference, 8)
	assert_int(selection.size()).is_equal(8)
	assert_bool(_is_plate_ordered(selection)).is_true()

	# El empate exacto en distancia no debe perder la placa de ninguna espiral.
	var zero_distance_entries: int = 0
	for entry in selection:
		if float(entry["distance"]) < 0.0001:
			zero_distance_entries += 1
	assert_int(zero_distance_entries).is_equal(2)

	var repeated: Array = field.select_closest_plates(reference, 8)
	for i in range(selection.size()):
		assert_int(int(repeated[i]["spiral_index"])).is_equal(
			int(selection[i]["spiral_index"])
		)
		assert_int(int(repeated[i]["plate_index"])).is_equal(
			int(selection[i]["plate_index"])
		)

func test_detail_pool_recalculates_only_every_n_ticks() -> void:
	var field := _make_field()
	var revision: int = field.get_detail_pool_revision()
	assert_int(revision).is_greater_equal(1)
	for _tick in range(field.detail_update_interval_ticks - 1):
		field._physics_process(0.016)
	assert_int(field.get_detail_pool_revision()).is_equal(revision)
	field._physics_process(0.016)
	assert_int(field.get_detail_pool_revision()).is_equal(revision + 1)

func test_multimesh_visual_is_baked_from_plate_transform() -> void:
	var field := _make_field()
	var multimesh: MultiMesh = field.get_plate_multimesh(0)
	assert_object(multimesh).is_not_null()
	assert_object(multimesh.mesh).is_not_null()
	var spiral: Dictionary = field.get_spiral_configs()[0]
	# El backend headless no conserva los transforms del MultiMesh: el cache
	# horneado es la fuente de verdad que se cargó en el visual.
	var baked: Array = field.get_baked_plate_transforms(0)
	assert_int(multimesh.instance_count).is_equal(200)
	assert_int(baked.size()).is_equal(multimesh.instance_count)

	var recorded: Array = []
	for plate_index in range(baked.size()):
		var expected: Transform = DomeSpiralFieldScript.plate_transform(
			spiral, plate_index
		)
		var actual: Transform = baked[plate_index]
		assert_bool(actual.is_equal_approx(expected)).is_true()
		recorded.append(actual)

	for _tick in range(25):
		field._physics_process(0.016)
	var after: Array = field.get_baked_plate_transforms(0)
	for plate_index in range(recorded.size()):
		var current: Transform = after[plate_index]
		var before: Transform = recorded[plate_index]
		assert_bool(current.is_equal_approx(before)).is_true()

func test_registry_anchors_are_valid_transforms() -> void:
	var dome_ids: Array = DomeRegistry.get_all_dome_ids()
	assert_array(dome_ids).is_not_empty()
	for dome_id in dome_ids:
		var anchors: Array = DomeRegistry.get_anchors(String(dome_id))
		assert_array(anchors).is_not_empty()
		for anchor in anchors:
			assert_int(typeof(anchor)).is_equal(TYPE_TRANSFORM)

	var synthetic: Array = DomeRegistry.get_anchors("dome_s03_p017")
	assert_array(synthetic).is_not_empty()
	for anchor in synthetic:
		assert_int(typeof(anchor)).is_equal(TYPE_TRANSFORM)

func test_dome_lod_entries_derive_from_plate_transform() -> void:
	var field := _make_field()
	var entries: Array = field.get_dome_lod_entries()
	assert_array(entries).is_not_empty()
	for entry in entries:
		var configs: Array = field.get_spiral_configs()
		var spiral_index: int = int(entry["spiral_index"])
		var plate_index: int = int(entry["plate_index"])
		var expected: Transform = DomeSpiralFieldScript.plate_transform(
			configs[spiral_index], plate_index
		)
		var actual: Transform = entry["transform"]
		assert_bool(actual.is_equal_approx(expected)).is_true()

func test_plate_world_anchors_compose_plate_transform() -> void:
	var field := _make_field()
	var local_anchors: Array = [
		Transform(Basis(), Vector3(0.0, 1.0, 0.0)),
		Transform(Basis(), Vector3(2.0, 0.0, -3.0))
	]
	var anchors: Array = field.get_plate_world_anchors(0, 42, local_anchors)
	assert_int(anchors.size()).is_equal(2)
	var spiral: Dictionary = field.get_spiral_configs()[0]
	var base: Transform = DomeSpiralFieldScript.plate_transform(spiral, 42)
	for index in range(local_anchors.size()):
		var actual: Transform = anchors[index]
		var local: Transform = local_anchors[index]
		assert_bool(actual.is_equal_approx(base * local)).is_true()
	assert_array(field.get_plate_world_anchors(9, 0, local_anchors)).is_empty()

	var spoke_offset := Vector3(0.0, 0.0, 1.0)
	assert_vector3(field.get_plate_spoke_anchor(0, 42, spoke_offset)).is_equal_approx(
		base.xform(spoke_offset), Vector3(0.0001, 0.0001, 0.0001)
	)
	assert_vector3(field.get_plate_spoke_anchor(9, 0, spoke_offset)).is_equal(Vector3.ZERO)

func test_resource_normalizes_spiral_configs() -> void:
	var resource = DomeSpiralFieldResourceScript.new()
	var defaults: Array = resource.get_spiral_configs()
	assert_int(defaults.size()).is_equal(1)
	assert_float(float(defaults[0]["turns"])).is_equal(8.0)
	assert_float(float(defaults[0]["total_height"])).is_equal(8000.0)
	assert_float(float(defaults[0]["plate_step"])).is_equal(40.0)
	assert_vector3(resource.plate_size).is_equal(Vector3(200.0, 2.0, 200.0))

	resource.spirals = [{"turns": 2.0}]
	var custom: Array = resource.get_spiral_configs()
	assert_int(custom.size()).is_equal(1)
	assert_float(float(custom[0]["turns"])).is_equal(2.0)
	assert_float(float(custom[0]["total_height"])).is_equal(8000.0)
