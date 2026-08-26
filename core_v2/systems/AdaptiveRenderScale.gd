extends Node

# Baja la escala de render cuando el dispositivo no da los fps, y la devuelve cuando si.
#
# NO toca set_screen_stretch por su cuenta: maneja `SettingsManager.render_scale` y deja que
# SettingsManager.apply_render_resolution() aplique. Ese ajuste ya existia (settings.cfg ->
# display/render_scale, con su base display/render_resolution y clamp a 0.5), y tener dos
# duenos del stretch termina en que se pisan: uno de los dos gana segun el orden de arranque
# y el otro cree estar mandando. Ademas asi la base es estable; leer el viewport ya resuelto
# como 100% es un trinquete, porque si el juego arranca reducido lo toma por escala completa
# y solo puede bajar mas.
#
# Por que esta palanca: el Redmi Note 9 Pro (Adreno 618, GLES2) esta limitado por FILLRATE,
# no por CPU. Medido sobre un replay determinista en Dome_Intro, bajando solo la resolucion
# de render y sin tocar una linea de logica:
#   1.00  1333x600   16.85 fps
#   0.85  1133x510   20.02 fps   (+19%)
#   0.75  1000x450   24.38 fps   (+45%)
#   0.50   666x300   31.25 fps   (+85%)
# Con la misma carga de CPU y hasta 5.6% MAS draw calls. Cuidado al diagnosticar esto:
# TIME_PROCESS y TIME_PHYSICS_PROCESS son tiempo de reloj y absorben los bloqueos esperando
# a la GPU, asi que un frame limitado por GPU se disfraza de CPU.
#
# UI Y MENUS: el modo de stretch del proyecto es "viewport" con aspect "expand", o sea que
# HUD, overlays y menus se dibujan dentro del mismo viewport y se estiran despues. Cambiar la
# escala los escala junto con la escena: proporciones y anclajes quedan exactos, solo baja la
# nitidez.
#
# En vez de una lista de dispositivos "debiles", que envejece mal y no cubre ni el termico ni
# la escena, se mide el fps real y se corrige solo: el mismo telefono va de 17 a 30 fps segun
# el tramo del nivel.

const DISABLE_ENV := "ODISEA_DISABLE_ADAPTIVE_SCALE"
const MOBILE_ENV := "ODISEA_FORCE_MOBILE_PROFILE"

# De mejor a peor. El piso es 0.5 porque es el clamp de SettingsManager, y mas abajo el texto
# de los menus deja de leerse.
const ESCALAS := [1.0, 0.85, 0.75, 0.6, 0.5]

export(bool) var enabled := true
export(bool) var only_on_mobile := true
# Debajo de esto sostenido, se baja un escalon.
export(float, 10.0, 60.0, 1.0) var fps_bajar := 22.0
# La subida es deliberadamente perezosa y el hueco con fps_bajar es ancho: en Dome_Intro el
# mismo telefono va de 17 a 30 fps segun el tramo, asi que con umbrales juntos bajaria en el
# tramo malo y subiria en el bueno una y otra vez. Una resolucion que cambia sola cada pocos
# segundos se nota mucho mas que una resolucion baja y estable.
export(float, 10.0, 90.0, 1.0) var fps_subir := 42.0
export(float, 0.5, 20.0, 0.5) var segundos_para_bajar := 3.0
export(float, 1.0, 60.0, 0.5) var segundos_para_subir := 12.0
# Tras cada cambio, ni se mide ni se decide: el primer segundo despues de recrear el
# framebuffer trae fps basura que dispararian otro cambio en cadena.
export(float, 0.5, 10.0, 0.5) var enfriamiento := 2.0
# Los primeros segundos de una escena estan dominados por la carga, no por el rendimiento
# real; el watchdog de SessionManager ya se comio ese falso positivo ("LOW FPS DETECTED (1.0)").
export(float, 0.0, 30.0, 0.5) var gracia_al_iniciar := 5.0
# Escalones a bajar de una sola vez apenas arranca un VCamera del grupo
# "cinematic_heavy" (ej. RuptureCam en cold_rupture.oys): esas tomas cortan a un
# angulo ya conocido como caro (medido: domo entero desde arriba, draw calls x3,
# fps a pique el tiempo completo) y esperar fps_bajar/segundos_para_bajar significa
# sufrir la toma entera a 2-5 fps antes de reaccionar. El nivel marca de antemano
# cuales tomas son caras (mismo patron que light_budget_aggressive en
# MobileLightBudget.gd); las demas cinematicas no se tocan.
export(int, 0, 4) var cinematic_drop_steps := 2

# La escala que el jugador eligio a mano es el TECHO: se puede bajar de ahi cuando el
# dispositivo sufre, y se puede volver hasta ahi, pero nunca por encima.
var _techo := 1.0
var _indice := 0
var _bajo := 0.0
var _alto := 0.0
var _espera := 0.0
var _gracia := 0.0
var _escena: Node = null
var _ajustes: Node = null
var _indice_pre_cinematica := -1


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		set_process(false)
		return
	if only_on_mobile and not _es_movil():
		set_process(false)
		return
	call_deferred("_tomar_techo")


