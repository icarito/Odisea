extends SceneTree

# measure_criopods.gd — Coste de los anillos de criopods de Dome_Intro.
#
# Sirve para comparar el ANTES (218 escenas instanciadas + batching a MultiMesh en
# runtime) contra el DESPUES (mallas horneadas a disco). Mide lo que de verdad se
# paga y no lo que se supone:
#
#   - nodos / cuerpos / formas del subarbol de criopods (coste de arbol y de fisica)
#   - superficies visibles y vertices (superficies = draw calls antes de multiplicar
#     por luces; en GLES2 cada luz que toca un objeto agrega una pasada)
#   - materiales distintos (dos superficies con el mismo material se batchean)
#   - el tiempo de pared que tarda la escena en quedar lista, que es donde se paga
#     el batching diferido
#
# Run: godot3-bin --no-window -s tools/measure_criopods.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const SETTLE_FRAMES := 180

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	var t0 := OS.get_ticks_msec()
	var root: Node = packed.instance()
	var t_instance := OS.get_ticks_msec() - t0

	var t1 := OS.get_ticks_msec()
	get_root().add_child(root)
	var t_add := OS.get_ticks_msec() - t1
	# Los primeros frames son donde se paga el arranque: _batch_static_meshes de
	# RadialScatter entra por call_deferred, o sea dentro del PRIMER frame. Medirlos de
	# a uno es lo unico que muestra el pico; el total de N frames no dice nada porque
	# el bucle mismo fija N.
	var primeros := PoolStringArray()
	for _i in range(8):
		var tf := OS.get_ticks_msec()
		yield(self, "idle_frame")
		primeros.append(str(OS.get_ticks_msec() - tf))
	# El batching de RadialScatter y el envoltorio de hielo entran por call_deferred /
	# timers, asi que "listo" no es el frame de add_child.
	for _i in range(SETTLE_FRAMES):
		yield(self, "idle_frame")
	var t_settle := OS.get_ticks_msec() - t1

	var groups := []
	for child in root.get_node("Spatial").get_children():
		if child.name.begins_with("Criopods"):
			groups.append(child)

	var tot := {"nodes": 0, "bodies": 0, "shapes": 0, "surfaces": 0, "verts": 0}
	var materials := {}
	print("anillo          nodos  bodies  shapes  superficies   verts")
	for g in groups:
		var s := _stats(g, materials)
		for k in tot:
			tot[k] += s[k]
		print("%-14s %6d  %6d  %6d  %11d  %6d" % [
			g.name, s.nodes, s.bodies, s.shapes, s.surfaces, s.verts])

	print("---")
	print("TOTAL criopods: nodos=%d bodies=%d shapes=%d superficies_visibles=%d verts=%d materiales_distintos=%d" % [
		tot.nodes, tot.bodies, tot.shapes, tot.surfaces, tot.verts, materials.size()])
	print("nodos de toda la escena: %d" % _count_nodes(root))
	# Que material termina REALMENTE en cada superficie visible. Es lo que hay que
	# preservar al hornear: PropDitherManager reemplaza SpatialMaterial por su shader
	# de oclusion y IceObjectFreezer encadena el overlay de hielo como next_pass, asi
	# que el material autorizado en el .tscn no es el que se dibuja.
	print("--- materiales dibujados (anillo 1) ---")
	for n in _walk(groups[0]):
		if n is MeshInstance and n.visible and n.mesh != null:
			_dump_materials(n, n.mesh)
		elif n is MultiMeshInstance and n.visible and n.multimesh != null:
			_dump_materials(n, n.multimesh.mesh)
	yield(_draw_calls_ab(root, groups), "completed")
	print("instance()=%d ms  add_child(_ready sincronico)=%d ms" % [t_instance, t_add])
	print("primeros 8 frames tras add_child (ms): %s" % primeros.join(" "))
	print("tamano Dome_Intro.tscn: %d bytes" % _file_size(SCENE_PATH))
	quit()


# Draw calls reales, no superficies: en GLES2 cada luz que toca un objeto agrega una
# pasada, asi que el coste de un anillo no es "3" sino "3 x las luces que lo alcanzan".
# El viewport raiz sale negro con --no-window, asi que se dibuja en un Viewport hijo con
# own_world=false (ver reference_headless_3d_screenshot). A/B: prender y apagar los
# anillos y quedarse con la diferencia, que es lo unico estable de estos contadores.
const CAM_POS := Vector3(-1, 4.7, 8)
const CAM_LOOK := Vector3(0, 3.0, 0)

