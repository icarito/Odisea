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
