extends Node

# Apaga las formas de colision de los props lejanos.
#
# Medido en un Redmi Note 9 Pro (Adreno 618, GLES2) sobre un replay determinista de
# Dome_Intro: con CERO cuerpos activos, cero pares y cero islas, el paso de fisica costaba
# ~14 ms. Desactivar a mano las 383 formas de los StaticBody de capa Prop lo bajaba a
# ~10 ms (-26%), el ahorro mas grande de todos los que probamos. No es simulacion: es
# mantenimiento del broadphase sobre formas registradas, y se paga aunque nada se mueva.
#
# Descartados con medicion antes de llegar aca (para que no se reintenten):
#   - _physics_process de los 168 scripts del juego: 1.42 ms de 14 (9%).
#   - Los 64 RayCast de FakeShadow:                  0.33 ms de 14 (2%).
#   - Estrechar la mascara de colision del jugador:  sin efecto medible.
#
# El culling se decide desde la posicion del jugador en el paso de FISICA, no en idle: asi
# un replay lo reproduce igual, porque la posicion del jugador es identica frame a frame.

# Capas cuyas formas se pueden apagar. Por defecto solo Prop (bit 64): Entorno es el suelo
# y las paredes, y apagarlo dejaria caer al jugador por el mundo.
export(int, LAYERS_3D_PHYSICS) var cullable_layers := 64
# Radio dentro del cual las formas SIEMPRE estan activas. Tiene que superar con holgura lo
# que el jugador pueda recorrer entre dos evaluaciones, o llegaria a un prop todavia apagado.
export(float, 5.0, 200.0, 1.0) var cull_radius := 15.0
# Histeresis: se reactiva a cull_radius y se apaga recien a cull_radius + este margen, para
# que un prop en el limite no oscile encendiendose y apagandose.
export(float, 1.0, 50.0, 1.0) var hysteresis := 8.0
export(int, 1, 30) var frames_between_scans := 8
# Sigue PRENDIDO, y en movil es donde mas rinde. Queda escrito porque hoy me equivoque en
# los dos sentidos y el error es facil de repetir.
#
# Primero medi "enabled = false vs true" mandando la propiedad por telemetria, y salia que
# apagarlo era mejor (40 fps contra 37). Estaba confundido: para cuando llegaba el
# set_property, _ready ya habia corrido y el PRIMER barrido ya habia culleado las formas.
# Ese "apagado" era en realidad "culleado una vez y despues sin reevaluar": tenia el
# beneficio del culling y ninguno de sus costos.
#
# Con el perfil de corrida instrumentado, mismo Redmi Note 9 Pro y mismo replay
# determinista (replay_1788458596 sobre Dome_Intro, 3252 frames):
#
#   culler vivo               fps med 36    este sistema: 0.272 ms por tick
#   culler que nunca corre    fps med 16
#
# Veinte fps. El barrido por tick cuesta 0.27 ms; no cullear cuesta ~20 fps de broadphase
# sobre las formas Prop registradas. La conclusion de FD-270 era correcta.
#
# La otra pata del error, para no repetirla: "pausar el arbol sube 7fps a 60fps" tampoco
# probaba que el broadphase fuera el costo dominante, porque pausar apaga TODOS los
# _physics_process, incluido el de este sistema. Las dos veces el problema fue el mismo:
# comparar configuraciones que no diferian solo en lo que yo creia.
#
# Donde esta el costo de verdad, ya medido con el perfil completo (mismo telefono, mismo
# replay, ms_physics 13.39 de mediana):
#
#   servidor de fisica    7.81 ms/tick   <- 58% del tick
#   scripts (todos)       5.58 ms/tick
#     SessionManager        3.38          (el jugador va adentro durante un replay)
#     PipeCoolantRun        0.33          (22 nodos)
#     KinematicArm3D        0.26
#     este sistema          0.24
#     el resto              < 0.15 c/u
#
# O sea que el broadphase sobre las formas estaticas es el item mas grande del tick, y por
# eso cullear vale 20 fps mientras el barrido que lo decide cuesta 0.24 ms. Lo que queda
# por exprimir en movil es tener menos formas o mas simples, no afinar scripts.
#
# Nota aparte, sin resolver: la grabacion test_locomocion_strafe.oys quedo grabada CON el
# culling activo y sin el deriva 5.74 m contra un umbral de 0.01. O sea que su jugador
# atraviesa un prop que sin culling es solido: hay una forma que no vuelve a habilitarse a
# tiempo. Es un agujero real del sistema, no del test.
#
# Los dos siguen escribiendo el mismo `disabled`: donde SI hay hielo, IceSubmergedCuller
# manda (ver su comentario), y este no debe resucitar formas que el hielo ya sepulto.
export(bool) var enabled := true

const DISABLE_ENV := "ODISEA_DISABLE_COLLISION_CULL"
const ShapeBounds := preload("res://core_v2/systems/collision/ShapeBounds.gd")

