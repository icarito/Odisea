extends SceneTree

# Harness de captura para Dome_Intro (depuracion del artefacto visual del domo).
#
# Carga la escena, teletransporta al jugador a una pose registrada del juego real, fija una
# camara propia con esa misma transform y guarda un PNG. Permite ocultar nodos por nombre
# para hacer A/B sin depender de que el juego este abierto y con foco.
#
# El root viewport sale negro con --no-window (ver reference_headless_3d_screenshot), asi
# que esto se corre con ventana real sobre un display virtual:
#
#   xvfb-run -a -s "-screen 0 1400x760x24" godot3-bin --path . --resolution 1400x760 \
#     -s tools/dbg_dome_shot.gd
#
# Variables de entorno:
#   DBG_OUT    nombre base del PNG (default "dome")
#   DBG_HIDE   nodos hijos de la escena a ocultar, separados por coma
#   DBG_DIR    directorio de salida (default /tmp/odisea_dbg)

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"

# Pose capturada del juego en vivo (peer :4999) en el angulo donde el artefacto se ve mejor.
# OJO: str(Transform) imprime la base POR FILAS, pero Basis(x, y, z) recibe las COLUMNAS
# (los ejes). Pasar las filas tal cual transpone la matriz, que en una rotacion equivale a
# invertirla, y la camara termina mirando a otro lado. Estos son los ejes ya transpuestos.
# Para releerlos del juego sin ambiguedad, pedir basis.x / basis.y / basis.z por separado.
const CAM_BASIS := Basis(
	Vector3(-0.876465, 0.0, -0.481466),
	Vector3(-0.078473, 0.986628, 0.142853),
	Vector3(0.475028, 0.162987, -0.864745)
)
const CAM_ORIGIN := Vector3(-11.084831, 7.033483, -19.336546)
const PLAYER_ORIGIN := Vector3(-11.980059, 4.7415, -16.858932)
const CAM_FOV := 75.0

# El IceObjectFreezer escanea 4 veces con 0.35 s de intervalo; hay que dejarlo terminar o
# la mitad de los props todavia no tienen encadenado el next_pass de hielo.
const WARMUP_SECONDS := 2.2


