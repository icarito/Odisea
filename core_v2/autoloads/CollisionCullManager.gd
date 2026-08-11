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
export(bool) var enabled := true

const DISABLE_ENV := "ODISEA_DISABLE_COLLISION_CULL"

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


func _ready() -> void:
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		set_physics_process(false)
		return
	var tree := get_tree()
	if tree != null:
		var _err = tree.connect("tree_changed", self, "_on_tree_changed")


func _on_tree_changed() -> void:
	# La escena cambio: el cache de props apunta a nodos liberados.
	if get_tree() != null and get_tree().current_scene != _scanned_scene:
		_tracked.clear()
		_scanned_scene = null
		_player = null


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if get_tree() == null:
		return

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
	var near_squared: float = cull_radius * cull_radius
	var far_squared: float = (cull_radius + hysteresis) * (cull_radius + hysteresis)

	for entry in _tracked:
		var shape: CollisionShape = entry.shape
		if not is_instance_valid(shape):
			continue
		var distance_squared: float = origin.distance_squared_to(entry.pos)
		if entry.culled:
			if distance_squared <= near_squared:
				shape.disabled = false
				entry.culled = false
				_culled_count -= 1
		elif distance_squared > far_squared:
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
