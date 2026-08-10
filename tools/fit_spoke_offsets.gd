extends SceneTree

# fit_spoke_offsets.gd — Mide cuanto le falta al borde EXTERIOR de cada HubSpoke
# para apoyar a ras contra el deck de la rampa, y calcula los
# back_left_depth_offset / back_right_depth_offset que hay que ponerle en
# DomeIntro_ScaffoldSource.tscn.
#
# Los spokes traen solo los offsets del borde interior (front_left/right); el
# exterior es un corte recto perpendicular, y la rampa llega en angulo. Eso es el
# "sin ajuste de offset".
#
# Mide contra la COLISION HORNEADA de Dome_Intro, no contra la escena fuente en
# vivo: SpiralWalkways tiene rebuild_baked_items y sus plataformas se destruyen y
# regeneran, asi que leerlas en vivo da resultados que dependen del frame.
#
# Los decks se separan de las barandas por forma: una baranda es una placa fina y
# casi vertical; un deck es una losa ancha y casi horizontal.
#
# Run: godot3-bin --no-window -s tools/fit_spoke_offsets.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_ScaffoldSource.tscn"
const RAMP_GROUPS := ["SpiralWalkways", "SpiralStairs"]
const MIN_DECK_AREA := 5.0
const MIN_DECK_FLATNESS := 0.55   # |normal.y|: descarta las placas de baranda

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dome: Node = (load(SCENE_PATH) as PackedScene).instance()
	get_root().add_child(dome)
	var source: Node = (load(SOURCE_PATH) as PackedScene).instance()
	get_root().add_child(source)
	for _i in range(30):
		yield(self, "idle_frame")

	var ramp_decks := []
	for group_name in RAMP_GROUPS:
		_collect_decks(dome.get_node_or_null(group_name), group_name, ramp_decks)
	print("FIT: %d decks de rampa detectados" % ramp_decks.size())

	var spokes: Node = source.get_node_or_null("HubSpokes")
	for spoke in spokes.get_children():
		var corners: Array = _spoke_deck(spoke)
		if corners.empty():
			continue
		var back_left: Vector3 = corners[2]
		var back_right: Vector3 = corners[3]
		var mid: Vector3 = (back_left + back_right) * 0.5
		var depth_axis: Vector3 = (spoke as Spatial).global_transform.basis.z.normalized()

		# El deck al que apunta el spoke: el que cruza la prolongacion de su eje,
		# no el mas cercano en linea recta (la espiral pasa por al lado).
		var target = null
		var target_distance := 1e20
		for deck in ramp_decks:
			var hit: float = _ray_into_quad(mid, depth_axis, deck["corners"])
			if hit < 0.0 or hit > 12.0:
				continue
			if abs(_height_at(deck["corners"], mid + depth_axis * hit) - mid.y) > 0.8:
				continue
			if hit < target_distance:
				target_distance = hit
				target = deck
		if target == null:
			print("FIT:%-8s y=%5.2f  el eje no cruza ningun deck de rampa a su altura" % [
				spoke.name, mid.y])
			continue

		# Borde CERCANO del deck de rampa: el que cruza el eje yendo hacia atras.
		var edge: Array = _near_edge(mid, depth_axis, target["corners"])
		# Positivo = la punta del spoke se mete adentro del deck de la rampa.
		var over_left: float = -_advance_to_line(back_left, depth_axis, edge[0], edge[1])
		var over_right: float = -_advance_to_line(back_right, depth_axis, edge[0], edge[1])
		print("FIT:%-8s y=%5.2f  apoya en %-26s" % [spoke.name, mid.y, target["item"]])
		print("     solape esquina izq = %+.3f m   esquina der = %+.3f m   (+ = se mete adentro)" % [
			over_left, over_right])
		print("     back_left_depth_offset  = %+.4f   back_right_depth_offset = %+.4f  (para quedar a ras)" % [
			-over_left, -over_right])
	quit(0)

func _spoke_deck(node: Node) -> Array:
	var shape_node: CollisionShape = _find_named(node, "DeckCollision")
	if shape_node == null or not (shape_node.shape is ConvexPolygonShape):
		return []
	var points: PoolVector3Array = (shape_node.shape as ConvexPolygonShape).points
	var out := []
	for i in range(4):
		out.append(shape_node.global_transform.xform(points[i]))
	return out

