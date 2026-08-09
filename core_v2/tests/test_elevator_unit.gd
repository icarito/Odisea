extends GdUnitTestSuite

func test_elevator_platform_move_to_sets_target():
	var platform = preload("res://core_v2/components/ElevatorPlatform.gd").new()
	platform.set_script(load("res://core_v2/components/ElevatorPlatform.gd"))
	
	platform.target_height = 0.0
	platform.is_moving = false
	
	platform.move_to(5.0)
	
	assert_float(platform.target_height).is_equal(5.0)
	assert_bool(platform.is_moving).is_true()
	
	platform.free()

func test_elevator_carries_player_directly_only_while_moving() -> void:
	var host := Spatial.new()
	add_child(host)
	var platform = preload("res://core_v2/components/ElevatorPlatform.gd").new()
	host.add_child(platform)
	var player := KinematicBody.new()
	player.set_script(load("res://core_v2/tests/helpers/StandInPlayer.gd"))
	host.add_child(player)

	platform._grab_player(player)
	assert_object(player.get_parent()).is_same(platform)
	assert_bool(platform.is_in_group("player_carrier")).is_true()

	platform._release_player_passengers()
	assert_object(player.get_parent()).is_same(host)
	host.free()

func test_elevator_controller_request_queues_floor():
	var controller = preload("res://core_v2/props/ElevatorController.gd").new()
	controller.set_script(load("res://core_v2/props/ElevatorController.gd"))
	
	controller.requests = []
	controller.current_floor = 0
	controller.is_moving = false
	
	controller._on_floor_request(1)
	
	assert_array(controller.requests).contains([1])
	
	controller.free()


# Each landing's call button owns its own indicator material. _sync_floors clones
# the template floor with Node.duplicate(), which shares resources, so all six
# landings used to light up together; and once the button moved to the prop layer
# PropDitherManager swapped its SpatialMaterial for the dither shader, after which
# none of them lit at all.
func test_landing_buttons_light_independently():
	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	elevator.floor_heights = [0.0, 4.6, 9.1]
	add_child(elevator)
	yield(await_idle_frame(), "completed")

	var buttons := []
	for stop in elevator.get_node("Floors").get_children():
		var button = stop.get_node_or_null("Input/PedestalButton")
		assert_object(button).is_not_null()
		buttons.append(button)
	assert_int(buttons.size()).is_equal(3)

	buttons[1].set_active(true, true)

	var lit := []
	for i in range(buttons.size()):
		var mesh = buttons[i].get_node("ButtonMesh")
		var mat = mesh.material_override
		assert_object(mat) \
			.override_failure_message("button %d lost its SpatialMaterial to the dither shader" % i) \
			.is_instanceof(SpatialMaterial)
		if mat.albedo_color.g > mat.albedo_color.r:
			lit.append(i)
	assert_array(lit) \
		.override_failure_message("only the pressed landing should be green, got %s" % [lit]) \
		.is_equal([1])


# The camera's spring arm masks layers 1 and 8 (PlayerControllerV2.camera_collision_mask
# = 129), and PropDitherManager only fades bodies carrying layer 7. So a shaft
# fitting left on layer 1 does both wrong things at once: it shoves the camera
# around inside the car and stays opaque between the camera and the player. The
# pedestal buttons and the door leaves were exactly that.
const PROP_LAYER := 64

func test_every_elevator_body_is_on_the_prop_layer():
	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	elevator.floor_heights = [0.0, 4.6, 9.1]
	add_child(elevator)
	yield(await_idle_frame(), "completed")

	var offenders := []
	_collect_non_prop_bodies(elevator, "ElevatorProp", offenders)
	assert_array(offenders) \
		.override_failure_message("bodies off the prop layer: %s" % [offenders]) \
		.is_empty()


# Areas are deliberately not checked: a SpringArm casts against physics bodies
# only, so an Area on any layer neither blocks the camera nor dithers.
func _collect_non_prop_bodies(node: Node, path: String, offenders: Array) -> void:
	if node is PhysicsBody and not (node.collision_layer & PROP_LAYER):
		offenders.append("%s (layer=%d)" % [path, node.collision_layer])
	for child in node.get_children():
		_collect_non_prop_bodies(child, path + "/" + child.name, offenders)


# Being on the prop layer is only half of falling into the occlusion dither: the
# manager walked MeshInstances only, so the shaft's CSG pieces — the header above
# every landing door, the cabin deck, the shaft cap — stayed solid between camera
# and player while the fences around them faded.
func test_the_shaft_falls_into_the_occlusion_dither():
	var dither = get_node_or_null("/root/PropDitherManager")
	if dither == null:
		return # Autoload absent; nothing to assert against.

	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	elevator.floor_heights = [0.0, 4.6, 9.1]
	add_child(elevator)
	for _i in range(8):
		yield(await_idle_frame(), "completed")

	var solid := []
	_collect_undithered(elevator, solid)
	# The indicator lamp is in no_occlusion on purpose (it has to keep changing
	# colour), and the projector strip is transparent without a scissor, which the
	# manager rejects by itself. Anything else solid is a hole in the effect.
	for name in solid:
		assert_bool(name in ["ButtonMesh", "ProjectorMesh"]) \
			.override_failure_message("'%s' stays solid; whole list: %s" % [name, solid]) \
			.is_true()


func test_metal_fence_grid_shader_supports_prop_occlusion() -> void:
	var elevator = auto_free(preload("res://core_v2/props/machinery/ElevatorProp.tscn").instance())
	add_child(elevator)
	for _i in range(4):
		yield(await_idle_frame(), "completed")

	var panels: Array = []
	_collect_named_meshes(elevator.get_node("MetalFence"), "FencePanel", panels)
	var checked := 0
	for panel in panels:
		var material = panel.material_override
		assert_bool(material is ShaderMaterial).is_true()
		assert_bool(PropDitherManager._is_occlusion_shader(material.shader)).is_true()
		checked += 1
	assert_int(checked).is_greater(0)

	var doors: Array = []
	_collect_nodes_by_name(elevator, ["ShaftFence", "FencePanel"], doors)
	for mesh in doors:
		var door_material = mesh.material_override
		if door_material == null:
			door_material = mesh.get_surface_material(0)
		assert_bool(door_material is ShaderMaterial).is_true()
		assert_bool(PropDitherManager._is_occlusion_shader(door_material.shader)).is_true()


func _collect_named_meshes(node: Node, marker: String, out: Array) -> void:
	if node is MeshInstance and node.name.find(marker) >= 0:
		out.append(node)
	for child in node.get_children():
		_collect_named_meshes(child, marker, out)


func _collect_nodes_by_name(node: Node, names: Array, out: Array) -> void:
	if node is MeshInstance and node.name in names:
		out.append(node)
	for child in node.get_children():
		_collect_nodes_by_name(child, names, out)


func _collect_undithered(node: Node, out: Array) -> void:
	if node is VisualInstance:
		var cls := node.get_class()
		if cls == "MeshInstance" or cls.begins_with("CSG"):
			var mat = node.get("material_override")
			if mat == null and node.has_method("get_surface_material"):
				mat = node.get_surface_material(0)
			if mat == null:
				mat = node.get("material")
			if mat != null and not (mat is ShaderMaterial):
				out.append(node.name)
	for child in node.get_children():
		_collect_undithered(child, out)
