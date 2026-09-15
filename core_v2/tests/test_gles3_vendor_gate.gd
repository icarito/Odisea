extends GdUnitTestSuite

# test_gles3_vendor_gate.gd — Contrato §11.10: Mali GLES3 ambiente conservador.

const GateScript = preload("res://core_v2/autoloads/GLES3VendorGate.gd")

func test_gate_strips_heavy_passes_when_known_adapter():
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)

	var env = auto_free(Environment.new())
	env.fog_enabled = true
	env.glow_enabled = true
	env.dof_blur_far_enabled = true
	env.dof_blur_near_enabled = true
	env.adjustment_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var we = auto_free(WorldEnvironment.new())
	we.environment = env
	# add_child dispara node_added: el gate debe limpiar el ambiente al vuelo.
	add_child(we)

	assert_bool(env.fog_enabled).is_false()
	assert_bool(env.glow_enabled).is_false()
	assert_bool(env.dof_blur_far_enabled).is_false()
	assert_bool(env.dof_blur_near_enabled).is_false()
	assert_bool(env.adjustment_enabled).is_false()
	assert_int(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_LINEAR)

func test_gate_leaves_environment_untouched_without_mali():
	var gate = auto_free(GateScript.new())
	gate.force_gate = false
	add_child(gate)

	var env = auto_free(Environment.new())
	env.fog_enabled = true
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var we = auto_free(WorldEnvironment.new())
	we.environment = env
	add_child(we)

	# Sin Mali (runner desktop/headless) el ambiente queda como vino: las
	# pasadas son válidas en GL de escritorio.
	assert_bool(env.fog_enabled).is_true()
	assert_bool(env.glow_enabled).is_true()
	assert_int(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_ACES)

func test_is_low_tier_follows_force_gate():
	var gate = auto_free(GateScript.new())
	gate.force_gate = false
	assert_bool(gate.is_low_tier()).is_false()
	gate.force_gate = true
	assert_bool(gate.is_low_tier()).is_true()

# Fisica a 30 Hz solo en tier LOW; fuera vuelve al valor del proyecto (desktop, CI y replays).
func test_physics_rate_follows_low_tier():
	var before: int = Engine.iterations_per_second
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	gate.sync_physics_rate()
	assert_int(Engine.iterations_per_second).is_equal(GateScript.LOW_TIER_PHYSICS_FPS)
	gate.force_gate = false
	gate.sync_physics_rate()
	assert_int(Engine.iterations_per_second).is_equal(int(ProjectSettings.get_setting("physics/common/physics_fps")))
	Engine.iterations_per_second = before

func test_low_tier_strips_shadows_and_materials():
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)

	var mat = auto_free(SpatialMaterial.new())
	mat.normal_enabled = true
	mat.rim_enabled = true
	mat.clearcoat_enabled = true
	mat.ao_enabled = true
	mat.depth_enabled = true
	mat.subsurf_scatter_enabled = true
	mat.flags_vertex_lighting = false

	var mesh = auto_free(CubeMesh.new())
	mesh.material = mat
	var mi = auto_free(MeshInstance.new())
	mi.mesh = mesh
	# add_child dispara node_added: el tier LOW debe aplanar el material.
	add_child(mi)

	assert_bool(mi.cast_shadow == GeometryInstance.SHADOW_CASTING_SETTING_OFF).is_true()
	assert_bool(mat.normal_enabled).is_false()
	assert_bool(mat.rim_enabled).is_false()
	assert_bool(mat.clearcoat_enabled).is_false()
	assert_bool(mat.ao_enabled).is_false()
	assert_bool(mat.depth_enabled).is_false()
	assert_bool(mat.subsurf_scatter_enabled).is_false()
	assert_bool(mat.flags_vertex_lighting).is_true()

func test_low_tier_disables_light_shadows():
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)

	var light = auto_free(DirectionalLight.new())
	light.shadow_enabled = true
	add_child(light)

	assert_bool(light.shadow_enabled).is_false()

func test_low_tier_frees_lowend_skip_group():
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)

	var deco = auto_free(Spatial.new())
	deco.add_to_group("lowend_skip", true)
	add_child(deco)

	assert_bool(deco.is_queued_for_deletion()).is_true()

func test_untouched_nodes_keep_shadows_without_gate():
	var gate = auto_free(GateScript.new())
	gate.force_gate = false
	add_child(gate)

	var light = auto_free(DirectionalLight.new())
	light.shadow_enabled = true
	var mat = auto_free(SpatialMaterial.new())
	mat.normal_enabled = true
	var mesh = auto_free(CubeMesh.new())
	mesh.material = mat
	var mi = auto_free(MeshInstance.new())
	mi.mesh = mesh
	add_child(light)
	add_child(mi)

	# Sin tier LOW, escritorio conserva sombras y materiales completos.
	assert_bool(light.shadow_enabled).is_true()
	assert_bool(mat.normal_enabled).is_true()
	assert_bool(mi.cast_shadow == GeometryInstance.SHADOW_CASTING_SETTING_OFF).is_false()
