extends Node

# Sin class_name: es un autoload, y el singleton ya ocupa ese nombre global.
#
# Achica el alcance de las luces en movil.
#
# El Redmi Note 9 Pro (Adreno 618, GLES2) no esta limitado por CPU sino por FILLRATE. La
# prueba: a un cuarto de los pixeles el frame paso de 59.4 a 32.0 ms (+85% de fps) con la
# misma logica y hasta 5.6% MAS draw calls. Ojo con los contadores de Godot al diagnosticar
# esto: TIME_PROCESS y TIME_PHYSICS_PROCESS son tiempo de reloj y se comen los bloqueos
# esperando a la GPU, asi que un frame limitado por GPU se disfraza de CPU.
#
# Con iluminacion forward en GLES2 cada luz vuelve a sombrear los pixeles que toca, asi que
# el costo de una luz es el area de pantalla que cubre su volumen. Achicar el alcance es la
# palanca directa sobre eso, y a diferencia de apagar luces conserva la atmosfera.
#
# Medido en Dome_Intro sobre un replay determinista (mismas trayectorias, estado limpio):
#   control (10 luces)      16.91 fps   510 draw calls
#   rangos al 60%           22.58 fps   340 draw calls   (+33.5%)
#   sin ninguna luz         23.63 fps   344 draw calls   (+39.8%)
# O sea que el 60% recupera el 84% de lo que daria apagar toda la iluminacion, sin apagar
# ninguna. Contra la captura del pose del replay, la diferencia media es 1.10/255 y solo el
# 1.70% de los pixeles cambia mas de 12/255.
#
# Solo movil a proposito: en escritorio sobra presupuesto y no hay razon para degradar.
#
# Salta las luces invisibles (DomeIntroBakeLightRig y equivalentes: el rig completo de
# luces exclusivas del pase BakedLightmap, forzado a visible=false en runtime — nunca
# cuestan fillrate, asi que recortarles el rango es trabajo puro sin ningun ahorro).
# Sin este filtro, el autoload registraba y tocaba ~106 luces invisibles en Dome_Intro
# ademas de las que si iluminan.

const DISABLE_ENV := "ODISEA_DISABLE_LIGHT_BUDGET"
const MOBILE_ENV := "ODISEA_FORCE_MOBILE_PROFILE"

export(float, 0.2, 1.0, 0.05) var range_scale := 0.6
# Recorte fuerte para las luces que el nivel marque con este grupo. El costo de una luz es
# el area de PANTALLA que cubre su volumen, no su rango en metros: una luz alta, vista desde
# cerca mirando hacia abajo, tapa la vista entera aunque su rango sea modesto.
#
# Medido en Dome_Intro sobre el replay: arriba de la torre (el peor tramo del nivel) DOS
# luces —DomeLamp/PathLight_0 a y=31.8 y TowerLight_5 a y=25.6— explicaban toda la
# iluminacion. Apagando esas dos las draw calls caian de 307 a 186, exactamente el mismo
# numero que apagando las once; las otras nueve ahi son gratis. Bajarles el rango a 5.0 y 3.0
# dio +54.7% de fps en ese tramo y +23.7% en todo el replay, sin apagar ninguna.
#
# Por eso es un grupo y no una regla automatica por altura: cual luz domina la vista depende
# de por donde pasa el jugador, y eso lo sabe el nivel, no un autoload.
export(String) var aggressive_group := "light_budget_aggressive"
export(float, 0.1, 1.0, 0.05) var aggressive_scale := 0.32