func _init() -> void:
	var out_name := _env("DBG_OUT", "dome")
	var out_dir := _env("DBG_DIR", "/tmp/odisea_dbg")
	var hide_list := _env("DBG_HIDE", "")

	var scene: Node = load(SCENE_PATH).instance()

	# Antes de add_child: _ready() del freezer todavia no corrio, asi que sacarlo aca evita
	# que llegue a encadenar su next_pass de hielo sobre ningun material.
	if _env("DBG_NOFREEZE", "") != "":
		var freezer: Node = scene.get_node_or_null("IceLevel/IceObjectFreezer")
		if freezer != null:
			freezer.get_parent().remove_child(freezer)
			freezer.free()
			print("[dbg] IceObjectFreezer removido")

	# DBG_UNGROUP: saca nodos del grupo ice_freezable antes de que el freezer escanee, para
	# probar "sin escarcha en ESTE nodo" sin apagar el sistema entero.
	var ungroup_list := _env("DBG_UNGROUP", "")
	if ungroup_list.strip_edges() != "":
		for raw_ungroup in ungroup_list.split(","):
			var ungroup_name: String = raw_ungroup.strip_edges()
			if ungroup_name == "":
				continue
			var ungrouped: Node = scene.get_node_or_null(ungroup_name)
			if ungrouped != null and ungrouped.is_in_group("ice_freezable"):
				ungrouped.remove_from_group("ice_freezable")
				print("[dbg] fuera de ice_freezable: ", ungroup_name)

	if _env("DBG_REGROUP", "") != "":
		_regroup(scene, _env("DBG_REGROUP", ""))

	get_root().add_child(scene)

	yield(self, "idle_frame")

	# El cono camara->jugador de PropDitherManager: radio 0 lo deja inerte.
	if _env("DBG_NODITHER", "") != "":
		var dither: Node = get_root().get_node_or_null("PropDitherManager")
		if dither != null:
			dither.set_occlusion_params(0.0)
			print("[dbg] PropDitherManager neutralizado")

	var player: Spatial = scene.get_node_or_null("Pilot_v2")
	if player != null:
		player.global_transform.origin = PLAYER_ORIGIN
		# La animacion idle del Pilot cambia de frame entre corridas y contamina tanto los
		# diffs de pixeles como el benchmark. Congelarla en t=0 hace las capturas comparables.
		_freeze_animation(player)

	var cam := Camera.new()
	cam.fov = CAM_FOV
	cam.far = 400.0
	get_root().add_child(cam)
	cam.global_transform = Transform(CAM_BASIS, CAM_ORIGIN)
	cam.current = true

	var elapsed := 0.0
	while elapsed < WARMUP_SECONDS:
		yield(self, "idle_frame")
		elapsed += 1.0 / 60.0
		# La camara del Pilot pelea por ser current apenas su rig se inicializa.
		if not cam.current:
			cam.current = true
		cam.global_transform = Transform(CAM_BASIS, CAM_ORIGIN)

	# DBG_SHOW: apaga todos los hijos de la escena y prende solo los nombrados. Es la forma
	# barata de aislar que nodo dibuja un artefacto cuando restar de a uno no alcanza.
	var show_list := _env("DBG_SHOW", "")
	if show_list.strip_edges() != "":
		for child in scene.get_children():
			if child is Spatial:
				child.visible = false
		for raw_show in show_list.split(","):
			var show_name: String = raw_show.strip_edges()
			if show_name == "":
				continue
			var shown_node: Node = scene.get_node_or_null(show_name)
			if shown_node == null:
				print("[dbg] nodo inexistente en DBG_SHOW: ", show_name)
				continue
			shown_node.visible = true
		print("[dbg] solo visibles: ", show_list)

	# DBG_NOGAS: apaga todo lo que emite particulas o vapor. Esas capas son animadas y
	# semitransparentes, asi que ensucian tanto el diff de pixeles como la lectura visual
	# del artefacto; apagarlas deja solo geometria y sus pases de material.
	if _env("DBG_NOGAS", "") != "":
		var silenced := 0
		for node in _descendants(scene):
			var is_gas: bool = node is Particles or node is CPUParticles \
				or node.get_class() == "GasArea3D" \
				or (node.get_script() != null and String(node.get_script().resource_path).find("/gas/") != -1) \
				or node.name.find("Emitter") != -1 or node.name.find("CoolantLeak") != -1 \
				or node.name.find("FrostMist") != -1 or node.name.find("IceVisualBand") != -1
			if is_gas:
				if node is Particles or node is CPUParticles:
					node.emitting = false
				if node is Spatial:
					node.visible = false
				if node.has_method("set_process"):
					node.set_process(false)
					node.set_physics_process(false)
				silenced += 1
		print("[dbg] emisores/gas desactivados: %d" % silenced)

	var hidden := []
	if hide_list.strip_edges() != "":
		for raw_name in hide_list.split(","):
			var node_name: String = raw_name.strip_edges()
			if node_name == "":
				continue
			var target: Node = scene.get_node_or_null(node_name)
			if target == null:
				print("[dbg] nodo inexistente: ", node_name)
				continue
			target.visible = false
			hidden.append(node_name)

	# DBG_ICEY: empuja el frente de hielo del overlay fuera de rango. El next_pass sigue
	# encadenado (los materiales siguen siendo las copias del freezer), pero descarta en
	# todos lados: separa "lo dibuja el overlay" de "lo causa duplicar el material".
	var ice_y := _env("DBG_ICEY", "")
	if ice_y != "":
		var freezer_node: Node = scene.get_node_or_null("IceLevel/IceObjectFreezer")
		if freezer_node != null:
			freezer_node._on_ice_height_changed(float(ice_y))
			print("[dbg] ice_height_world forzado a ", float(ice_y))

	# DBG_FADE="start,end": sobrescribe el fade por distancia del overlay. Con un end enorme
	# el fade queda inerte, que es como se mide el "antes" sin editar el shader.
	var fade_spec := _env("DBG_FADE", "")
	if fade_spec != "":
		var parts := fade_spec.split(",")
		var freezer_ref: Node = scene.get_node_or_null("IceLevel/IceObjectFreezer")
		if freezer_ref != null and parts.size() == 2:
			var mats := [freezer_ref._shared_material]
			for extra in freezer_ref._cutout_materials:
				mats.append(extra)
			for mat in mats:
				if mat is ShaderMaterial:
					mat.set_shader_param("fade_start", float(parts[0]))
					mat.set_shader_param("fade_end", float(parts[1]))
			print("[dbg] fade forzado a %s..%s en %d material(es)" % [parts[0], parts[1], mats.size()])

	# DBG_ENV: apaga efectos de post-proceso del WorldEnvironment uno por uno. Son
	# screen-space, asi que se mueven con la camara y ninguna prueba que agregue o quite
	# NODOS los detecta: aparecen igual en el antes y en el despues.
	var env_off := _env("DBG_ENV", "")
	if env_off != "":
		var world_env: Node = scene.get_node_or_null("WorldEnvironment")
		if world_env != null and world_env.environment != null:
			var e: Environment = world_env.environment
			for raw_flag in env_off.split(","):
				var flag: String = raw_flag.strip_edges()
				if flag == "glow":
					e.glow_enabled = false
				elif flag == "dof":
					e.dof_blur_far_enabled = false
					e.dof_blur_near_enabled = false
				elif flag == "adjust":
					e.adjustment_enabled = false
				elif flag == "fog":
					e.fog_enabled = false
				elif flag == "glow_commit":
					# Valores del glow que estan commiteados en HEAD, antes del cambio local.
					e.glow_intensity = 0.28
					e.glow_strength = 0.2
					e.set("glow_levels/1", false)
			print("[dbg] post-proceso apagado: ", env_off)

	# DBG_LODDIST: sobrescribe fixture_lod_distance de WallLights para poder medir el
	# antes/despues del cambio de LOD sin editar la escena entre corridas.
	var lod_dist := _env("DBG_LODDIST", "")
	if lod_dist != "":
		var wall_lights: Node = scene.get_node_or_null("WallLights")
		if wall_lights != null:
			wall_lights.fixture_lod_distance = float(lod_dist)
			print("[dbg] fixture_lod_distance = ", float(lod_dist))

	# Diagnostico de los beacons: por que su OmniLight quedo encendida o apagada.
	if _env("DBG_BEACONS", "") != "":
		for node in _descendants(scene):
			if node.get_class() == "StaticBody" and node.has_method("_player_within_light_range"):
				var omni: Node = node.get_node_or_null("OmniLight")
				var dist := -1.0
				if player != null:
					dist = node.global_transform.origin.distance_to(player.global_transform.origin)
				print("[beacon] act=%.1f is_active=%s omni_vis=%s dist=%.1f | physics_process=%s gate_dice=%s" % [
					node.light_activation_distance, str(node.is_active),
					str(omni.visible) if omni != null else "sin OmniLight", dist,
					str(node.is_physics_processing()), str(node._player_within_light_range())])
		var sm := get_root().get_node_or_null("SessionManager")
		print("[beacon] SessionManager=%s  player=%s" % [str(sm != null), str(sm.player) if sm != null else "n/a"])

	# DBG_BEACONDIST: sobrescribe light_activation_distance en todos los beacons, para poder
	# medir el antes/despues sin editar la escena entre corridas.
	var beacon_dist := _env("DBG_BEACONDIST", "")
	if beacon_dist != "":
		var changed := 0
		for node in _descendants(scene):
			if node.has_method("_player_within_light_range"):
				node.light_activation_distance = float(beacon_dist)
				changed += 1
		print("[dbg] light_activation_distance = %s en %d beacon(s)" % [beacon_dist, changed])

	# DBG_MITIGATE: dispara a mano la mitigacion dinamica de SessionManager y reporta si
	# efectivamente apago los efectos del Environment que la escena esta usando.
	if _env("DBG_MITIGATE", "") != "":
		var sm2 := get_root().get_node_or_null("SessionManager")
		var we: Node = scene.get_node_or_null("WorldEnvironment")
		if sm2 != null and we != null and we.environment != null:
			var before := "glow=%s adjust=%s dof=%s" % [we.environment.glow_enabled, we.environment.adjustment_enabled, we.environment.dof_blur_far_enabled]
			sm2._apply_dynamic_performance_mitigation()
			var after := "glow=%s adjust=%s dof=%s" % [we.environment.glow_enabled, we.environment.adjustment_enabled, we.environment.dof_blur_far_enabled]
			print("[mitig] watchdog_habilitado=%s" % str(sm2._performance_watchdog_enabled))
			print("[mitig] antes:   ", before)
			print("[mitig] despues: ", after)
			print("[mitig] environment activo resuelto = %s" % str(sm2._active_environment() == we.environment))

	# Verificacion del perfil movil: que malla usan los fixtures y si el domo quedo envuelto.
	if _env("DBG_MOBILECHECK", "") != "":
		var wl: Node = scene.get_node_or_null("WallLights")
		if wl != null:
			for child in wl.get_children():
				if child is MultiMeshInstance and String(child.name).begins_with("FixtureBatch_"):
					var mesh_name := "null"
					if child.multimesh != null and child.multimesh.mesh != null:
						mesh_name = child.multimesh.mesh.resource_path.get_file()
						var vcount := 0
						for si in range(child.multimesh.mesh.get_surface_count()):
							vcount += child.multimesh.mesh.surface_get_array_len(si)
						mesh_name += " (%d verts)" % vcount
					print("[mobile] %s -> %s" % [child.name, mesh_name])
		var terrace_mesh: Node = scene.get_node_or_null("Terrace/TerraceMesh")
		if terrace_mesh != null and terrace_mesh.mesh != null:
			for si in range(terrace_mesh.mesh.get_surface_count()):
				var m: Material = terrace_mesh.get_surface_material(si)
				if m == null:
					m = terrace_mesh.mesh.surface_get_material(si)
				var np := "SIN next_pass (no envuelto)"
				if m != null and m.next_pass != null:
					np = "CON next_pass de hielo"
				print("[mobile] Terrace surf %d -> %s" % [si, np])

	if _env("DBG_INVENTORY", "") != "":
		_report_inventory(scene)

	_report_ice_state(scene)

	for _i in range(8):
		yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")

	# DBG_BENCH=N: mide el tiempo medio de frame sobre N frames con vsync apagado, para
	# comparar variantes del shader sin que el limite de refresco aplaste la diferencia.
	var bench_frames := int(_env("DBG_BENCH", "0"))
	if bench_frames > 0:
		OS.vsync_enabled = false
		# Descarte: los primeros frames arrastran compilacion de shaders y subida de texturas.
		for _w in range(30):
			yield(self, "idle_frame")
		var started := OS.get_ticks_usec()
		for _b in range(bench_frames):
			yield(self, "idle_frame")
		var elapsed_us: int = OS.get_ticks_usec() - started
		var per_frame_ms := float(elapsed_us) / float(bench_frames) / 1000.0
		print("[bench] frames=%d ms/frame=%.3f fps=%.1f" % [bench_frames, per_frame_ms, 1000.0 / max(per_frame_ms, 0.001)])

	# Costo de render del frame capturado. INFO_*_DRAWS_IN_FRAME no existe en 3.6; los
	# contadores validos son OBJECTS/VERTICES/MATERIAL_CHANGES/SHADER_CHANGES.
	print("[perf] objects=%d vertices=%d material_changes=%d shader_changes=%d surface_changes=%d" % [
		VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME),
		VisualServer.get_render_info(VisualServer.INFO_VERTICES_IN_FRAME),
		VisualServer.get_render_info(VisualServer.INFO_MATERIAL_CHANGES_IN_FRAME),
		VisualServer.get_render_info(VisualServer.INFO_SHADER_CHANGES_IN_FRAME),
		VisualServer.get_render_info(VisualServer.INFO_SURFACE_CHANGES_IN_FRAME),
	])

	# Auto-chequeo de la pose: si la base se transpuso, la camara mira a otro lado y esto lo
	# delata antes de que yo saque conclusiones de una captura con el angulo equivocado.
	var to_player: Vector3 = (PLAYER_ORIGIN - CAM_ORIGIN).normalized()
	var forward: Vector3 = -cam.global_transform.basis.z
	print("[pose] dot(forward, camara->jugador) = %.3f  (bajo = base mal orientada)" % forward.dot(to_player))
	print("[pose] jugador proyecta en %s de un cuadro de %s" % [
		str(cam.unproject_position(PLAYER_ORIGIN + Vector3(0.0, 1.2, 0.0))),
		str(cam.get_viewport().size),
	])

	# Proyecta puntos sobre la cabeza del jugador: define la ROI donde el artefacto se ve.
	for head_h in [1.7, 2.6, 3.6, 5.0]:
		var world_point: Vector3 = PLAYER_ORIGIN + Vector3(0.0, head_h, 0.0)
		print("[roi] y=+%.1fm -> pantalla %s" % [head_h, str(cam.unproject_position(world_point))])

	var image: Image = get_root().get_texture().get_data()
	image.flip_y()
	var path := "%s/%s.png" % [out_dir, out_name]
	var err: int = image.save_png(path)
	print("[dbg] %s err=%d hidden=%s cam=%s" % [path, err, str(hidden), str(cam.global_transform.origin)])

	quit()


