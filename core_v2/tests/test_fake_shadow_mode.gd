extends GdUnitTestSuite

# O8 (parte 1): la eleccion del modo "cheap" de FakeShadow se gatea por el flag de
# tier bajo del proyecto (GLES3VendorGate.is_low_tier()), NO por arquitectura ARM.
#  - low-tier activo  => shadow_mode pasa a "cheap" (quad + 1 raycast).
#  - low-tier inactivo => NO se fuerza cheap aunque el runner sea Linux/ARM; queda
#    en el modo pedido por la escena (acá simulamos "grid", el del piloto).

const FakeShadowScript = preload("res://core_v2/visual/FakeShadow.gd")

var _gate_prev := {}
var _settings_prev := false
var _env_blob := ""
var _env_shadow := ""


func before() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate:
		_gate_prev = {
			"force_gate": gate.force_gate,
			"gated": gate._gated_active,
			"env": gate._env_forced_low_tier,
			"unshaded": gate._unshaded_mode,
		}
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		_settings_prev = bool(sm.get("low_end_forced"))
	# Con las blob shadows disponibles _ready sale por ese camino antes de decidir
	# cheap/grid; se desactivan para poder medir la seleccion legacy.
	_env_blob = OS.get_environment("ODISEA_DISABLE_BLOB_SHADOW")
	_env_shadow = OS.get_environment("ODISEA_DISABLE_FAKE_SHADOW")
	OS.set_environment("ODISEA_DISABLE_BLOB_SHADOW", "1")
	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", "")


func after() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate and not _gate_prev.empty():
		gate.force_gate = _gate_prev["force_gate"]
		gate._gated_active = _gate_prev["gated"]
		gate._env_forced_low_tier = _gate_prev["env"]
		gate._unshaded_mode = _gate_prev["unshaded"]
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", _settings_prev)
	OS.set_environment("ODISEA_DISABLE_BLOB_SHADOW", _env_blob)
	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", _env_shadow)


func _set_low_tier(active: bool) -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	assert_object(gate).is_not_null()
	if gate == null:
		return
	gate.force_gate = active
	gate._gated_active = false
	gate._env_forced_low_tier = false
	var sm = get_node_or_null("/root/SettingsManager")
	if sm and "low_end_forced" in sm:
		sm.set("low_end_forced", false)


func _make_shadow() -> MeshInstance:
	var fs: MeshInstance = FakeShadowScript.new()
	# La escena del piloto hornea "grid"; el default del script es "cheap", asi que
	# se fija "grid" antes del _ready para que la corrida sea significativa.
	fs.shadow_mode = "grid"
	add_child(fs)
	return fs


func test_low_tier_flag_forces_cheap_mode() -> void:
	_set_low_tier(true)
	var fs := _make_shadow()
	assert_str(String(fs.shadow_mode)).is_equal("cheap")
	assert_bool(fs._cheap_ray != null).is_true()
	fs.free()


func test_without_low_tier_arm_does_not_force_cheap() -> void:
	_set_low_tier(false)
	var fs := _make_shadow()
	assert_str(String(fs.shadow_mode)).is_equal("grid")
	assert_bool(fs._cheap_ray == null).is_true()
	# La deteccion por arquitectura se elimino por completo (O8).
	assert_bool(fs.has_method("_detect_arm_architecture")).is_false()
	fs.free()


func test_flat_low_tier_keeps_pilot_shadow_without_blob_support() -> void:
	_set_low_tier(true)
	var gate = get_node_or_null("/root/GLES3VendorGate")
	gate._unshaded_mode = "3"
	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", "1")
	var pilot := KinematicBody.new()
	pilot.add_to_group("player", true)
	add_child(pilot)
	var fs: MeshInstance = FakeShadowScript.new()
	fs.shadow_mode = "grid"
	pilot.add_child(fs)
	OS.set_environment("ODISEA_DISABLE_FAKE_SHADOW", "")
	gate._unshaded_mode = ""
	assert_bool(fs.visible).is_true()
	assert_bool(fs.is_processing()).is_true()
	assert_str(String(fs.shadow_mode)).is_equal("cheap")
	assert_bool(fs.mesh is PlaneMesh).is_true()
	pilot.free()


# --- O8b: look y seguimiento del camino cheap (Anbernic / tier LOW) ---

