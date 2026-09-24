extends GdUnitTestSuite

# RingHubFloorMaterial.gd — el piso del domo elige la variante PBR (desktop) o la
# liviana (mobile/flat) por tier, y se puede forzar por env para comparar A/B.

const FloorScript = preload("res://core_v2/levels/RingHubFloorMaterial.gd")
const DESKTOP := preload("res://core_v2/levels/interiors/RingHub_Floor_desktop.tres")
const MOBILE := preload("res://core_v2/levels/interiors/RingHub_Floor_mobile.tres")
const JOINTS := preload("res://core_v2/levels/interiors/RingHub_Floor_joints.tres")
const FLOOR_MESH := preload("res://core_v2/levels/RingHub_Floor_baked.mesh")
const JOINTS_MESH := preload("res://core_v2/levels/RingHub_Floor_joints_baked.mesh")
const FORCE_ENV := "ODISEA_RINGHUB_FLOOR_VARIANT"


func _make_floor() -> MeshInstance:
	var mi: MeshInstance = auto_free(MeshInstance.new())
	mi.name = "FloorMesh"
	mi.set_script(FloorScript)
	return mi


# Piso real: hace falta el mesh del piso para que el script agregue la capa de
# juntas (con mesh null no la crea, asi los tests de seleccion no ganan geometria).
func _make_real_floor() -> MeshInstance:
	var mi: MeshInstance = auto_free(MeshInstance.new())
	mi.name = "FloorMesh"
	mi.mesh = FLOOR_MESH
	mi.set_script(FloorScript)
	return mi


func test_desktop_material_is_the_pbr_variant() -> void:
	assert_str(DESKTOP.resource_name).is_equal("M_RingHubFloor_desktop")
	assert_bool(DESKTOP.albedo_texture != null).is_true()
	assert_bool(DESKTOP.normal_enabled).is_true()
	assert_bool(DESKTOP.ao_enabled).is_true()
	assert_bool(DESKTOP.roughness_texture != null).is_true()


# Feedback desktop: con el spot cercano y rasante de la linterna el PBR del piso no
# se notaba (difusa clipeada, normal casi plano, AO que solo tocaba el ambiente).
# Estos valores son el arreglo; si alguien los revierte, el piso vuelve a verse liso.
func test_desktop_pbr_is_tuned_to_read_under_the_flashlight() -> void:
	# Relieve marcado bajo incidencia rasante.
	assert_float(DESKTOP.normal_scale).is_greater_equal(1.5)
	# El AO tambien oscurece juntas/contacto bajo luz directa (no solo el ambiente).
	assert_float(DESKTOP.ao_light_affect).is_greater(0.0)
	# Sin specular azulado fuerte del spot lavando el panel.
	assert_float(DESKTOP.metallic).is_less_equal(0.1)
	assert_float(DESKTOP.roughness).is_greater_equal(0.7)
	# La escala/tono del bake no cambian (solo se toco el sombreado).
	assert_vector3(DESKTOP.uv1_scale).is_equal(Vector3(0.5, 0.5, 0.5))
	assert_bool(DESKTOP.albedo_color.is_equal_approx(Color(0.72, 0.76, 0.8, 1))).is_true()


func test_mobile_material_keeps_albedo_without_extra_maps() -> void:
	assert_str(MOBILE.resource_name).is_equal("M_RingHubFloor_mobile")
	assert_bool(MOBILE.albedo_texture != null).is_true()
	assert_bool(MOBILE.normal_enabled).is_false()
	assert_bool(MOBILE.ao_enabled).is_false()
	assert_bool(MOBILE.roughness_texture == null).is_true()


func test_env_force_desktop() -> void:
	var prev := OS.get_environment(FORCE_ENV)
	OS.set_environment(FORCE_ENV, "desktop")
	var mi := _make_floor()
	add_child(mi)
	assert_str(mi.material_override.resource_name).is_equal("M_RingHubFloor_desktop")
	OS.set_environment(FORCE_ENV, prev)


