extends Control

# ZoomRuler.gd - Rallitas metricas abajo al centro, solo mientras se hace zoom (OdiseaOS HUD).
# Sin texto (narrativa ambiental): la separacion de las marcas crece al acercar y se achica al
# alejar, desde el centro, asi que el zoom se ve aunque la escena no de referencia.
#
# El zoom es la distancia del brazo de camara en orbita (base_spring_length_3d) o, en una camara
# cinematica, su FOV (_cinematic_zoom_target_fov). Se sondea al jugador cada cuadro en vez de
# conectar una señal: el jugador cambia con cada escena y esto no tiene que enterarse.
#
# La separacion recorre una octava: al duplicarse el zoom vuelve a la base, y las marcas menores
# (que crecen con la fraccion de la octava) quedan exactamente donde estaban las mayores, asi que
# el ciclo no salta.

const UIScaleCompensator = preload("res://core_v2/ui/UIScaleCompensator.gd")

const WIDTH_RATIO := 0.4 # del ancho de la pantalla
const HEIGHT := 26.0 # nominal
const BOTTOM_MARGIN := 14.0 # nominal
const BASE_SPACING := 18.0 # nominal, entre marcas mayores al empezar la octava
const HOLD_MSEC := 600 # visible tras el ultimo cambio de zoom
const FADE_MSEC := 400
const COLOR := Color(0.0, 0.83, 1.0, 0.9)

var _level := 0.0 # log2 del aumento: +1 cada vez que el zoom se duplica
var _last_metric := -1.0
var _last_change_msec := -100000
var _player_id := 0
# El control remoto no tiene jugador: su backend da la metrica (zoom_metric) con el pellizco.
var backend: Node = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(_delta: float) -> void:
	var metric: float = _zoom_metric()
	if metric > 0.0:
		if _last_metric > 0.0 and abs(metric - _last_metric) > 0.0001:
			_last_change_msec = OS.get_ticks_msec()
		_last_metric = metric
		_level = -log(metric) / log(2.0)
	var since: int = OS.get_ticks_msec() - _last_change_msec
	var alpha: float = 1.0 if since < HOLD_MSEC else clamp(1.0 - float(since - HOLD_MSEC) / FADE_MSEC, 0.0, 1.0)
	var show: bool = alpha > 0.0 and not get_tree().paused
	visible = show
	if show:
		modulate.a = alpha
		_place()
		update()

# Mas chico = mas cerca: distancia de camara, o tan(FOV/2) en una camara cinematica.
func _zoom_metric() -> float:
	if is_instance_valid(backend) and backend.has_method("zoom_metric"):
		return backend.zoom_metric()
	var session = get_node_or_null("/root/SessionManager")
	var player = session.get("player") if session != null else null
	if not is_instance_valid(player):
		return -1.0
	# Otro jugador (cambio de escena): su distancia distinta no es un zoom.
	if player.get_instance_id() != _player_id:
		_player_id = player.get_instance_id()
		_last_metric = -1.0
	var fov = player.get("_cinematic_zoom_target_fov")
	if fov != null and float(fov) > 0.0:
		return tan(deg2rad(float(fov)) * 0.5)
	var distance = player.get("base_spring_length_3d")
	return float(distance) if distance != null and float(distance) > 0.0 else -1.0

func _place() -> void:
	var k: float = UIScaleCompensator.scale_for(self)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var size := Vector2(viewport_size.x * WIDTH_RATIO, HEIGHT * k)
	rect_size = size
	rect_position = Vector2((viewport_size.x - size.x) * 0.5, viewport_size.y - size.y - BOTTOM_MARGIN * k)

func _draw() -> void:
	var k: float = UIScaleCompensator.scale_for(self)
	var octave: float = _level - floor(_level)
	var spacing: float = BASE_SPACING * k * pow(2.0, octave)
	var center_x: float = rect_size.x * 0.5
	var baseline: float = rect_size.y
	var major: float = rect_size.y * 0.7
	var minor: float = major * octave # nace en 0 y llega a mayor justo al cerrar la octava
	draw_line(Vector2(0.0, baseline), Vector2(rect_size.x, baseline), COLOR, 1.0, true)
	var n: int = int(ceil(center_x / (spacing * 0.5)))
	for i in range(-n, n + 1):
		var x: float = center_x + i * spacing * 0.5
		if x < 0.0 or x > rect_size.x:
			continue
		var is_major: bool = i % 2 == 0
		var height: float = major if is_major else minor
		# Hacia los extremos se desvanecen, para que la regla no tenga bordes duros.
		var edge: float = 1.0 - abs(x - center_x) / center_x
		var color := Color(COLOR.r, COLOR.g, COLOR.b, COLOR.a * clamp(edge * 1.5, 0.0, 1.0))
		draw_line(Vector2(x, baseline), Vector2(x, baseline - height), color, 2.0 if i == 0 else 1.0, true)
