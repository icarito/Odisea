extends Node
class_name AirlockLOD

# LOD del AirlockChamber: de lejos queda solo el cilindro exterior.
#
# Dome_Intro tiene cuatro camaras y el domo es un anillo, asi que desde el centro se ven
# casi todas a la vez. Cada una son ~27 MeshInstance: nueve del interior (costillas, piso,
# tiras de luz, conductos) y dieciocho de las dos puertas iris (ocho hojas y un marco cada
# una). A eso hay que sumarle que IceObjectFreezer encadena un next_pass a la geometria que
# el hielo puede alcanzar, y un next_pass DUPLICA las draw calls de lo que envuelve.
#
# De lejos nada de ese detalle se lee: el iris son unos pocos pixeles. Lo que si define la
# silueta es el cilindro, y ese se queda siempre.
#
# Solo toca `visible`. Las colisiones y la logica quedan intactas a proposito: apagar formas
# las re-registra en el espacio de fisica y eso perturba el orden de resolucion de contactos
# (medido: mete drift en un replay que sin eso da 0.0000 m). Aca no hay nada de eso, y
# ademas el jugador no puede alcanzar una camara que esta a mas de veinte metros.

# El cilindro exterior y su colision: la silueta del airlock, nunca se apaga.
export(Array, NodePath) var always_visible := [NodePath("CylindricalShell")]
# Lo que se apaga de lejos. Ocultar un Spatial oculta a sus hijos, asi que basta con nombrar
# cada puerta iris entera para llevarse sus nueve mallas.
export(Array, NodePath) var detail_nodes := [
	NodePath("Rib_Front"), NodePath("Rib_Center"), NodePath("Rib_Back"),
	NodePath("Floor"),
	NodePath("LightStripLeft"), NodePath("LightStripRight"), NodePath("LightStripTop"),
	NodePath("ConduitLeft"), NodePath("ConduitRight"),
	NodePath("OuterDoor"), NodePath("InnerDoor"),
]
# Misma distancia que usan las luminarias de pared en Dome_Intro (fixture_cull_distance),
# para que el nivel no tenga dos nociones distintas de "lejos".
export(float, 5.0, 200.0, 1.0) var detail_distance := 22.0
# Se apaga a detail_distance + histeresis y se prende a detail_distance, para que caminar
# justo en el limite no haga parpadear el interior.
export(float, 0.0, 20.0, 0.5) var hysteresis := 4.0
export(int, 1, 60) var frames_between_checks := 10
# Para niveles donde la camara nunca se usa: se aplica el LOD una vez y no se vuelve a
# evaluar la distancia. En Dome_Intro los cuatro airlocks estan congelados desde el arranque
# y no se entra a ninguno, asi que el detalle interior no se mira nunca y el chequeo por
# frame es trabajo puro. Ademas el ahorro pasa a valer en TODO el nivel, no solo cuando el
# jugador esta lejos: adentro del domo (radio ~13) casi nunca se esta a 22 m de un airlock,
# solo desde lo alto de la torre.
export(bool) var force_lod := false
# Opt-in por nivel. AirlockChamber.tscn lo instancian tambien Dome_Crio y DomeFacade_01, y
# ahi los airlocks SI se usan: prenderlo por defecto les cambiaria como se ven sin que nadie
# lo haya pedido ni medido. En Dome_Intro no hace falta porque los cuatro airlocks son
# AirlockShell, que ya es solo el cilindro.
export(bool) var enabled := false

const DISABLE_ENV := "ODISEA_DISABLE_AIRLOCK_LOD"

var _detail := []
var _detail_visible := true
var _frames := 0
var _referencia: Spatial = null


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		set_process(false)
		return
	var padre := get_parent()
	if padre == null:
		set_process(false)
		return
	for ruta in detail_nodes:
		var n := padre.get_node_or_null(ruta)
		if n is Spatial:
			_detail.append(n)
	if _detail.empty():
		set_process(false)
		return
	if force_lod:
		_detail_visible = false
		for n in _detail:
			n.visible = false
		set_process(false)


# Se decide en el frame de dibujo, no en el de fisica: esto no cambia ningun estado de
# juego, solo que se dibuja, asi que no debe acoplarse al paso determinista.
func _process(_delta: float) -> void:
	if not enabled:
		return
	_frames += 1
	if _frames < frames_between_checks:
		return
	_frames = 0
	var origen = _punto_de_vista()
	if origen == null:
		return
	var padre := get_parent() as Spatial
	if padre == null:
		return
	var d: float = origen.distance_to(padre.global_transform.origin)
	var quiero := d <= (detail_distance if not _detail_visible else detail_distance + hysteresis)
	if quiero == _detail_visible:
		return
	_detail_visible = quiero
	for n in _detail:
		if is_instance_valid(n):
			n.visible = quiero


# La camara manda: es lo que decide que se dibuja. El jugador es el respaldo para cuando
# todavia no hay camara activa (arranque de escena, transiciones).
func _punto_de_vista():
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera()
		if cam != null:
			return cam.global_transform.origin
	if not is_instance_valid(_referencia):
		var jugadores := get_tree().get_nodes_in_group("player") if get_tree() != null else []
		_referencia = jugadores[0] if not jugadores.empty() and jugadores[0] is Spatial else null
	if is_instance_valid(_referencia):
		return _referencia.global_transform.origin
	return null


# Apagar el LOD tiene que DEVOLVER el detalle, no solo dejar de decidir: si se congela con
# la camara lejos, el airlock se queda pelado para siempre.
func set_lod_enabled(valor: bool) -> void:
	enabled = valor
	set_process(valor and not force_lod)
	if not valor:
		_detail_visible = true
		for n in _detail:
			if is_instance_valid(n):
				n.visible = true


func get_stats() -> Dictionary:
	return {
		"detalle_visible": _detail_visible,
		"nodos": _detail.size(),
		"distancia": detail_distance,
		"enabled": enabled,
	}