func test_cheap_look_defaults_are_smaller_and_denser() -> void:
	# El blob cheap se achico (uv_scale sube) y se hizo mas opaco (opacity sube).
	# Se lockean los defaults tuneables: la unica verificacion posible en headless
	# (el shader GLSL no compila aca; el look final se valida en device).
	var fs: MeshInstance = FakeShadowScript.new()
	assert_float(fs.cheap_uv_scale).is_greater_equal(2.0)
	assert_float(fs.cheap_opacity).is_greater_equal(0.7)
	# Rim: filo fino (rim_width chico) y denso, desactivable con rim_strength=0.
	assert_float(fs.rim_width).is_greater(0.0)
	assert_float(fs.rim_width).is_less(0.1)
	assert_float(fs.rim_strength).is_greater(0.0)
	# O8r: el filo ya no es blanco ni intenso. Gris suave (canales bajos y parejos)
	# y fuerza discreta, ambos tuneables por export en device.
	assert_float(fs.rim_strength).is_less_equal(0.5)
	assert_bool(fs.rim_color.r <= 0.6 and fs.rim_color.g <= 0.6 and fs.rim_color.b <= 0.6).is_true()
	assert_float(abs(fs.rim_color.r - fs.rim_color.b)).is_less(0.1)
	fs.free()


func test_shader_has_thin_rim_params() -> void:
	# El shader GLSL no se carga/compila en headless (rasterizer dummy: Shader.code
	# vuelve vacio), asi que lockeamos el texto del .tres: el uniform del filo y su
	# default tuneable en device.
	var f := File.new()
	assert_int(f.open("res://materials/shadow/FakeShadowShader.tres", File.READ)).is_equal(OK)
	var code: String = f.get_as_text()
	f.close()
	assert_bool(code.find("uniform float rim_strength") != -1).is_true()
	assert_bool(code.find("uniform float rim_width") != -1).is_true()
	assert_bool(code.find("uniform vec3 rim_color") != -1).is_true()
	assert_bool(code.find("shader_param/rim_width") != -1).is_true()
	# O8r: defaults del material = gris suave y fuerza discreta (no blanco/vistoso).
	assert_bool(code.find("shader_param/rim_strength = 0.35") != -1).is_true()
	assert_bool(code.find("shader_param/rim_color = Vector3( 0.42, 0.44, 0.47 )") != -1).is_true()


# --- O8d: dither halftone para que el blob se lea sobre piso oscuro (DARK) ---

func test_dither_defaults_and_zero_is_legacy() -> void:
	# Defaults tuneables en device. dither_strength=0 debe ser el look legacy
	# (sin dither), por eso el default es > 0 pero bajo (cue sutil, no neon).
	var fs: MeshInstance = FakeShadowScript.new()
	assert_float(fs.dither_strength).is_greater(0.0)
	assert_float(fs.dither_strength).is_less_equal(0.5)
	assert_float(fs.dither_scale).is_greater_equal(0.5)
	assert_float(fs.dither_scale).is_less_equal(8.0)
	# El shader lee 0.0 como apagado (a_dither = 0).
	assert_float(fs.dither_strength).is_not_equal(0.0)
	fs.free()


func test_shader_has_procedural_dither() -> void:
	# Sin compilar GLSL en headless, lockeamos el texto del .tres: los uniforms,
	# sus defaults y el patron Bayer procedural (sin textura nueva ni TIME/rand).
	var f := File.new()
	assert_int(f.open("res://materials/shadow/FakeShadowShader.tres", File.READ)).is_equal(OK)
	var code: String = f.get_as_text()
	f.close()
	assert_bool(code.find("uniform float dither_strength") != -1).is_true()
	assert_bool(code.find("uniform float dither_scale") != -1).is_true()
	assert_bool(code.find("shader_param/dither_strength = 0.15") != -1).is_true()
	assert_bool(code.find("shader_param/dither_scale = 1.5") != -1).is_true()
	# Patron procedural ordenado por posicion de pantalla (determinista).
	assert_bool(code.find("bayer4(") != -1).is_true()
	assert_bool(code.find("FRAGCOORD") != -1).is_true()
	assert_bool(code.find("a_dither") != -1).is_true()
	# No debe depender de TIME ni de aleatoriedad (determinismo).
	assert_bool(code.find("TIME") == -1).is_true()
	assert_bool(code.find("rand(") == -1).is_true()


# --- O8t: cue dithered para el camino BlobShadow (desktop/DARK) ---