# Inventario estatico de geometria por nodo raiz: cuantos vertices aporta cada rama y
# cuantas de sus superficies llevan encadenado un next_pass (que las hace dibujar dos
# veces). No mide lo mismo que INFO_VERTICES_IN_FRAME (eso ya incluye la duplicacion y el
# culling), pero dice de donde sale el grueso de la geometria.
func _report_inventory(scene: Node) -> void:
	var rows := []
	for child in scene.get_children():
		var totals := {"verts": 0, "meshes": 0, "next_pass": 0}
		_count_geometry(child, totals)
		if totals.verts > 0:
			rows.append({"name": child.name, "verts": totals.verts, "meshes": totals.meshes, "np": totals.next_pass})
	# Censo de luces: en GLES2 cada luz que alcanza una superficie agrega un pase completo
	# sobre su geometria, asi que este numero es el multiplicador que convierte los
	# vertices estaticos en los de INFO_VERTICES_IN_FRAME.
	var lights := []
	_count_lights(scene, lights)
	print("[inv] luces activas=%d" % lights.size())
	for light_desc in lights:
		print("[inv]   %s" % light_desc)

	rows.sort_custom(self, "_by_verts")
	var grand_total := 0
	for row in rows:
		grand_total += row.verts
	print("[inv] total_estatico=%d vertices" % grand_total)
	for row in rows:
		print("[inv] %-22s verts=%9d (%5.1f%%) mallas=%4d superficies_con_next_pass=%d" % [
			row.name, row.verts, 100.0 * float(row.verts) / max(grand_total, 1), row.meshes, row.np,
		])