# { CollisionShape: { "body": StaticBody, "pos": Vector3, "culled": bool } }
var _tracked := []
var _frame_counter := 0
var _player: Spatial = null
var _scanned_scene: Node = null
var _culled_count := 0
# Posicion del jugador en la ultima evaluacion. El conjunto culleado solo es valido
# mientras el jugador no se haya alejado de ese punto mas que la histeresis; en cuanto lo
# supera, hay que reevaluar SI O SI, sin esperar el turno del contador de frames.
var _last_eval_pos := Vector3.ZERO
var _has_evaluated := false


# Cache del perfilador: buscar el autoload por path en cada tick cuesta, y ese costo
# alcanza para que un replay pierda pasos de fisica y derive. Se resuelve una vez.
var _pm_perfil = null
var _pm_perfil_buscado := false

func _ready() -> void:
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		set_physics_process(false)
		return
	var tree := get_tree()
	if tree != null:
		var _err = tree.connect("tree_changed", self, "_on_tree_changed")


func _on_tree_changed() -> void:
	# get_tree() sobre un nodo fuera del arbol imprime un error del motor antes de devolver
	# null, y esta senal tambien llega durante el desarme de la escena. Preguntar primero.
	if not is_inside_tree():
		return
	# La escena cambio: el cache de props apunta a nodos liberados.
	if get_tree().current_scene != _scanned_scene:
		_tracked.clear()
		_scanned_scene = null
		_player = null


func _physics_process(_delta: float) -> void:
	if not enabled or not is_inside_tree():
		return
	if not _pm_perfil_buscado:
		_pm_perfil_buscado = true
		_pm_perfil = get_node_or_null("/root/PerformanceMonitor")
	if _pm_perfil != null and _pm_perfil._perfil_corrida_on:
		_pm_perfil.perfil_inicio("CollisionCullManager")
		_paso_fisica()
		_pm_perfil.perfil_fin("CollisionCullManager")
		return
	_paso_fisica()

func _paso_fisica() -> void:

	# Un respawn o un teleport mueve al jugador de golpe. Con una evaluacion cada N frames,
	# durante esos frames las formas de su nuevo destino siguen apagadas y el jugador
	# atraviesa el piso: los andamios son capa Prop, o sea culleables. Por eso la condicion
	# real no es "cada N frames" sino "el jugador no se alejo mas que la histeresis desde
	# la ultima evaluacion". Leer una transform por frame es barato; caerse del mundo no.
	var salto_grande := false
	if _has_evaluated and is_instance_valid(_player):
		var recorrido: float = _player.global_transform.origin.distance_squared_to(_last_eval_pos)
		salto_grande = recorrido > (hysteresis * hysteresis)

	_frame_counter += 1
	if not salto_grande and _frame_counter < frames_between_scans:
		return
	_frame_counter = 0
	if get_tree().current_scene != _scanned_scene:
		_rescan()
	if _tracked.empty():
		return
	if not is_instance_valid(_player):
		_player = _find_player()
		if not is_instance_valid(_player):
			return

	var origin: Vector3 = _player.global_transform.origin
	_last_eval_pos = origin
	_has_evaluated = true

	for entry in _tracked:
		var shape: CollisionShape = entry.shape
		if not is_instance_valid(shape):
			continue
		# La distancia se mide contra la SUPERFICIE, no contra el origen del nodo. Una baranda
		# o una plataforma larga tiene su origen en el centro: parado en un extremo el jugador
		# esta a mas de cull_radius del centro y la forma se apagaria mientras la esta tocando.
		# Eso paso de verdad: el jugador atraveso una baranda y cayo.
		var distance: float = origin.distance_to(entry.pos) - entry.radius
		if entry.culled:
			if distance <= cull_radius:
				shape.disabled = false
				entry.culled = false
				_culled_count -= 1
		elif distance > cull_radius + hysteresis:
			shape.disabled = true
			entry.culled = true
			_culled_count += 1


# Las posiciones se cachean una vez: son StaticBody, no se mueven, y leer global_transform
# de 268 cuerpos en cada evaluacion costaria mas que el ahorro.
func _rescan() -> void:
	_tracked.clear()
	_culled_count = 0
	_has_evaluated = false
	var scene: Node = get_tree().current_scene
	_scanned_scene = scene
	if scene == null:
		return
	var stack := [scene]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node is StaticBody and (node.collision_layer & cullable_layers) != 0:
			for child in node.get_children():
				if child is CollisionShape and not child.disabled:
					_tracked.append({
						"shape": child,
						"pos": (child as Spatial).global_transform.origin,
						"radius": ShapeBounds.radius_of(child as CollisionShape),
						"culled": false,
					})
		for child2 in node.get_children():
			stack.push_back(child2)


func _find_player() -> Spatial:
	var session := get_node_or_null("/root/SessionManager")
	if session != null and is_instance_valid(session.player):
		return session.player
	var players := get_tree().get_nodes_in_group("player")
	if not players.empty() and players[0] is Spatial:
		return players[0]
	return null


func get_stats() -> Dictionary:
	return {
		"tracked": _tracked.size(),
		"culled": _culled_count,
		"radius": cull_radius,
		"enabled": enabled,
	}
