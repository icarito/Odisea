extends Area
class_name GlooSpan

# Puerta de GLOO (FD-322): un hueco entre dos plataformas que se cruza pegando
# `required_blobs` blobs de gloo (grupo `gloo_blob` del `MultiToolV2`, API
# pública). Al alcanzar el umbral se habilita una pasarela pisable.
#
# Lectura en `_physics_process` (sin RNG): cuenta blobs vivos dentro del volumen.

signal opened()

export(int) var required_blobs := 2
export(Vector3) var span_from := Vector3.ZERO
export(Vector3) var span_to := Vector3.ZERO
export(float) var span_height := 0.4
export(Color) var cured_color := Color(0.3, 0.75, 0.65, 1.0)

var _opened := false
var _platform: StaticBody = null
var _platform_visual: MeshInstance = null
var _probe: CollisionShape = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	_build_sensor()
	_build_closed_visual()

func _build_sensor() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = true
	_probe = CollisionShape.new()
	var box := BoxShape.new()
	var half := (span_to - span_from) * 0.5
	var center := (span_from + span_to) * 0.5
	box.extents = Vector3(2.0, 1.4, max(1.0, half.length()))
	_probe.shape = box
	_probe.translation = center - global_transform.origin
	add_child(_probe)

func _build_closed_visual() -> void:
	var missing := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(0.6, 0.15, 4.0)
	missing.mesh = box
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.5, 0.4, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.6, 0.3, 1.0) * 0.6
	mat.emission_energy = 0.8
	missing.material_override = mat
	missing.translation = Vector3(0.0, span_height + 0.2, 0.0)
	add_child(missing)

func _physics_process(_delta: float) -> void:
	if _opened:
		return
	var count := 0
	for blob in get_tree().get_nodes_in_group("gloo_blob"):
		if is_instance_valid(blob) and _inside(blob.global_transform.origin):
			count += 1
			if count >= required_blobs:
				_open()
				return

func _inside(p: Vector3) -> bool:
	var local: Vector3 = global_transform.affine_inverse().xform(p)
	return abs(local.x) <= 2.0 and abs(local.y) <= 1.4 and abs(local.z) <= max(1.0, (span_to - span_from).length())

func _open() -> void:
	_opened = true
	_platform = StaticBody.new()
	_platform.name = "GlooSpanPlatform"
	_platform_visual = MeshInstance.new()
	var box := CubeMesh.new()
	var span_len: float = (span_to - span_from).length()
	box.size = Vector3(2.2, 0.18, span_len)
	_platform_visual.mesh = box
	var mat := SpatialMaterial.new()
	mat.albedo_color = cured_color
	mat.metallic = 0.2
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = cured_color * 0.5
	_platform_visual.material_override = mat
	_platform.add_child(_platform_visual)
	var col := CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(1.1, 0.12, span_len * 0.5)
	col.shape = colbox
	_platform.add_child(col)
	_platform.translation = Vector3(0.0, span_height, 0.0)
	_platform.collision_layer = 64
	_platform.collision_mask = 255
	add_child(_platform)
	emit_signal("opened")

func is_opened() -> bool:
	return _opened

func set_phase(_phase: int) -> void:
	pass

func get_state() -> Dictionary:
	return {"opened": _opened}

func restore_state(data: Dictionary) -> void:
	if bool(data.get("opened", false)) and not _opened:
		_open()
