extends SceneTree

# Captura un airlock a distancia con y sin LOD, para juzgar a ojo cuanto detalle se pierde.
# El arnes general (tools/dbg_dome_shot.gd) usa un pose fijo donde no entra ningun airlock.
#
#   DBG_LOD   "1" detalle apagado (como se ve de lejos), "0" detalle completo
#   DBG_DIST  distancia de la camara al airlock, en metros (default 30)
#   DBG_OUT   ruta del PNG

const AIRLOCK := "Airlock_North"


func _init():
	var salida := _env("DBG_OUT", "/tmp/odisea_dbg/airlock.png")
	var dist := float(_env("DBG_DIST", "30"))
	var lod_on := _env("DBG_LOD", "1") in ["1", "true", "yes", "on"]

	var escena = load("res://core_v2/levels/interiors/Dome_Intro.tscn").instance()
	get_root().add_child(escena)
	for _i in range(4):
		yield(self, "idle_frame")
	yield(create_timer(2.5), "timeout")

	var aire = escena.get_node_or_null(AIRLOCK)
	if aire == null:
		print("[t] no encontre ", AIRLOCK)
		quit()
		return
	var lod = aire.get_node_or_null("AirlockLOD")
	if lod != null:
		# Se fija a mano en vez de dejar que decida la distancia: la camara de captura no es
		# la del juego y el LOD podria evaluar contra otro punto de vista.
		lod.set_lod_enabled(false)
		if lod_on:
			lod._detail_visible = false
			for n in lod._detail:
				n.visible = false

	var centro: Vector3 = aire.global_transform.origin
	# El domo tiene radio ~13, asi que alejarse 22 m en horizontal saca la camara fuera del
	# domo. La unica forma real de estar tan lejos de un airlock es estar ARRIBA, en la
	# torre, que es justo cuando el detalle no se lee. Se reproduce ese caso: adentro del
	# domo, en alto, mirando hacia abajo.
	var hacia_centro: Vector3 = Vector3(-centro.x, 0, -centro.z).normalized()
	var horizontal: float = min(dist * 0.4, 9.0)
	var altura: float = sqrt(max(dist * dist - horizontal * horizontal, 1.0))
	var ojo: Vector3 = centro + hacia_centro * horizontal + Vector3(0, altura, 0)
	var cam := Camera.new()
	cam.fov = 70.0
	cam.far = 400.0
	get_root().add_child(cam)
	cam.look_at_from_position(ojo, centro, Vector3.UP)
	cam.current = true

	var t := 0.0
	while t < 2.0:
		yield(self, "idle_frame")
		t += 1.0 / 60.0
		if not cam.current:
			cam.current = true

	var img: Image = get_root().get_texture().get_data()
	img.flip_y()
	var err: int = img.save_png(salida)
	print("[t] %s  lod=%s dist=%.0f  err=%d  mallas_visibles=%d" % [
		salida, lod_on, dist, err, _contar(aire)])
	quit()


func _contar(raiz) -> int:
	var n := 0
	var pila := [raiz]
	while not pila.empty():
		var x = pila.pop_back()
		if x is MeshInstance and x.is_visible_in_tree():
			n += 1
		for c in x.get_children():
			pila.push_back(c)
	return n


func _env(clave: String, defecto: String) -> String:
	var v := OS.get_environment(clave)
	return v if v != "" else defecto