func _tomar_techo() -> void:
	_ajustes = get_node_or_null("/root/SettingsManager")
	if _ajustes == null:
		set_process(false)
		return
	_techo = float(_ajustes.render_scale)
	_indice = _indice_mas_cercano(_techo)
	_gracia = gracia_al_iniciar
	var cm := get_node_or_null("/root/CinematicManager")
	if cm != null:
		cm.connect("cinematic_started", self, "_on_cinematic_started")
		cm.connect("cinematic_stopped", self, "_on_cinematic_stopped")


# El nombre que llega en la señal no alcanza para mirar el grupo: hay que resolver
# el nodo. get_active_vcamera() ya devuelve el que acaba de activarse (seteado antes
# de emitir la señal); si vino de un rig legacy en vez de VCamera, no hay nodo activo
# de vcamera y simplemente no matchea "cinematic_heavy" — ninguna toma legacy usa ese
# grupo hoy.
func _on_cinematic_started(_rig_id) -> void:
	if not enabled or _ajustes == null or _en_replay():
		return
	var cm := get_node_or_null("/root/CinematicManager")
	if cm == null or not cm.has_method("get_active_vcamera"):
		return
	var vcam = cm.get_active_vcamera()
	if vcam == null or not is_instance_valid(vcam) or not vcam.is_in_group("cinematic_heavy"):
		return
	if _indice_pre_cinematica == -1:
		_indice_pre_cinematica = _indice
	_aplicar(min(ESCALAS.size() - 1, _indice + cinematic_drop_steps))


func _on_cinematic_stopped() -> void:
	# No hay snap-back: la toma caro ya termino, pero el jugador puede seguir en la
	# misma zona densa (ej. justo debajo del domo tras la ruptura). Dejar que la
	# rampa normal de segundos_para_subir confirme que el fps aguanta antes de subir,
	# en vez de arriesgarse a otro tiron por resetear el framebuffer de una.
	_indice_pre_cinematica = -1


func _indice_mas_cercano(valor: float) -> int:
	var mejor := 0
	var dif := INF
	for i in range(ESCALAS.size()):
		var d: float = abs(ESCALAS[i] - valor)
		if d < dif:
			dif = d
			mejor = i
	return mejor


func _es_movil() -> bool:
	if OS.get_environment(MOBILE_ENV) in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


func _process(delta: float) -> void:
	if not enabled or _ajustes == null:
		return
	# Durante un replay no se toca nada: cambiar la resolucion a mitad de una medicion la
	# invalida, y una reproduccion tiene que rendir igual que la corrida que la grabo.
	if _en_replay():
		return

	var escena = get_tree().current_scene if get_tree() != null else null
	if escena != _escena:
		_escena = escena
		_gracia = gracia_al_iniciar
		_bajo = 0.0
		_alto = 0.0
	if _gracia > 0.0:
		_gracia -= delta
		return
	if _espera > 0.0:
		_espera -= delta
		return

	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	if fps <= 0.0:
		return

	if fps < fps_bajar:
		_bajo += delta
		_alto = 0.0
	elif fps > fps_subir:
		_alto += delta
		_bajo = 0.0
	else:
		_bajo = 0.0
		_alto = 0.0

	if _bajo >= segundos_para_bajar and _indice < ESCALAS.size() - 1:
		_aplicar(_indice + 1)
	elif _alto >= segundos_para_subir and _indice > 0 and ESCALAS[_indice - 1] <= _techo:
		_aplicar(_indice - 1)


func _en_replay() -> bool:
	var sm := get_node_or_null("/root/SessionManager")
	if sm == null:
		return false
	return bool(sm.is_replaying) or bool(sm.get("is_hotzone_playback"))


func _aplicar(indice: int) -> void:
	indice = int(clamp(indice, 0, ESCALAS.size() - 1))
	if indice == _indice or _ajustes == null:
		return
	_indice = indice
	# Se cambia el ajuste y se le pide a su dueno que lo aplique. A proposito NO se guarda:
	# la adaptacion es de esta corrida, y persistirla pisaria en disco lo que eligio el
	# jugador, que es justo el techo que estamos respetando.
	_ajustes.render_scale = ESCALAS[_indice]
	_ajustes.apply_render_resolution()
	_bajo = 0.0
	_alto = 0.0
	_espera = enfriamiento
	print("[AdaptiveRenderScale] render_scale -> %.2f (techo %.2f)" % [ESCALAS[_indice], _techo])


# Para forzar una escala a mano (opciones del juego, pruebas).
func set_scale_index(indice: int) -> void:
	_aplicar(indice)


func get_stats() -> Dictionary:
	return {
		"escala": ESCALAS[_indice],
		"techo": _techo,
		"viewport": get_viewport().size if get_viewport() != null else Vector2.ZERO,
		"enabled": enabled,
	}