func test_blob_cue_defaults_are_subtle_and_zero_is_off() -> void:
	# El cue es tenue (se superpone a la blob) y tuneable: 0.0 = sin cue.
	var fs: MeshInstance = FakeShadowScript.new()
	assert_float(fs.blob_cue_strength).is_greater(0.0)
	assert_float(fs.blob_cue_strength).is_less_equal(0.5)
	assert_float(fs.blob_cue_scale).is_greater_equal(0.5)
	assert_float(fs.blob_cue_scale).is_less_equal(8.0)
	fs.free()


func test_blob_cue_gated_off_on_low_tier_and_strength_zero() -> void:
	# tier LOW: no se agrega cue (el piloto ya usa el quad legacy, sin coste extra).
	_set_low_tier(true)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs._setup_blob_cue()
	assert_bool(fs._blob_cue == null).is_true()
	fs.free()
	# blob_cue_strength = 0.0 tambien lo apaga en desktop.
	_set_low_tier(false)
	var fs2: MeshInstance = FakeShadowScript.new()
	fs2.blob_cue_strength = 0.0
	add_child(fs2)
	fs2._setup_blob_cue()
	assert_bool(fs2._blob_cue == null).is_true()
	fs2.free()


func test_blob_cue_created_on_desktop_with_own_material() -> void:
	# Desktop (no low tier): el cue existe, es un quad unshaded con material propio
	# (no toca el .tres compartido del camino grid/cheap) y su rayo de piso.
	_set_low_tier(false)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs._setup_blob_cue()
	assert_bool(fs._blob_cue != null).is_true()
	assert_bool(fs._blob_cue.mesh is PlaneMesh).is_true()
	assert_bool(fs._blob_cue.material_override != null).is_true()
	assert_bool(fs._blob_cue_ray != null).is_true()
	# El material del cue es una copia, no el recurso compartido por grid/cheap.
	var shared: ShaderMaterial = load("res://materials/shadow/FakeShadowShader.tres")
	assert_bool(fs._blob_cue.material_override != shared).is_true()
	fs.free()


func test_shader_has_cue_only_mode() -> void:
	# Sin compilar GLSL en headless, lockeamos el texto del .tres: el uniform
	# cue_only, su default y su uso (apaga nucleo/filo y aplica el dither al aro).
	var f := File.new()
	assert_int(f.open("res://materials/shadow/FakeShadowShader.tres", File.READ)).is_equal(OK)
	var code: String = f.get_as_text()
	f.close()
	assert_bool(code.find("uniform float cue_only") != -1).is_true()
	assert_bool(code.find("shader_param/cue_only = 0.0") != -1).is_true()
	assert_bool(code.find("1.0 - cue_only") != -1).is_true()
	assert_bool(code.find("mix(core, rim, cue_only)") != -1).is_true()
	# Determinismo: reusa el Bayer por FRAGCOORD, sin TIME/rand.
	assert_bool(code.find("TIME") == -1).is_true()
	assert_bool(code.find("rand(") == -1).is_true()


func test_cheap_actor_follows_every_frame() -> void:
	_set_low_tier(true)
	var fs := _make_shadow()
	# Cheap: el actor (piloto) no tiene cadence de 3-6 frames; los props si.
	assert_int(fs._cheap_frame_interval(true)).is_equal(1)
	assert_int(fs._cheap_frame_interval(false)).is_greater_equal(3)
	# El nodo de test no es pilot owner => conserva el intervalo alto.
	assert_int(fs.update_every_n_frames).is_greater_equal(3)
	fs.free()


func test_cheap_shadow_disables_physics_interpolation() -> void:
	if not ClassDB.class_has_method("Node", "set_physics_interpolation_mode"):
		return
	_set_low_tier(true)
	var fs := _make_shadow()
	# OFF (1): el shadow se posiciona a mano con la transform ya interpolada del actor;
	# dejarlo interpolado lo dibujaba varios frames atras.
	assert_int(fs.get_physics_interpolation_mode()).is_equal(1)
	fs.free()


# --- O8t2b: la sombra de DARK (cue dithered) gira con el mesh del actor ---

func test_blob_cue_rotation_defaults_on_and_tunable() -> void:
	# Por defecto el cue copia el yaw del actor (era la devolucion del dueno); el
	# offset fino de alineacion arranca en 0 y es tuneable en device.
	var fs: MeshInstance = FakeShadowScript.new()
	assert_bool(fs.blob_cue_rotate_with_actor).is_true()
	assert_float(fs.blob_cue_yaw_sign).is_equal(1.0)
	assert_float(fs.blob_cue_yaw_offset_deg).is_equal(0.0)
	fs.free()