# Deja quieto todo lo animado bajo un nodo: AnimationPlayer en t=0 y AnimationTree apagado.
func _freeze_animation(root: Node) -> void:
	var frozen := 0
	for node in _descendants(root):
		if node is AnimationPlayer:
			node.stop(true)
			node.seek(0.0, true)
			node.playback_active = false
			frozen += 1
		elif node is AnimationTree:
			node.active = false
			frozen += 1
	if frozen > 0:
		print("[dbg] animacion congelada en %d nodo(s)" % frozen)


func _descendants(root: Node) -> Array:
	var found := [root]
	for child in root.get_children():
		found += _descendants(child)
	return found


# DBG_REGROUP: vuelve a meter nodos en ice_freezable. Sirve para reproducir el
# comportamiento anterior a un fix que los saco del grupo, sin revertir la escena.
func _regroup(scene: Node, names: String) -> void:
	for raw_name in names.split(","):
		var node_name: String = raw_name.strip_edges()
		if node_name == "":
			continue
		var target: Node = scene.get_node_or_null(node_name)
		if target != null and not target.is_in_group("ice_freezable"):
			target.add_to_group("ice_freezable")
			print("[dbg] devuelto a ice_freezable: ", node_name)


func _count_lights(node: Node, out: Array) -> void:
	if node is Light and node.visible and node.is_visible_in_tree():
		var extra := ""
		if node is OmniLight:
			extra = " range=%.1f" % node.omni_range
		out.append("%s (%s) energy=%.2f%s" % [node.get_path(), node.get_class(), node.light_energy, extra])
	for child in node.get_children():
		_count_lights(child, out)