# --- Adelgazado del pool de luces cuando el dispositivo no da ---
# Un LightPathV2 marcado con el grupo mantiene un pool fijo de luces que persigue al jugador
# (WallLights son 3). Si los fps se sostienen bajos, se le quita una.
#
# Va en UNA sola direccion y nunca vuelve a subir, a proposito: en GLES2 Godot compila
# variantes de shader segun cuantas luces alcanzan cada superficie, asi que cada cambio del
# conteo obliga a recompilar a mitad de partida — es el mismo mecanismo detras de los tirones
# de 50-90 ms que medimos. Ese costo se paga una vez y se queda; oscilar seria pagarlo cada
# pocos segundos y ademas haria titilar la iluminacion.
#
# FD-284: ahora TAMBIEN sube, pero con un trinquete. La razon de arriba sigue siendo
# cierta —cada cambio del conteo recompila variantes de shader— asi que la subida:
#   * exige fps sostenidos MUY por encima del piso, durante una ventana mucho mas larga
#     que la de bajada (12 s contra 5 s), y
#   * se cancela para siempre en cuanto el dispositivo tuvo que bajar aunque sea una vez
#     (_degradado). Un aparato que ya sufrio no vuelve a pagar recompilaciones.
# Asi un equipo holgado llega a max_pool_size y uno justo nunca oscila, que era el punto
# original del comentario.
export(bool) var adaptive_pool := true
export(float, 5.0, 60.0, 1.0) var pool_fps_floor := 20.0
export(float, 1.0, 30.0, 0.5) var pool_seconds := 5.0
# Piso del pool. Con 1 sola luz el pasillo queda desparejo, asi que no baja de 2.
export(int, 1, 12) var min_pool_size := 2
# Techo de la mejora progresiva. 3 es el valor que este autoload asumia historicamente
# para WallLights antes de que FD-273 lo bajara a 1 por fillrate.
export(bool) var pool_upgrade := true
export(int, 1, 12) var max_pool_size := 3
export(float, 20.0, 120.0, 1.0) var pool_high_fps := 50.0
# Deliberadamente mas larga que pool_seconds: subir cuesta una recompilacion, bajar
# evita un tiron. Ante la duda, no subir.
export(float, 2.0, 60.0, 0.5) var pool_upgrade_seconds := 12.0
# Los primeros segundos de una escena los domina la carga, no el rendimiento real.
export(float, 0.0, 30.0, 0.5) var pool_grace := 6.0
# Luces por debajo de este alcance se dejan quietas: ya cubren poca pantalla, y achicarlas
# se nota mas de lo que ahorra (la del casco del jugador, por ejemplo).
export(float, 0.0, 20.0, 0.5) var min_range_to_touch := 6.0
export(bool) var enabled := true
# LightPathV2 genera sus luces por codigo y no todas existen en el primer frame, igual que
# pasa con los grupos horneados de RadialScatter.
# La ventana de escaneo (intentos x intervalo) cubre hasta que nacio la ultima luz
# procedural. 3 s da margen sobre los 1.4 s originales; medido, ampliarla mas no encuentra
# luces adicionales en Dome_Intro, asi que no hay razon para escanear mas tiempo.
export(int) var scan_attempts := 6
export(float) var scan_interval := 0.5

# { Light: rango original } — para poder volver atras sin recargar la escena.
var _originales := {}
var _escena: Node = null
# LightPathV2 marcados con el grupo, o sea los que pueden perder luces del pool.
var _paths := []
var _bajo_fps := 0.0
var _alto_fps := 0.0
# Trinquete: una sola bajada cancela la subida para el resto de la sesion.
var _degradado := false
# En escritorio no se recorta nada, pero la mejora progresiva SI corre.
var _solo_subida := false
var _gracia := 0.0
var _scans := 0
var _aplicado := false


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		return
	# En escritorio sobra presupuesto: no se recorta ningun rango ni se adelgaza el pool,
	# pero el pool si puede crecer hasta max_pool_size. Antes se salia aca y el
	# adaptativo no existia fuera del movil.
	_solo_subida = not _es_movil()
	# Como autoload sobrevive a los cambios de escena, asi que hay que re-aplicar en cada
	# nivel nuevo: el cache de originales apunta a nodos ya liberados.
	var t := get_tree()
	if t != null:
		var _e = t.connect("tree_changed", self, "_on_tree_changed")
	_programar_scan()


func _on_tree_changed() -> void:
	if not is_inside_tree() or not enabled:
		return
	var actual = get_tree().current_scene
	if actual == _escena:
		return
	_escena = actual
	_originales.clear()
	_scans = 0
	_aplicado = false
	if actual != null:
		_programar_scan()


func _es_movil() -> bool:
	if OS.get_environment(MOBILE_ENV) in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


func _programar_scan() -> void:
	if _scans >= scan_attempts:
		return
	_scans += 1
	var t := get_tree()
	if t == null:
		return
	yield(t.create_timer(scan_interval), "timeout")
	if not is_inside_tree():
		return
	_aplicar()
	_programar_scan()


func _raiz_de_escena() -> Node:
	return get_tree().current_scene if get_tree() != null else null


func _aplicar() -> void:
	if not enabled or get_tree() == null:
		return
	var raiz := _raiz_de_escena()
	if raiz == null:
		return
	var pila := [raiz]
	while not pila.empty():
		var n: Node = pila.pop_back()
		if not _solo_subida and n is Light and (n as Light).visible and not _originales.has(n):
			var actual := _rango_de(n as Light)
			# El rango original se guarda ANTES de tocarlo. Sin esto, un segundo escaneo
			# volveria a multiplicar sobre el valor ya reducido y las luces se apagarian
			# de a poco a cada pasada.
			var agresiva := _es_agresiva(n)
			var factor: float = aggressive_scale if agresiva else range_scale
			# El umbral no aplica a las marcadas: si el nivel dice que una luz domina la
			# vista, hay que recortarla aunque su rango ya sea chico.
			if actual >= min_range_to_touch or agresiva:
				_originales[n] = actual
				_set_rango(n as Light, actual * factor)
		elif adaptive_pool and ("light_pool_size" in n) and _es_agresiva(n) and not _paths.has(n):
			# Antes solo se anotaban los que podian ADELGAZAR (> min_pool_size). Ahora el
			# ajuste va en las dos direcciones, asi que entra cualquier path marcado.
			_paths.append(n)
		for c in n.get_children():
			pila.push_back(c)
	_aplicado = true
	set_process(_puede_cambiar())
	_gracia = pool_grace


