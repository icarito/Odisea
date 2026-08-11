extends Node
class_name AirlockPool

# Mantiene UN solo AirlockChamber completo y lo monta sobre el AirlockShell al que se acerca
# el jugador.
#
# Dome_Intro tiene cuatro airlocks pero el jugador solo puede estar usando uno a la vez. Los
# otros tres solo aportan silueta, y para eso alcanza el cilindro (ver AirlockShell.gd). Con
# esto la escena paga el interior completo — dos puertas iris, el beacon con su luz, las dos
# Area, los cuatro scripts — una vez en vez de cuatro, y solo mientras hace falta.
#
# El montaje se decide en el paso de FISICA a partir de la posicion del jugador, no en idle:
# asi un replay lo reproduce igual, porque la posicion del jugador es identica frame a frame.
#
# --- COMO VOLVER AL AIRLOCK COMPLETO EN LOS CUATRO ---
# Sacar este nodo de Dome_Intro.tscn y seguir las instrucciones de AirlockShell.gd.

const DISABLE_ENV := "ODISEA_DISABLE_AIRLOCK_POOL"
const CHAMBER_SCENE := preload("res://core_v2/props/doors/AirlockChamber.tscn")

# Radio al que se monta el airlock completo. Tiene que superar con holgura lo que el jugador
# recorra entre dos evaluaciones, o llegaria a la camara antes de que exista su interior.
# En Dome_Intro los airlocks estan a radio ~32 del centro: pasado ese valor habria siempre
# uno montado (el centro queda a 32 de los cuatro) y el pool no ahorraria nada.
export(float, 5.0, 100.0, 1.0) var activation_distance := 18.0
# Se monta a activation_distance y se desmonta recien a activation_distance + esto, para que
# quedarse justo en el limite no haga aparecer y desaparecer el interior.
export(float, 1.0, 30.0, 1.0) var hysteresis := 6.0
export(int, 1, 30) var frames_between_checks := 6
# En Dome_Intro viene en false: ahi los cuatro airlocks estan congelados desde el arranque y
# no se entra a ninguno, asi que montar el interior seria pagar por algo que nadie usa.
# Ademas montar un airlock FUNCIONAL cambia la fisica y la logica a su alrededor —aparecen
# sus dos Area y sus scripts, y AirlockZoneV2 toca la camara—, y eso rompe la reproduccion
# exacta de un replay: medido, 0.13 m de drift montando contra 0.0015 m con solo los shells.
# Ponerlo en true devuelve un airlock completo y funcional (incluida la transicion a
# OdiseaExterior) al que el jugador se acerque.
export(bool) var enabled := true

var _shells := []
var _chamber: Spatial = null
var _montado: Spatial = null
var _player: Spatial = null
var _frames := 0


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
	if not enabled:
		# Deshabilitado no debe instanciar nada. Antes se creaba igual el AirlockChamber
		# completo y se aparcaba invisible: desperdicio, y ademas sus materiales quedaban
		# registrados en PropDitherManager, que les escribe uniforms cada frame. Un shader
		# que nunca se dibujo no tiene version compilada, y cada escritura sacaba
		# `_get_uniform: Condition "!version" is true`.
		set_physics_process(false)
		return
	call_deferred("_preparar")


func _preparar() -> void:
	_shells = _buscar_shells()
	if _shells.empty():
		set_physics_process(false)
		return
	_chamber = CHAMBER_SCENE.instance()
	_chamber.name = "AirlockChamberPooled"
	# Se cuelga del mismo padre que los shells para que las transformadas sean comparables
	# sin tener que componer jerarquias distintas.
	var padre: Node = _shells[0].get_parent()
	padre.add_child(_chamber)
	_desmontar()


func _buscar_shells() -> Array:
	var out := []
	var tree := get_tree()
	if tree == null:
		return out
	var raiz: Node = self
	while raiz.get_parent() != null and raiz.get_parent() != tree.root:
		raiz = raiz.get_parent()
	var pila := [raiz]
	while not pila.empty():
		var n: Node = pila.pop_back()
		if n.has_method("get_zone_config") and n is Spatial:
			out.append(n)
		for c in n.get_children():
			pila.push_back(c)
	return out


