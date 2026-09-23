extends GdUnitTestSuite

# test_gles3_vendor_gate.gd — Contrato §11.10: Mali GLES3 ambiente conservador.

const GateScript = preload("res://core_v2/autoloads/GLES3VendorGate.gd")

# La opcion "low end" de Opciones persiste en settings.cfg y el gate la lee del SettingsManager.
# Ese estado del usuario no puede filtrarse a los tests: un runner con low_end_forced=true haria
# fallar los casos "sin Mali el ambiente queda intacto". Se aisla y se restaura por test.
var _saved_low_end_forced := false
var _saved_low_end_present := false

func before_test() -> void:
	var sm = get_node_or_null("/root/SettingsManager")
	if sm != null and "low_end_forced" in sm:
		_saved_low_end_present = true
		_saved_low_end_forced = bool(sm.get("low_end_forced"))
		sm.set("low_end_forced", false)

func after_test() -> void:
	if _saved_low_end_present:
		var sm = get_node_or_null("/root/SettingsManager")
		if sm != null:
			sm.set("low_end_forced", _saved_low_end_forced)

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
	env.ssao_enabled = true
	env.ss_reflections_enabled = true
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
	assert_bool(env.ssao_enabled).is_false()
	assert_bool(env.ss_reflections_enabled).is_false()
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

# ODISEA_FORCE_LOW_TIER=1 es el override de desarrollo que usa
# tools/launch_game.sh --lowend para probar el tier LOW en desktop.
func test_env_override_forces_low_tier():
	var gate = auto_free(GateScript.new())
	var prev := OS.get_environment(GateScript.FORCE_LOW_TIER_ENV)

	OS.set_environment(GateScript.FORCE_LOW_TIER_ENV, "1")
	gate._env_forced_low_tier = gate._read_env_forced_low_tier()
	assert_bool(gate.is_low_tier()).is_true()

	OS.set_environment(GateScript.FORCE_LOW_TIER_ENV, "0")
	gate._env_forced_low_tier = gate._read_env_forced_low_tier()
	assert_bool(gate.is_low_tier()).is_false()

	OS.set_environment(GateScript.FORCE_LOW_TIER_ENV, prev)

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

# Un replay graba 1 frame de buffer = 1 tick de fisica; si el tier LOW se queda tickeando a
# 30 Hz durante la reproduccion, todo lo que no se stepea a mano (RigidBody/Area nativos)
# desincroniza contra el paso manual del jugador (FIXED_DT fijo a 1/60) y descarrila la
# trayectoria. set_replay_active debe forzar el rate del proyecto pese al tier LOW, y
# devolver el tier al terminar.
func test_replay_active_overrides_low_tier_physics_rate():
	var before: int = Engine.iterations_per_second
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	gate.sync_physics_rate()
	assert_int(Engine.iterations_per_second).is_equal(GateScript.LOW_TIER_PHYSICS_FPS)

	gate.set_replay_active(true)
	assert_int(Engine.iterations_per_second).is_equal(int(ProjectSettings.get_setting("physics/common/physics_fps")))

	gate.set_replay_active(false)
	assert_int(Engine.iterations_per_second).is_equal(GateScript.LOW_TIER_PHYSICS_FPS)

	gate.force_gate = false
	gate.sync_physics_rate()
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

# Los tools de horneado (tools/bake_*.gd) llaman suspend_node_mutation() antes de
# instanciar: si no, un bake corrido en tier LOW guarda los materiales COMPARTIDOS
# ya mutados (transparencia/alpha scissor apagados) y las rejillas quedan opacas
# para todos los perfiles.
func test_suspend_node_mutation_freezes_low_tier_material_changes():
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)
	gate.suspend_node_mutation()

	var mat = auto_free(SpatialMaterial.new())
	mat.flags_transparent = true
	mat.params_use_alpha_scissor = true
	mat.params_alpha_scissor_threshold = 0.46
	mat.normal_enabled = true
	mat.flags_vertex_lighting = false

	var mesh = auto_free(CubeMesh.new())
	mesh.material = mat
	var mi = auto_free(MeshInstance.new())
	mi.mesh = mesh
	add_child(mi)

	assert_bool(mat.flags_transparent).is_true()
	assert_bool(mat.params_use_alpha_scissor).is_true()
	assert_float(mat.params_alpha_scissor_threshold).is_equal_approx(0.46, 0.001)
	assert_bool(mat.normal_enabled).is_true()
	assert_bool(mat.flags_vertex_lighting).is_false()
	assert_bool(mi.cast_shadow == GeometryInstance.SHADOW_CASTING_SETTING_OFF).is_false()

func test_flat_mode_releases_the_material_override():
	# El material_override le gana a los materiales por superficie: si el modo plano
	# no lo suelta, el prop sigue dibujando el suyo (rejillas transparentes) y todo el
	# trabajo por superficie es codigo muerto.
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	# Despues de add_child: _ready() relee ODISEA_UNSHADED del entorno y pisaria esto.
	add_child(gate)
	gate._unshaded_mode = "3"

	var over = auto_free(SpatialMaterial.new())
	over.flags_transparent = true
	over.params_use_alpha_scissor = true
	var mi = auto_free(MeshInstance.new())
	mi.mesh = auto_free(CubeMesh.new())
	mi.material_override = over
	add_child(mi)

	assert_object(mi.material_override).is_null()
	assert_object(mi.get_surface_material(0)).is_not_null()
	assert_bool(mi.get_surface_material(0) is ShaderMaterial).is_true()