# La marca se hereda de los ancestros porque las luces que mas pesan suelen no existir en la
# escena: LightPathV2 genera las suyas por codigo (DomeLamp/PathLight_0 es una de las dos
# caras del peor tramo), asi que no hay nodo donde poner el grupo. Marcando el generador
# quedan cubiertas todas las que produzca.
# Ajusta el pool segun los fps sostenidos: baja cuando el aparato no da, y sube hasta
# max_pool_size cuando sobra margen. La subida se cancela para siempre tras la primera
# bajada (ver el comentario del trinquete arriba).
func _process(delta: float) -> void:
	if not enabled or not adaptive_pool or _paths.empty():
		return
	# Durante un replay no se toca: cambiar la iluminacion a mitad de una medicion la
	# invalida, y una reproduccion tiene que rendir igual que la corrida que la grabo.
	var sm := get_node_or_null("/root/SessionManager")
	if sm != null and (bool(sm.is_replaying) or bool(sm.get("is_hotzone_playback"))):
		return
	if _gracia > 0.0:
		_gracia -= delta
		return
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	if not _solo_subida and fps < pool_fps_floor:
		_alto_fps = 0.0
		_bajo_fps += delta
		if _bajo_fps >= pool_seconds:
			_bajo_fps = 0.0
			_ajustar_pool(-1)
		return
	if pool_upgrade and not _degradado and fps >= pool_high_fps:
		_bajo_fps = 0.0
		_alto_fps += delta
		if _alto_fps >= pool_upgrade_seconds:
			_alto_fps = 0.0
			_ajustar_pool(1)
		return
	# Zona intermedia: ni sufre ni sobra. Se reinician los dos acumuladores para que una
	# racha buena y una mala no se sumen entre si a lo largo de minutos.
	_bajo_fps = 0.0
	_alto_fps = 0.0


func _ajustar_pool(paso: int) -> void:
	var cambio := false
	var quedan := []
	for p in _paths:
		if not is_instance_valid(p):
			continue
		quedan.append(p)
		var actual: int = int(p.light_pool_size)
		# Un pool en 0 lo apago alguien a proposito (DomeLightState en PLENO/OSCURAS):
		# no es falta de presupuesto, es una decision del nivel, y no se pisa.
		if actual <= 0:
			continue
		var nuevo: int = actual
		if paso > 0:
			nuevo = int(min(max_pool_size, actual + 1))
		elif actual > min_pool_size:
			nuevo = int(max(min_pool_size, actual - 1))
		if nuevo != actual:
			print("[MobileLightBudget] %s: pool de luces %d -> %d" % [p.name, actual, nuevo])
			p.light_pool_size = nuevo
			cambio = true
	_paths = quedan
	if paso < 0 and cambio:
		# El trinquete: este aparato ya no dio. No se vuelve a subir en toda la sesion.
		_degradado = true
	if cambio:
		# Tras un cambio hay que dejar que el motor recompile variantes antes de medir.
		_gracia = pool_grace
	set_process(_puede_cambiar())


# Deja de gastar el frame de dibujo cuando ya no queda ningun ajuste posible.
func _puede_cambiar() -> bool:
	for p in _paths:
		if not is_instance_valid(p):
			continue
		var actual: int = int(p.light_pool_size)
		if actual <= 0:
			continue
		if pool_upgrade and not _degradado and actual < max_pool_size:
			return true
		if not _solo_subida and actual > min_pool_size:
			return true
	return false


func _es_agresiva(n: Node) -> bool:
	var actual: Node = n
	while actual != null:
		if actual.is_in_group(aggressive_group):
			return true
		actual = actual.get_parent()
	return false


func _rango_de(l: Light) -> float:
	if l is OmniLight:
		return (l as OmniLight).omni_range
	if l is SpotLight:
		return (l as SpotLight).spot_range
	return 0.0


func _set_rango(l: Light, v: float) -> void:
	if l is OmniLight:
		(l as OmniLight).omni_range = v
	elif l is SpotLight:
		(l as SpotLight).spot_range = v


func set_budget_enabled(valor: bool) -> void:
	enabled = valor
	if valor:
		_scans = 0
		_originales.clear()
		_programar_scan()
		return
	for l in _originales.keys():
		if is_instance_valid(l):
			_set_rango(l, _originales[l])
	_originales.clear()
	_aplicado = false


func get_stats() -> Dictionary:
	return {
		"tocadas": _originales.size(),
		"escala": range_scale,
		"enabled": enabled,
		"aplicado": _aplicado,
	}
