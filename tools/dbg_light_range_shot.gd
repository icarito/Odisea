extends SceneTree

# Captura Dome_Intro desde el pose grabado del replay escalando el alcance de las luces,
# para juzgar a ojo cuanta atmosfera se pierde a cambio de fillrate.
#
#   DBG_FACTOR  multiplicador del rango (1.0 = sin cambio)
#   DBG_OUT     ruta del PNG
#
# OJO: str(Transform) imprime la base POR FILAS, pero Basis(x, y, z) recibe las COLUMNAS.
# Estos valores ya estan transpuestos; se verifica abajo con el producto punto.
const CAM_BASIS := Basis(
	Vector3(-0.876465, 0.0, -0.481466),
	Vector3(-0.078473, 0.986628, 0.142853),
	Vector3(0.475028, 0.162987, -0.864745)
)
const CAM_ORIGIN := Vector3(-11.084831, 7.033483, -19.336546)
const PLAYER_ORIGIN := Vector3(-11.980059, 4.7415, -16.858932)


func _init():
	var factor := float(_env("DBG_FACTOR", "1.0"))
	var salida := _env("DBG_OUT", "/tmp/odisea_dbg/luz.png")

	var esc = load("res://core_v2/levels/interiors/Dome_Intro.tscn").instance()
	get_root().add_child(esc)
	for _i in range(6):
		yield(self, "idle_frame")
	yield(create_timer(2.5), "timeout")

	var tocadas := 0
	var pila := [esc]
	while not pila.empty():
		var n = pila.pop_back()
		if n is OmniLight and n.is_visible_in_tree():
			n.omni_range = n.omni_range * factor
			tocadas += 1
		elif n is SpotLight and n.is_visible_in_tree():
			n.spot_range = n.spot_range * factor
			tocadas += 1
		for c in n.get_children():
			pila.push_back(c)

	var cam := Camera.new()
	cam.fov = 70.0
	cam.far = 400.0
	get_root().add_child(cam)
	cam.global_transform = Transform(CAM_BASIS, CAM_ORIGIN)
	cam.current = true

	# El pose es el del replay: si la base viniera transpuesta la camara miraria a otro lado
	# y las capturas no serian comparables. El producto punto correcto ronda 0.84.
	var hacia := (PLAYER_ORIGIN - CAM_ORIGIN).normalized()
	var adelante := -cam.global_transform.basis.z
	print("[t] verificacion de pose: dot=%.3f (correcto ~0.84)" % adelante.dot(hacia))

	var t := 0.0
	while t < 2.5:
		yield(self, "idle_frame")
		t += 1.0 / 60.0
		if not cam.current:
			cam.current = true

	var img: Image = get_root().get_texture().get_data()
	img.flip_y()
	var err: int = img.save_png(salida)
	print("[t] %s  factor=%.2f  luces_tocadas=%d  draw_calls=%d  err=%d" % [
		salida, factor, tocadas,
		int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)), err])
	quit()


func _env(clave: String, defecto: String) -> String:
	var v := OS.get_environment(clave)
	return v if v != "" else defecto
