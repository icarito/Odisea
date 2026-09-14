extends GdUnitTestSuite

# test_gles3_vendor_gate.gd — Contrato §11.10: Mali GLES3 ambiente conservador.

const GateScript = preload("res://core_v2/autoloads/GLES3VendorGate.gd")

func test_gate_strips_heavy_passes_when_mali_active():
	var gate = auto_free(GateScript.new())
	gate.force_vendor_gate = true
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
	gate.force_vendor_gate = false
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
