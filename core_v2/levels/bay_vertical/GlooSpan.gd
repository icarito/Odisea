extends Area
class_name GlooSpan

# Puerta de GLOO (FD-322): un hueco entre dos plataformas que se cruza pegando
# `required_blobs` blobs de gloo (grupo `gloo_blob` del `MultiToolV2`, API
# pública). Al alcanzar el umbral se habilita una pasarela pisable.
#
# La pasarela se ORIENTA según span_to - span_from (no asume el eje Z), así une
# realmente los dos extremos aunque el tramo esté en cualquier dirección, y su
# altura se ubica respecto de los extremos.
#
# Lectura en `_physics_process` (sin RNG): cuenta blobs vivos dentro del volumen.

signal opened()

export(int) var required_blobs := 2
export(Vector3) var span_from := Vector3.ZERO
export(Vector3) var span_to := Vector3.ZERO
export(float) var span_height := 0.4
export(float) var bridge_width := 2.2
export(float) var bridge_thickness := 0.18
export(Color) var cured_color := Color(0.3, 0.75, 0.65, 1.0)

var _opened := false
var _length := 4.0
var _platform: StaticBody = null
var _platform_visual: MeshInstance = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	_length = max(1.0, (span_to - span_from).length())
	_apply_span_transform()
	_build_sensor()
	_build_closed_visual()

# Coloca el nodo en el centro del tramo, elevado respecto de los extremos, con su
# +Z alineado al tramo (span_to - span_from). Los hijos usan coordenadas locales.
func _apply_span_transform() -> void:
	var dir: Vector3 = span_to - span_from
	var mid: Vector3 = (span_from + span_to) * 0.5
	if dir.length_squared() > 0.0001:
		var forward: Vector3 = dir.normalized()
		var up := Vector3.UP
		var right: Vector3 = up.cross(forward)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		right = right.normalized()
		var basis := Basis(right, up, forward)
		mid.y = max(span_from.y, span_to.y) + span_height
		global_transform = Transform(basis, mid)
	else:
		mid.y = span_from.y + span_height
		global_transform = Transform(Basis.IDENTITY, mid)

func _build_sensor() -> void:
	collision_layer = 0
	collision_mask = 0
	monitoring = true
	var probe := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(bridge_width * 0.5, 1.4, _length * 0.5)
	probe.shape = box
	add_child(probe)

func _build_closed_visual() -> void:
	var missing := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(0.6, 0.15, _length)
	missing.mesh = box
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.5, 0.4, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.6, 0.3, 1.0) * 0.6
	mat.emission_energy = 0.8
	missing.material_override = mat
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
	return abs(local.x) <= bridge_width * 0.5 and abs(local.y) <= 1.4 and abs(local.z) <= _length * 0.5

func _open() -> void:
	_opened = true
	_platform = StaticBody.new()
	_platform.name = "GlooSpanPlatform"
	_platform_visual = MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(bridge_width, bridge_thickness, _length)
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
	colbox.extents = Vector3(bridge_width * 0.5, bridge_thickness * 0.5, _length * 0.5)
	col.shape = colbox
	_platform.add_child(col)
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