func test_env_force_mobile() -> void:
	var prev := OS.get_environment(FORCE_ENV)
	OS.set_environment(FORCE_ENV, "mobile")
	var mi := _make_floor()
	add_child(mi)
	assert_str(mi.material_override.resource_name).is_equal("M_RingHubFloor_mobile")
	OS.set_environment(FORCE_ENV, prev)


func test_auto_follows_low_tier() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return
	var prev_env := OS.get_environment(FORCE_ENV)
	var prev_force = gate.force_gate
	OS.set_environment(FORCE_ENV, "")
	gate.force_gate = true
	var mi := _make_floor()
	add_child(mi)
	assert_str(mi.material_override.resource_name).is_equal("M_RingHubFloor_mobile")
	gate.force_gate = prev_force
	OS.set_environment(FORCE_ENV, prev_env)


# --- Referencia visual en DARK / flat: capa de juntas emisivas -----------------

func test_joint_material_is_emissive_but_subtle() -> void:
	# La junta tiene que leerse sin luz pero SIN volverse neon: su emision es baja
	# (en flat el gate la mapea a glow = clamp(max(em)*4, 0.25, 1)).
	assert_str(JOINTS.resource_name).is_equal("M_RingHubFloor_joints")
	assert_bool(JOINTS.emission_enabled).is_true()
	assert_bool(JOINTS.albedo_texture == null).is_true()
	var em: Color = JOINTS.emission
	var peak: float = max(em.r, max(em.g, em.b))
	assert_bool(peak > 0.01).is_true()
	assert_bool(peak <= 0.15).is_true()


func test_floor_spawns_joint_overlay() -> void:
	var mi := _make_real_floor()
	add_child(mi)
	var joints = mi.get_node_or_null("FloorJoints")
	assert_object(joints).is_not_null()
	assert_bool(joints.mesh == JOINTS_MESH).is_true()
	assert_bool(joints.material_override == JOINTS).is_true()
	assert_bool(joints.cast_shadow == GeometryInstance.SHADOW_CASTING_SETTING_OFF).is_true()
	assert_bool(joints.use_in_baked_light).is_false()
	assert_bool(joints.mesh.surface_get_array_index_len(0) / 3 > 0).is_true()


func test_flat_unshaded_keeps_joint_albedo() -> void:
	# ODISEA_UNSHADED=2: el gate deja el SpatialMaterial del piso y de la junta
	# unshaded conservando el albedo (la emision se ignora, pero la linea se ve).
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return
	var prev_force = gate.force_gate
	var prev_mode = gate._unshaded_mode
	gate.force_gate = true
	gate._unshaded_mode = "2"
	var mi := _make_real_floor()
	add_child(mi)
	var joints = mi.get_node_or_null("FloorJoints")
	assert_object(joints).is_not_null()
	assert_bool(joints.material_override is SpatialMaterial).is_true()
	assert_bool((joints.material_override as SpatialMaterial).flags_unshaded).is_true()
	gate.force_gate = prev_force
	gate._unshaded_mode = prev_mode


func test_flat_albedo_mode_keeps_joint_glow() -> void:
	# ODISEA_UNSHADED=3: el gate aplana por superficie; la referencia de la junta
	# sobrevive como glow del FlatFake (no se apaga con el ambiente DARK).
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return
	var prev_force = gate.force_gate
	var prev_mode = gate._unshaded_mode
	gate.force_gate = true
	gate._unshaded_mode = "3"
	var mi := _make_real_floor()
	add_child(mi)
	var joints = mi.get_node_or_null("FloorJoints")
	assert_object(joints).is_not_null()
	var flat = joints.get_surface_material(0)
	assert_bool(flat is ShaderMaterial).is_true()
	var flat_mat: ShaderMaterial = flat as ShaderMaterial
	# El gate aplana la junta al FlatFake doble-lado con el glow de su emision.
	# (El valor de glow no se puede leer bajo el binario Server: los uniforms de un
	# ShaderMaterial sin compilar no se exponen ahi. La estructura y el shader si.)
	assert_str(flat_mat.shader.resource_path.get_file()).is_equal("FlatFakeDoubleSided.shader")
	gate.force_gate = prev_force
	gate._unshaded_mode = prev_mode