func _physics_process(_delta: float) -> void:
	if not enabled or _chamber == null:
		return
	_frames += 1
	if _frames < frames_between_checks:
		return
	_frames = 0
	if not is_instance_valid(_player):
		_player = _buscar_jugador()
		if not is_instance_valid(_player):
			return
	var pos: Vector3 = _player.global_transform.origin

	var cerca: Spatial = null
	var mejor := INF
	for s in _shells:
		if not is_instance_valid(s):
			continue
		var d: float = pos.distance_to((s as Spatial).global_transform.origin)
		if d < mejor:
			mejor = d
			cerca = s

	# El umbral de salida es mas grande que el de entrada: sin eso, quedarse parado justo en
	# el borde haria aparecer y desaparecer el interior en frames alternos.
	var limite: float = activation_distance + hysteresis if _montado != null else activation_distance
	if cerca != null and mejor <= limite:
		if _montado != cerca:
			_montar(cerca)
	elif _montado != null:
		_desmontar()


func _montar(shell: Spatial) -> void:
	if _montado != null and is_instance_valid(_montado):
		_montado.set_shell_visible(true)
	_montado = shell
	_chamber.global_transform = shell.global_transform
	_aplicar_config(shell)
	_chamber.visible = true
	_chamber.set_physics_process(true)
	_chamber.set_process(true)
	# El cilindro del shell y el del chamber son la misma silueta: mostrar los dos los deja
	# superpuestos peleando por el z-buffer. La COLISION del shell queda puesta, y por eso la
	# del chamber se apaga: la que sostiene al jugador nunca se toca.
	shell.set_shell_visible(false)
	_apagar_colision_del_chamber()


func _desmontar() -> void:
	if _montado != null and is_instance_valid(_montado):
		_montado.set_shell_visible(true)
	_montado = null
	_chamber.visible = false
	_chamber.set_physics_process(false)
	_chamber.set_process(false)
	# Lejos de todo, para que sus Area no toquen nada mientras esta guardado.
	_chamber.global_transform = Transform(Basis(), Vector3(0, -10000, 0))


# El shell guarda a donde lleva su airlock; el chamber pooled es uno solo y se reconfigura
# cada vez que se monta.
func _aplicar_config(shell: Spatial) -> void:
	var zona := _chamber.get_node_or_null("AirlockZoneV2")
	if zona == null:
		return
	var cfg: Dictionary = shell.get_zone_config()
	zona.target_scene = cfg["target_scene"]
	zona.target_spawn_id = cfg["target_spawn_id"]
	zona.target_airlock_path = cfg["target_airlock_path"]
	zona.zone_dir = cfg["zone_dir"]


# El chamber montado aporta SOLO imagen y zonas. Toda su colision solida se apaga porque el
# shell ya la tiene puesta, identica y siempre presente. Duplicarla cambiaria la fisica segun
# el chamber este montado o no, y eso rompe el determinismo del replay: con las dos capas de
# colision el drift medido fue 0.12 m, contra 0.0000 m dejando solo la del shell.
#
# Las formas que cuelgan de un Area (AirlockZoneV2, ChamberZone) NO se tocan: no chocan con
# nada, y son las que hacen andar la transicion de escena.
func _apagar_colision_del_chamber() -> void:
	var pila := [_chamber]
	while not pila.empty():
		var n: Node = pila.pop_back()
		if n is CollisionShape and n.get_parent() is PhysicsBody:
			(n as CollisionShape).disabled = true
		for c in n.get_children():
			pila.push_back(c)


func _buscar_jugador() -> Spatial:
	var session := get_node_or_null("/root/SessionManager")
	if session != null and is_instance_valid(session.player):
		return session.player
	var jugadores := get_tree().get_nodes_in_group("player") if get_tree() != null else []
	return jugadores[0] if not jugadores.empty() and jugadores[0] is Spatial else null


func get_stats() -> Dictionary:
	return {
		"shells": _shells.size(),
		"montado": _montado.name if _montado != null and is_instance_valid(_montado) else "",
		"enabled": enabled,
	}
