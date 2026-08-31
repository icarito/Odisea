extends SceneTree

# shot_scaffold.gd — Fotos headless de los andamios de Dome_Intro para revisar el
# horneado (barandas de la rampa, uniones de los HubSpokes, etc).
#
# El viewport raiz sale negro con --no-window, asi que se usa un Viewport hijo con
# render target compartiendo el mundo ya cargado (own_world = false).
#
# Uso:
#   ODISEA_SHOT_OUT=/tmp/x ODISEA_SHOT_TARGETS=SpiralStairs,HubSpokes \
#     godot3-bin --no-window -s tools/shot_scaffold.gd
#
# Variables:
#   ODISEA_SHOT_SCENE    escena a cargar (default Dome_Intro)
#   ODISEA_SHOT_OUT      prefijo de salida (default user://scaffold)
#   ODISEA_SHOT_TARGETS  nodos a encuadrar, separados por coma
#   ODISEA_SHOT_ANGLES   angulos de orbita en grados (default 25,115,205,295)
#   ODISEA_SHOT_KEEP     nodos extra que NO se ocultan al aislar el objetivo
#   ODISEA_SHOT_NOISOLATE=1  no ocultar el resto de la escena

const DEFAULT_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const DEFAULT_TARGETS := "SpiralStairs,HubSpokes,SpiralWalkways"
const DEFAULT_ANGLES := "25,115,205,295"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_path: String = OS.get_environment("ODISEA_SHOT_SCENE")
	if scene_path.empty():
		scene_path = DEFAULT_SCENE
	var out_prefix: String = OS.get_environment("ODISEA_SHOT_OUT")
	if out_prefix.empty():
		out_prefix = "user://scaffold"
	var targets: Array = _split_env("ODISEA_SHOT_TARGETS", DEFAULT_TARGETS)
	var angles: Array = _split_env("ODISEA_SHOT_ANGLES", DEFAULT_ANGLES)
	var keep: Array = _split_env("ODISEA_SHOT_KEEP", "")
	var isolate: bool = OS.get_environment("ODISEA_SHOT_NOISOLATE") != "1"

	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("SHOT:load_failed %s" % scene_path)
		quit(1)
		return
	var root: Node = packed.instance()
	get_root().add_child(root)

	# RadialScatter.build() y SteelGratePlatform._rebuild() son diferidos.
	for _i in range(90):
		yield(self, "idle_frame")

	var vp := Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	# Los interiores estan demasiado oscuros para leer geometria en una foto.
	var key := DirectionalLight.new()
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	root.add_child(key)
	var fill := DirectionalLight.new()
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	root.add_child(fill)

	var cam := Camera.new()
	vp.add_child(cam)
	cam.current = true
	cam.far = 500.0
	cam.fov = 55.0
	# El interior del domo es casi negro; sin un environment propio la foto no deja
	# leer la geometria de los andamios.
	# Cielo procedural, no color plano: los tubos son metalicos (metallic 0.8) y sin
	# reflexion de cielo salen practicamente negros.
	var sky := ProceduralSky.new()
	sky.sky_top_color = Color(0.55, 0.62, 0.75)
	sky.sky_horizon_color = Color(0.72, 0.74, 0.78)
	sky.ground_bottom_color = Color(0.28, 0.29, 0.32)
	sky.ground_horizon_color = Color(0.45, 0.46, 0.5)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_sky = sky
	env.background_energy = 1.0
	env.ambient_light_sky_contribution = 1.0
	cam.environment = env

	for target_name in targets:
		var target: Spatial = root.get_node_or_null(target_name) as Spatial
		if target == null:
			printerr("SHOT:missing_target %s" % target_name)
			continue
		var hidden: Array = []
		if isolate:
			hidden = _isolate(root, [target_name] + keep)
		var aabb: AABB = _global_aabb(target)
		if aabb.size == Vector3.ZERO:
			printerr("SHOT:empty_aabb %s" % target_name)
			_restore(hidden)
			continue
		var center: Vector3 = aabb.position + aabb.size * 0.5
		var radius: float = aabb.size.length() * 0.5
		for angle_text in angles:
			if angle_text == "top":
				# Planta ortografica: la unica vista donde un hueco entre dos
				# cubiertas se lee sin ambiguedad de perspectiva.
				cam.projection = Camera.PROJECTION_ORTHOGONAL
				cam.size = max(aabb.size.x, aabb.size.z) * 1.05
				cam.look_at_from_position(
					center + Vector3(0.0, radius * 1.5, 0.01), center, Vector3.UP)
			else:
				cam.projection = Camera.PROJECTION_PERSPECTIVE
				var angle: float = deg2rad(float(angle_text))
				var distance: float = radius * 1.25
				var eye := center + Vector3(
					cos(angle) * distance, radius * 0.55, sin(angle) * distance)
				cam.look_at_from_position(eye, center, Vector3.UP)
			for _i in range(3):
				yield(self, "idle_frame")
			yield(VisualServer, "frame_post_draw")
			var img: Image = vp.get_texture().get_data()
			img.flip_y()
			var path: String = "%s_%s_%s.png" % [out_prefix, target_name.replace("/", "_"), angle_text]
			var err: int = img.save_png(path)
			print("SHOT:%s@%s saved=%s path=%s" % [target_name, angle_text, str(err == OK), path])
		_restore(hidden)

	quit(0)

func _split_env(var_name: String, fallback: String) -> Array:
	var raw: String = OS.get_environment(var_name)
	if raw.empty():
		raw = fallback
	var out: Array = []
	for piece in raw.split(",", false):
		var trimmed: String = piece.strip_edges()
		if not trimmed.empty():
			out.append(trimmed)
	return out

# Oculta todo lo que no sea el objetivo, para que criopods y cascara del domo no
# tapen los andamios. Devuelve los nodos ocultados, para restaurarlos despues.
func _isolate(root: Node, visible_names: Array) -> Array:
	var hidden: Array = []
	for child in root.get_children():
		if not (child is Spatial):
			continue
		if child.name in visible_names:
			continue
		if not (child as Spatial).visible:
			continue
		(child as Spatial).visible = false
		hidden.append(child)
	return hidden

func _restore(hidden: Array) -> void:
	for node in hidden:
		if is_instance_valid(node):
			(node as Spatial).visible = true

func _global_aabb(node: Node) -> AABB:
	var boxes: Array = []
	_collect_aabbs(node, boxes)
	if boxes.empty():
		return AABB()
	var acc: AABB = boxes[0]
	for i in range(1, boxes.size()):
		acc = acc.merge(boxes[i])
	return acc

func _collect_aabbs(node: Node, out_list: Array) -> void:
	if node is VisualInstance and not (node is Light):
		var vi := node as VisualInstance
		var box: AABB = vi.global_transform.xform(vi.get_aabb())
		if box.size != Vector3.ZERO:
			out_list.append(box)
	for child in node.get_children():
		_collect_aabbs(child, out_list)
