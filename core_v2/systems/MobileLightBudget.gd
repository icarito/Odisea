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
var _scans := 0
var _aplicado := false


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		return
	if not _es_movil():
		return
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
		if n is Light and not _originales.has(n):
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
		for c in n.get_children():
			pila.push_back(c)
	_aplicado = true


# La marca se hereda de los ancestros porque las luces que mas pesan suelen no existir en la
# escena: LightPathV2 genera las suyas por codigo (DomeLamp/PathLight_0 es una de las dos
# caras del peor tramo), asi que no hay nodo donde poner el grupo. Marcando el generador
# quedan cubiertas todas las que produzca.
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