func _by_verts(a, b) -> bool:
	return a.verts > b.verts


func _count_geometry(node: Node, totals: Dictionary) -> void:
	if node is MeshInstance and node.mesh != null:
		totals.meshes += 1
		for i in range(node.mesh.get_surface_count()):
			totals.verts += node.mesh.surface_get_array_len(i)
			var material: Material = node.get_surface_material(i)
			if material == null:
				material = node.mesh.surface_get_material(i)
			if material != null and material.next_pass != null:
				totals.next_pass += 1
	elif node is MultiMeshInstance and node.multimesh != null and node.multimesh.mesh != null:
		totals.meshes += 1
		var instances: int = node.multimesh.instance_count
		if node.multimesh.visible_instance_count >= 0:
			instances = node.multimesh.visible_instance_count
		for i in range(node.multimesh.mesh.get_surface_count()):
			totals.verts += node.multimesh.mesh.surface_get_array_len(i) * instances
			var multi_material: Material = node.multimesh.mesh.surface_get_material(i)
			if multi_material != null and multi_material.next_pass != null:
				totals.next_pass += 1
	for child in node.get_children():
		_count_geometry(child, totals)


# Vuelca el estado que gobierna el overlay de hielo: sin esto no se puede distinguir
# "el next_pass dibuja donde no debe" de "la banda de congelamiento esta donde deberia".
func _report_ice_state(scene: Node) -> void:
	var ice: Node = scene.get_node_or_null("IceLevel")
	if ice != null:
		print("[dbg] ice_height=%s freeze_progress=%s" % [ice.ice_height, ice.visual_freeze_progress])

	var terrace: Node = scene.get_node_or_null("Terrace")
	if terrace == null:
		return
	for child in terrace.get_children():
		if not (child is MeshInstance):
			continue
		var mesh_instance: MeshInstance = child
		if mesh_instance.mesh == null:
			continue
		print("[dbg] Terrace/%s surfaces=%d" % [mesh_instance.name, mesh_instance.mesh.get_surface_count()])
		for i in range(min(mesh_instance.mesh.get_surface_count(), 6)):
			var material: Material = mesh_instance.get_surface_material(i)
			if material == null:
				material = mesh_instance.mesh.surface_get_material(i)
			if material == null:
				print("[dbg]   surf %d: (sin material)" % i)
				continue
			var shader_name := "SpatialMaterial"
			if material is ShaderMaterial and material.shader != null:
				shader_name = material.shader.resource_path.get_file()
			var overlay_info := "sin next_pass"
			if material.next_pass is ShaderMaterial:
				var overlay: ShaderMaterial = material.next_pass
				overlay_info = "next_pass ice_height_world=%s band=%s scissor=%s" % [
					overlay.get_shader_param("ice_height_world"),
					overlay.get_shader_param("freeze_band_height"),
					overlay.get_shader_param("alpha_scissor_threshold"),
				]
			print("[dbg]   surf %d: %s | %s" % [i, shader_name, overlay_info])


func _env(key: String, fallback: String) -> String:
	var value: String = OS.get_environment(key)
	return value if value != "" else fallback