func _find_named(node: Node, prefix: String) -> CollisionShape:
	if node is CollisionShape and node.name.begins_with(prefix):
		return node as CollisionShape
	for child in node.get_children():
		var found: CollisionShape = _find_named(child, prefix)
		if found != null:
			return found
	return null

# Toda ConvexPolygonShape del grupo que parezca una losa horizontal ancha.
func _collect_decks(node: Node, group_name: String, out_list: Array) -> void:
	if node == null:
		return
	if node is CollisionShape and node.shape is ConvexPolygonShape:
		var points: PoolVector3Array = (node.shape as ConvexPolygonShape).points
		if points.size() >= 8:
			var corners := []
			for i in range(4):
				corners.append(node.global_transform.xform(points[i]))
			var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
			if normal.length() > MIN_DECK_AREA and abs(normal.normalized().y) > MIN_DECK_FLATNESS:
				out_list.append({"corners": corners, "item": "%s/%s" % [group_name, node.name]})
	for child in node.get_children():
		_collect_decks(child, group_name, out_list)

# Distancia desde `origin` a lo largo de `axis` hasta entrar en el cuadrilatero
# (en planta). -1 si no lo cruza.
func _ray_into_quad(origin: Vector3, axis: Vector3, corners: Array) -> float:
	var best := -1.0
	for pair in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		var t: float = _advance_to_line(origin, axis, corners[pair[0]], corners[pair[1]])
		if t <= 0.001:
			continue
		if not _within_segment(origin + axis * t, corners[pair[0]], corners[pair[1]]):
			continue
		if best < 0.0 or t < best:
			best = t
	return best

# El lado del deck de la rampa contra el que apoya el spoke.
#
# Elegirlo por la interseccion del eje hacia atras es fragil: cuando el eje queda
# casi paralelo a un lado, la interseccion se va a decenas de metros. Se elige por
# distancia perpendicular, descartando los lados casi paralelos al eje (contra
# esos el spoke no puede apoyar).
func _near_edge(origin: Vector3, axis: Vector3, corners: Array) -> Array:
	var direction := Vector2(axis.x, axis.z).normalized()
	var best_distance := 1e20
	var best: Array = [corners[0], corners[1]]
	for pair in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		var a: Vector3 = corners[pair[0]]
		var b: Vector3 = corners[pair[1]]
		var line := Vector2(b.x - a.x, b.z - a.z).normalized()
		if abs(direction.cross(line)) < 0.3:
			continue
		var distance: float = _distance_to_segment(origin, a, b)
		if distance < best_distance:
			best_distance = distance
			best = [a, b]
	return best

func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	var pa := Vector2(a.x, a.z)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var length_squared: float = ab.length_squared()
	if length_squared < 0.000001:
		return p.distance_to(pa)
	var t: float = clamp((p - pa).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(pa + ab * t)

# El lado del cuadrilatero por el que entra el eje del spoke.
func _entry_edge(origin: Vector3, axis: Vector3, corners: Array) -> Array:
	var best_t := 1e20
	var best: Array = [corners[0], corners[1]]
	for pair in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		var t: float = _advance_to_line(origin, axis, corners[pair[0]], corners[pair[1]])
		if t <= 0.001:
			continue
		if not _within_segment(origin + axis * t, corners[pair[0]], corners[pair[1]]):
			continue
		if t < best_t:
			best_t = t
			best = [corners[pair[0]], corners[pair[1]]]
	return best

func _within_segment(point: Vector3, a: Vector3, b: Vector3) -> bool:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var t: float = ap.dot(ab) / max(ab.length_squared(), 0.000001)
	return t >= -0.02 and t <= 1.02

# Altura del plano del deck en la vertical de `point`.
func _height_at(corners: Array, point: Vector3) -> float:
	var normal: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
	if abs(normal.y) < 0.001:
		return corners[0].y
	return corners[0].y - (normal.x * (point.x - corners[0].x) + normal.z * (point.z - corners[0].z)) / normal.y

# Cuanto hay que correr `point` a lo largo de `axis` para caer sobre la recta ab.
func _advance_to_line(point: Vector3, axis: Vector3, a: Vector3, b: Vector3) -> float:
	var direction := Vector2(axis.x, axis.z)
	var line := Vector2(b.x - a.x, b.z - a.z).normalized()
	var offset := Vector2(point.x - a.x, point.z - a.z)
	var denominator: float = direction.cross(line)
	if abs(denominator) < 0.000001:
		return 0.0
	return -offset.cross(line) / denominator