func test_blob_cue_yaw_sign_flips_without_recompile() -> void:
	# El sentido es tuneable en device: sign=-1 espeja el barrido respecto del
	# fakeshadow legacy (que rota la textura con texture_rotation = -yaw).
	_set_low_tier(false)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs.blob_cue_yaw_sign = -1.0
	fs._setup_blob_cue()
	fs._update_blob_cue(Vector3.ZERO, PI * 0.5)
	assert_float(abs(wrapf(fs._blob_cue.global_transform.basis.get_euler().y + PI * 0.5, -PI, PI))).is_less(0.001)
	fs.free()


func test_blob_cue_basis_follows_actor_yaw() -> void:
	# El BlobCue se creaba toplevel con basis IDENTITY => ovalo fijo al mundo. La
	# aceptacion pide que su basis/rotacion siga al actor, como el fakeshadow legacy.
	_set_low_tier(false)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs._setup_blob_cue()
	assert_bool(fs._blob_cue != null).is_true()
	var yaw := PI * 0.5
	fs._update_blob_cue(Vector3(1.0, 0.5, 2.0), yaw)
	var basis: Basis = fs._blob_cue.global_transform.basis
	assert_float(abs(wrapf(basis.get_euler().y - yaw, -PI, PI))).is_less(0.001)
	# El yaw no debe inclinar el quad: sigue horizontal (sin pitch/roll).
	assert_float(abs(basis.get_euler().x)).is_less(0.001)
	assert_float(abs(basis.get_euler().z)).is_less(0.001)
	# El origen conserva el XZ del centro y se pega al piso en Y.
	var origin: Vector3 = fs._blob_cue.global_transform.origin
	assert_float(abs(origin.x - 1.0)).is_less(0.001)
	assert_float(abs(origin.z - 2.0)).is_less(0.001)
	assert_float(origin.y).is_less(0.5)
	fs.free()


func test_blob_cue_rotation_can_be_disabled() -> void:
	# blob_cue_rotate_with_actor = false recupera el look fijo al mundo (legacy).
	_set_low_tier(false)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs.blob_cue_rotate_with_actor = false
	fs._setup_blob_cue()
	fs._update_blob_cue(Vector3.ZERO, PI * 0.5)
	assert_float(abs(fs._blob_cue.global_transform.basis.get_euler().y)).is_less(0.001)
	fs.free()


func test_blob_cue_yaw_offset_aligns_with_mesh() -> void:
	# Con el actor en yaw 0, un offset de 90 grados orienta el ovalo a PI/2.
	_set_low_tier(false)
	var fs: MeshInstance = FakeShadowScript.new()
	add_child(fs)
	fs.blob_cue_yaw_offset_deg = 90.0
	fs._setup_blob_cue()
	fs._update_blob_cue(Vector3.ZERO, 0.0)
	assert_float(abs(wrapf(fs._blob_cue.global_transform.basis.get_euler().y - PI * 0.5, -PI, PI))).is_less(0.001)
	fs.free()


func test_anchor_yaw_reads_parent_rotation() -> void:
	# Sin body raiz, el yaw sale del padre directo (mismo origen que grid/cheap).
	var holder := Spatial.new()
	add_child(holder)
	holder.rotation.y = 0.7
	var fs: MeshInstance = FakeShadowScript.new()
	fs.anchor_to_root_body = false
	holder.add_child(fs)
	assert_float(abs(wrapf(fs._get_anchor_yaw(fs.get_parent()) - 0.7, -PI, PI))).is_less(0.001)
	holder.free()


func test_anchor_yaw_follows_visual_pivot_inside_root_body() -> void:
	# El Pilot mantiene recto el KinematicBody y gira Visual/Pivot: el cue debe usar
	# ese pivote, igual que los caminos grid/cheap.
	var body := KinematicBody.new()
	add_child(body)
	body.rotation.y = 1.1
	var holder := Spatial.new()
	holder.rotation.y = -0.4
	body.add_child(holder)
	var fs: MeshInstance = FakeShadowScript.new()
	fs.anchor_to_root_body = true
	holder.add_child(fs)
	assert_float(abs(wrapf(fs._get_anchor_yaw(fs.get_parent()) - 0.7, -PI, PI))).is_less(0.001)
	body.free()