func test_flat_mode_keeps_double_sided_decks():
	# Las rejillas/decks de los andamios usan CULL_DISABLED y son un unico quad: al
	# hornear, el winding puede quedar hacia abajo y con cull_back el piso caminable
	# desaparece visto desde arriba (el jugador flota sobre una superficie invisible).
	# El material plano debe conservar el doble lado de la fuente.
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	add_child(gate)
	gate._unshaded_mode = "3"
	assert_bool(gate.is_flat_mode()).is_true()

	var grate = auto_free(SpatialMaterial.new())
	grate.params_cull_mode = SpatialMaterial.CULL_DISABLED
	var grate_mesh = auto_free(CubeMesh.new())
	grate_mesh.material = grate
	var grate_mi = auto_free(MeshInstance.new())
	grate_mi.mesh = grate_mesh
	add_child(grate_mi)

	var flat_deck = grate_mi.get_surface_material(0)
	assert_bool(flat_deck is ShaderMaterial).is_true()
	assert_str((flat_deck as ShaderMaterial).shader.resource_path.get_file()).is_equal("FlatFakeDoubleSided.shader")

	var frame = auto_free(SpatialMaterial.new())
	var frame_mesh = auto_free(CubeMesh.new())
	frame_mesh.material = frame
	var frame_mi = auto_free(MeshInstance.new())
	frame_mi.mesh = frame_mesh
	add_child(frame_mi)

	var flat_frame = frame_mi.get_surface_material(0)
	assert_bool(flat_frame is ShaderMaterial).is_true()
	assert_str((flat_frame as ShaderMaterial).shader.resource_path.get_file()).is_equal("FlatFake.shader")


func test_flat_mode_leaves_the_pilot_shaded():
	# Los personajes quedan fuera del modo plano: conservan su material y se ven
	# gouraud (vertex lighting) contra un mundo plano.
	var gate = auto_free(GateScript.new())
	gate.force_gate = true
	# Despues de add_child: _ready() relee ODISEA_UNSHADED del entorno y pisaria esto.
	add_child(gate)
	gate._unshaded_mode = "3"

	var mat = auto_free(SpatialMaterial.new())
	mat.flags_vertex_lighting = false
	var mesh = auto_free(CubeMesh.new())
	mesh.material = mat
	var mi = auto_free(MeshInstance.new())
	mi.name = "PilotVisual"
	mi.mesh = mesh
	add_child(mi)

	assert_object(mi.material_override).is_null()
	assert_object(mi.get_surface_material(0)).is_null()
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


# Tier LOW apaga las sombras falsas por env, antes de que las escenas las instancien.
func test_low_tier_sets_fake_shadow_off_env():
	var prev := OS.get_environment("ODISEA_DISABLE_FAKE_SHADOW")
	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", "")

	var gate = auto_free(GateScript.new())
	gate.force_gate = false
	gate._sync_low_tier_env_hints()
	assert_str(OS.get_environment("ODISEA_DISABLE_FAKE_SHADOW")).is_equal("")

	gate.force_gate = true
	gate._sync_low_tier_env_hints()
	assert_str(OS.get_environment("ODISEA_DISABLE_FAKE_SHADOW")).is_equal("1")

	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", prev)

# FD: en el perfil low-end (el mismo que enciende el modo plano) el juego arranca a 640x480
# en vez de 800x600. Es el DEFAULT, no una imposicion: una resolucion ya elegida por el
# jugador (presente en settings.cfg, o guardada desde Opciones) sobrevive intacta.
func test_low_end_profile_defaults_to_640x480():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("default_render_resolution"):
		return
	sm.set("low_end_forced", false)
	assert_vector2(sm.default_render_resolution()).is_equal(sm.DEFAULT_RENDER_RESOLUTION)

	sm.set("low_end_forced", true)
	assert_vector2(sm.default_render_resolution()).is_equal(Vector2(640, 480))

func test_a_resolution_chosen_by_the_player_survives_the_low_end_profile():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("apply_render_resolution"):
		return
	var saved_resolution = sm.get("render_resolution")
	var saved_user_set = sm.get("_render_resolution_user_set")

	sm.set("low_end_forced", true)
	sm.set("render_resolution", Vector2(1280, 720))
	sm.set("_render_resolution_user_set", true)
	sm.apply_render_resolution()
	assert_vector2(sm.get("render_resolution")).is_equal(Vector2(1280, 720))

	# Sin eleccion previa, el perfil manda.
	sm.set("_render_resolution_user_set", false)
	sm.apply_render_resolution()
	assert_vector2(sm.get("render_resolution")).is_equal(Vector2(640, 480))

	sm.set("render_resolution", saved_resolution)
	sm.set("_render_resolution_user_set", saved_user_set)
	sm.apply_render_resolution()
