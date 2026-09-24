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