func _draw_calls_ab(root: Node, groups: Array) -> void:
	var vp := Viewport.new()
	vp.size = Vector2(640, 360)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera.new()
	cam.current = true
	vp.add_child(cam)
	cam.look_at_from_position(CAM_POS, CAM_LOOK, Vector3.UP)
	for _i in range(10):
		yield(self, "idle_frame")

	var con: int = yield(_sample(), "completed")
	for g in groups:
		g.visible = false
	var sin_pods: int = yield(_sample(), "completed")
	for g in groups:
		g.visible = true
	var con2: int = yield(_sample(), "completed")

	print("draw calls (camara en el spawn): con criopods=%d / %d  sin criopods=%d  -> los criopods cuestan ~%d" % [
		con, con2, sin_pods, int(round((con + con2) * 0.5)) - sin_pods])

	# La captura sale del MISMO viewport hijo, que es lo unico que dibuja con --no-window.
	# Sirve para comparar a ojo el antes y el despues del horneado sin levantar xvfb (el
	# harness de tools/dbg_dome_shot.gd tarda minutos con GL por software).
	var salida: String = OS.get_environment("MEASURE_PNG")
	if salida != "":
		vp.size = Vector2(1280, 720)
		for _i in range(20):
			yield(self, "idle_frame")
		var img: Image = vp.get_texture().get_data()
		img.flip_y()
		print("[shot] %s err=%d" % [salida, img.save_png(salida)])
	vp.queue_free()


# Media de varios frames: los contadores son por-frame y globales a todos los viewports.
func _sample() -> int:
	var total := 0
	var muestras := 8
	for _i in range(muestras):
		yield(self, "idle_frame")
		total += VisualServer.get_render_info(VisualServer.INFO_DRAW_CALLS_IN_FRAME)
	return int(round(float(total) / muestras))


# Cuenta superficies VISIBLES: una MeshInstance oculta (los originales que RadialScatter
# apaga al batchear) no dibuja, pero sigue costando arbol, memoria y fisica.
func _stats(node: Node, materials: Dictionary) -> Dictionary:
	var s := {"nodes": 0, "bodies": 0, "shapes": 0, "surfaces": 0, "verts": 0}
	for n in _walk(node):
		s.nodes += 1
		if n is PhysicsBody:
			s.bodies += 1
		elif n is CollisionShape:
			s.shapes += 1
		elif n is MeshInstance and n.visible and n.mesh != null:
			_add_mesh(n.mesh, n, 1, s, materials)
		elif n is MultiMeshInstance and n.visible and n.multimesh != null and n.multimesh.mesh != null:
			_add_mesh(n.multimesh.mesh, n, n.multimesh.instance_count, s, materials)
	return s


func _add_mesh(mesh: Mesh, holder: VisualInstance, instances: int, s: Dictionary, materials: Dictionary) -> void:
	for i in range(mesh.get_surface_count()):
		s.surfaces += 1
		# surface_get_array_len solo existe en ArrayMesh; las PrimitiveMesh (el
		# PersonCard es un CylinderMesh) hay que pasarlas por surface_get_arrays.
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > ArrayMesh.ARRAY_VERTEX and arrays[ArrayMesh.ARRAY_VERTEX] != null:
			s.verts += arrays[ArrayMesh.ARRAY_VERTEX].size() * instances
		var mat: Material = null
		if holder is MeshInstance:
			mat = (holder as MeshInstance).get_surface_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		if holder.material_override != null:
			mat = holder.material_override
		if mat != null:
			materials[mat.get_instance_id()] = true


func _dump_materials(holder: VisualInstance, mesh: Mesh) -> void:
	if mesh == null:
		return
	for i in range(mesh.get_surface_count()):
		var mat: Material = null
		if holder is MeshInstance:
			mat = (holder as MeshInstance).get_surface_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		if holder.material_override != null:
			mat = holder.material_override
		print("  %s surf%d: %s  next_pass=%s  no_occlusion=%s" % [
			holder.name, i, _mat_desc(mat), _mat_desc(mat.next_pass if mat != null else null),
			str(holder.is_in_group("no_occlusion"))])


func _mat_desc(mat: Material) -> String:
	if mat == null:
		return "-"
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		return "Shader(%s)" % (mat as ShaderMaterial).shader.resource_path.get_file()
	return mat.get_class()


func _walk(node: Node, acc: Array = []) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc


func _count_nodes(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_nodes(c)
	return n


func _file_size(path: String) -> int:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return -1
	var size := f.get_len()
	f.close()
	return size
