extends Reference
class_name CriopodRingLodV2

# FD-314 - LOD por camara para las capas MultiMesh de los anillos de criopods de RingHub.
#
# Un MultiMeshInstance tiene un AABB unico que abarca todo el anillo: si una parte
# entra al frustum se dibujan TODAS las instancias. Este helper rankea las
# instancias por distancia a la camara con bias de frustum/backface (mismo patron
# que OdiseaExterior._select_nearest_dome_lod_assignments), reordena el buffer de
# transforms para que las N mas relevantes queden primeras, y limita el dibujo con
# MultiMesh.visible_instance_count. Al apagarse re-aplica el orden original.
#
# Visual/CPU-only: no toca estado de gameplay ni determinismo. Inerte salvo que
# CriopodRingVisualV2 lo cree (env ODISEA_CRIOPOD_RING_LOD=1).
#
# El refresh se gatea por el angulo/desplazamiento de la camara (como el patron
# legacy _tick_frustum_lod_update): el sort O(n log n) corre solo cuando la camara
# giro/s e movio lo suficiente, no por frame.

const CAM_EPSILON := 0.0001
# Espejo de CriopodRingVisualV2._hidden_transform. Debe coincidir: colapsar la
# instancia en su origen (escala ~0) en vez de moverla lejos, que inflaria el AABB
# del MultiMesh. No se referencia al visual para no crear un preload ciclico.
const HIDDEN_SCALE := 0.0001

# 0 = sin tope (dibuja todas, solo reordena por relevancia).
var max_instances := 16
var frustum_half_fov_deg := 80.0
var backface_penalty := 8.0
var camera_angle_threshold := 20.0
var camera_move_threshold := 2.0

var _layers := []
# _base[layer_idx][pod_idx] = Transform original (pre-LOD) de esa capa.
var _base := []
# Referencia compartida al diccionario del visual: pod_idx -> true si oculto.
var _hidden := {}
var _count := 0
var _order := []      # posicion -> pod_idx
var _slot_of := []    # pod_idx -> posicion
var _visible_count := -1
var _enabled := true
var _dirty := true
var _last_cam_fwd := Vector3.ZERO
var _last_cam_pos := Vector3.ZERO

func setup(layers: Array, base: Array, hidden: Dictionary, instance_count: int) -> void:
	_layers = layers
	_base = base
	_hidden = hidden
	_count = max(0, instance_count)
	_identity_order()
	_dirty = true

# Posicion actual (slot del buffer) del pod `pod_index`. El visual la usa para
# que block_slot/unblock_slot escriban en el slot correcto cuando el LOD reordena.
func slot_for(pod_index: int) -> int:
	if pod_index < 0 or pod_index >= _slot_of.size():
		return pod_index
	return int(_slot_of[pod_index])

func get_visible_count() -> int:
	return _visible_count

func mark_dirty() -> void:
	_dirty = true

func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	if not _enabled:
		restore()

# Re-aplica el orden original y vuelve a dibujar todas las instancias.
func restore() -> void:
	for layer_idx in range(_layers.size()):
		var mm: MultiMesh = _layers[layer_idx].multimesh
		if mm == null:
			continue
		for i in range(_count):
			mm.set_instance_transform(i, _final_transform(layer_idx, i))
		mm.visible_instance_count = -1
	_identity_order()
	_last_cam_fwd = Vector3.ZERO
	_last_cam_pos = Vector3.ZERO
	_dirty = true

func tick(camera: Camera) -> void:
	if not _enabled or _layers.empty() or _count <= 0:
		return
	if camera == null or not is_instance_valid(camera):
		if _visible_count != -1:
			restore()
		return
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	if cam_fwd.length_squared() <= CAM_EPSILON:
		return
	cam_fwd = cam_fwd.normalized()
	var cam_pos: Vector3 = camera.global_transform.origin
	if not _dirty:
		if _last_cam_fwd.length_squared() > CAM_EPSILON:
			var cos_threshold := cos(deg2rad(clamp(camera_angle_threshold, 1.0, 90.0)))
			if cam_fwd.dot(_last_cam_fwd) >= cos_threshold \
					and _last_cam_pos.distance_squared_to(cam_pos) <= camera_move_threshold * camera_move_threshold:
				return
	_last_cam_fwd = cam_fwd
	_last_cam_pos = cam_pos
	_dirty = false
	_reorder(cam_pos, cam_fwd)

func _reorder(cam_pos: Vector3, cam_fwd: Vector3) -> void:
	# Los transforms de instancia viven en el espacio local del MultiMeshInstance:
	# hay que llevar camara (mundo) al mismo espacio antes de rankear por distancia.
	var inv: Transform = _layers[0].global_transform.affine_inverse()
	var cam_pos_local: Vector3 = inv.xform(cam_pos)
	var cam_fwd_local: Vector3 = inv.basis.xform(cam_fwd).normalized()
	var fov_cos := cos(deg2rad(clamp(frustum_half_fov_deg, 0.0, 179.9)))
	var penalty := backface_penalty
	var scored := []
	var hidden := []
	for i in range(_count):
		if _hidden.has(i):
			hidden.append(i)
			continue
		var to_pod: Vector3 = _base_transform(0, i).origin - cam_pos_local
		var dist_sq := to_pod.length_squared()
		var score := dist_sq
		if dist_sq > 0.001:
			if to_pod.normalized().dot(cam_fwd_local) < fov_cos:
				score = dist_sq * penalty
		scored.append({"pod": i, "score": score})
	scored.sort_custom(self, "_sort_scored")
	var ranked := []
	for entry in scored:
		ranked.append(int(entry["pod"]))
	# Los ocultos van al final: quedan fuera de visible_instance_count y colapsados.
	ranked.append_array(hidden)
	var visible := scored.size()
	if max_instances > 0 and visible > max_instances:
		visible = max_instances
	_apply_order(ranked, visible)

func _apply_order(order: Array, visible: int) -> void:
	var size := min(order.size(), _count)
	for layer_idx in range(_layers.size()):
		var mm: MultiMesh = _layers[layer_idx].multimesh
		if mm == null:
			continue
		for slot in range(_count):
			var pod := int(order[slot]) if slot < size else slot
			mm.set_instance_transform(slot, _final_transform(layer_idx, pod))
		mm.visible_instance_count = visible
	_order = order
	_slot_of = []
	for i in range(_count):
		_slot_of.append(i)
	for slot in range(size):
		_slot_of[int(order[slot])] = slot
	_visible_count = visible

func _final_transform(layer_idx: int, pod: int) -> Transform:
	var base := _base_transform(layer_idx, pod)
	if _hidden.has(pod):
		return Transform(Basis.IDENTITY.scaled(Vector3(HIDDEN_SCALE, HIDDEN_SCALE, HIDDEN_SCALE)), base.origin)
	return base

func _base_transform(layer_idx: int, pod: int) -> Transform:
	if layer_idx < 0 or layer_idx >= _base.size():
		return Transform()
	var layer_base: Array = _base[layer_idx]
	if pod < 0 or pod >= layer_base.size():
		return Transform()
	return layer_base[pod]

func _identity_order() -> void:
	_order = []
	_slot_of = []
	for i in range(_count):
		_order.append(i)
		_slot_of.append(i)
	_visible_count = -1

func _sort_scored(a: Dictionary, b: Dictionary) -> bool:
	var sa := float(a.get("score", 0.0))
	var sb := float(b.get("score", 0.0))
	if sa != sb:
		return sa < sb
	# Tie-break determinista: sort_custom no es estable.
	return int(a.get("pod", -1)) < int(b.get("pod", -1))
