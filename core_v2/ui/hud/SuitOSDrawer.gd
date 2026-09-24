extends Control
class_name SuitOSDrawer

# SuitOSDrawer.gd - El "..." del radial (FD-305 §3): la lista completa de pantallas registradas,
# alfabetica, donde el jugador USA (A) y CURA (X).
#
# El dial muestra solo los favoritos; el drawer muestra todo. Por eso el orden aca es alfabetico
# y no por relevancia: son dos preguntas distintas ("donde esta X?" vs "que me importa ahora?").
#
# No usa ScrollContainer: su scroll nativo no toma velocidad analogica. El stick da VELOCIDAD
# (acelera, acompaña y decae), la cruceta da pasos, los topes rebotan y al detenerse la fila mas
# cercana al centro se alinea sola. Todo sobre un unico offset en pixeles, dibujado a mano.
#
# La busqueda de texto esta fuera de la primera entrega (FD-305 §3.4): solo sirve en desktop y el
# agrupado por inicial ya cubre una lista de menos de una docena de filas.

const UIScaleCompensator = preload("res://core_v2/ui/UIScaleCompensator.gd")
const Haptics = preload("res://core_v2/ui/Haptics.gd")

signal screen_chosen(id)
signal favorite_toggled(id, is_favorite)
signal closed()

const ROW_HEIGHT := 56.0
const ROW_WIDTH := 420.0
# El stick da velocidad, no posicion: acelera mientras se empuja y decae al soltar.
const ACCEL := 2800.0
const FRICTION := 7.0
const MAX_SCROLL_SPEED := 1800.0
# Resistencia elastica pasado el ultimo item, y rebote al soltar: el extremo se siente.
const OVERSCROLL_RESISTANCE := 0.35
const OVERSCROLL_RETURN := 9.0
# Se alinea sola cuando ya casi no se mueve. Puro tacto; la decision final es de playtest.
const SNAP_SPEED := 10.0
const SNAP_VELOCITY := 60.0
# Rueda del mouse (O13r): en vez del salto seco de una fila entera, cada notch avanza una fraccion
# de fila al instante y el resto lo asienta drive() con easing. El destino sigue siendo una fila
# exacta, asi que no pelea con el snap; y como el rumbo se calcula desde el destino pendiente, el
# notch no vuelve a la fila de la que salio.
const WHEEL_STEP_FRACTION := 0.5
const WHEEL_SNAP_SPEED := 14.0
const STICK_DEADZONE := 0.2
# Mismo umbral que el hold del HUD, para no inventar un tercer tempo.
const REPEAT_MSEC := 400
const REPEAT_RATE_MSEC := 90
# Con menos filas que esto el agrupado por inicial es ruido y no ayuda a saltar.
const GROUPING_MIN_ROWS := 8
const DENY_MSEC := 600
# Margen izquierdo del titulo dentro de la fila. Antes era el ancho de la estrella de favorito
# (O13r: la estrella se elimino); sin ella, ese hueco quedaria como un margen muerto.
const TITLE_PAD_LEFT := 14.0

const COLOR_DIM := Color(0.42, 0.68, 0.76, 1.0)
const COLOR_HOT := Color(0.0, 0.835, 1.0, 1.0)
const COLOR_AMBER := Color(1.0, 0.72, 0.23, 1.0)
const COLOR_PANEL := Color(0.0, 0.05, 0.08, 0.55)
const COLOR_PANEL_HOT := Color(0.0, 0.55, 0.7, 0.4)

# [{ id, title, sort_key, source, favorite, alarm }]
var _rows: Array = []
var _scroll: float = 0.0
var _velocity: float = 0.0
# Destino pendiente de la rueda del mouse, en pixeles. -1 = sin gesto de rueda en curso.
var _wheel_target: float = -1.0
var _stick: float = 0.0
var _step_down: int = 0 # -1 arriba, +1 abajo, 0 nada (cruceta)
var _step_msec: int = 0
var _deny_msec: int = -100000
var _deny_row: int = -1


func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	connect("draw", self, "_draw_drawer")


# --- Contenido ---

# Reconstruye la lista conservando el foco por id: registrar o desregistrar una pantalla con el
# drawer abierto no debe mover lo que el jugador tenia enfocado (FD-305 §5).
func set_rows(rows: Array) -> void:
	var focused_id: String = focused_screen_id()
	_rows = []
	for row in rows:
		var entry: Dictionary = (row as Dictionary).duplicate()
		entry["sort_key"] = _sort_key(String(entry.get("title", entry.get("id", ""))))
		_rows.append(entry)
	_rows.sort_custom(self, "_compare_rows")
	_wheel_target = -1.0
	if not focused_id.empty():
		var again: int = index_of(focused_id)
		if again >= 0:
			_scroll = again * ROW_HEIGHT
			_velocity = 0.0
	_scroll = clamp(_scroll, 0.0, _max_scroll())
	update()


func _compare_rows(a: Dictionary, b: Dictionary) -> bool:
	return String(a["sort_key"]).nocasecmp_to(String(b["sort_key"])) < 0


# Clave de orden sin acentos: el jugador busca por nombre y "Área" va con la A, no despues de la Z.
static func _sort_key(title: String) -> String:
	var out: String = title.to_upper()
	var from: Array = ["Á", "É", "Í", "Ó", "Ú", "Ü", "Ñ", "Ç"]
	var to: Array = ["A", "E", "I", "O", "U", "U", "N", "C"]
	for i in range(from.size()):
		out = out.replace(from[i], to[i])
	return out


func row_count() -> int:
	return _rows.size()


func index_of(id: String) -> int:
	for i in range(_rows.size()):
		if String(_rows[i]["id"]) == id:
			return i
	return -1


func focused_index() -> int:
	if _rows.empty():
		return -1
	return int(clamp(round(_scroll / ROW_HEIGHT), 0, _rows.size() - 1))


func focused_screen_id() -> String:
	var i: int = focused_index()
	return String(_rows[i]["id"]) if i >= 0 else ""


func row_id(index: int) -> String:
	return String(_rows[index]["id"]) if index >= 0 and index < _rows.size() else ""


# Centro de la fila enfocada, para que el arrastre con el hombro arranque desde ahi.
func focused_row_center() -> Vector2:
	var k: float = UIScaleCompensator.scale_for(self)
	var i: int = focused_index()
	return _row_rect(i, k).get_center() if i >= 0 else rect_size * 0.5


# --- Navegacion ---

# El stick: velocidad, no posicion. Se llama una vez por tick con el eje crudo.
func drive(axis: float, dpad: int, delta: float) -> void:
	if _rows.empty():
		return
	_stick = axis if abs(axis) > STICK_DEADZONE else 0.0
	_feed_dpad(dpad)
	if _wheel_target >= 0.0:
		if _stick != 0.0 or dpad != 0:
			# El stick o la cruceta toman el mando: la rueda suelta su destino y no pelea.
			_wheel_target = -1.0
		else:
			_velocity = 0.0
			_scroll = lerp(_scroll, _wheel_target, min(1.0, WHEEL_SNAP_SPEED * delta))
			if abs(_scroll - _wheel_target) <= 0.5:
				_scroll = _wheel_target
				_wheel_target = -1.0
			update()
			return
	if _stick != 0.0:
		_velocity = clamp(_velocity + _stick * ACCEL * delta, -MAX_SCROLL_SPEED, MAX_SCROLL_SPEED)
	_scroll += _velocity * delta
	var limit: float = _max_scroll()
	if _scroll < 0.0 or _scroll > limit:
		# Pasado el tope la lista cede con resistencia y vuelve sola: un clamp seco no se siente.
		var over: float = _scroll if _scroll < 0.0 else _scroll - limit
		_scroll -= over * (1.0 - OVERSCROLL_RESISTANCE)
		_velocity *= OVERSCROLL_RESISTANCE
		if _stick == 0.0:
			_scroll = lerp(_scroll, clamp(_scroll, 0.0, limit), min(1.0, OVERSCROLL_RETURN * delta))
	if _stick == 0.0:
		_velocity = lerp(_velocity, 0.0, min(1.0, FRICTION * delta))
		if abs(_velocity) < SNAP_VELOCITY and _scroll >= 0.0 and _scroll <= limit:
			_velocity = 0.0
			_scroll = lerp(_scroll, round(_scroll / ROW_HEIGHT) * ROW_HEIGHT, min(1.0, SNAP_SPEED * delta))
	update()


# La cruceta da pasos discretos, con auto-repeat al mismo umbral que el hold del HUD.
func _feed_dpad(dpad: int) -> void:
	var now: int = OS.get_ticks_msec()
	if dpad == 0:
		_step_down = 0
		return
	if dpad != _step_down:
		_step_down = dpad
		_step_msec = now
		step_focus(dpad)
		return
	var held: int = now - _step_msec
	if held >= REPEAT_MSEC and (held - REPEAT_MSEC) % REPEAT_RATE_MSEC < 20:
		step_focus(dpad)


func step_focus(direction: int) -> void:
	if _rows.empty():
		return
	_wheel_target = -1.0
	var target: int = int(clamp(focused_index() + direction, 0, _rows.size() - 1))
	if target * ROW_HEIGHT == _scroll:
		return
	_scroll = target * ROW_HEIGHT
	_velocity = 0.0
	Haptics.tick()
	update()


# Rueda del mouse (O13r): no salta una fila entera, se desliza hacia la siguiente. El primer tramo
# entra en el evento (una fraccion de fila, menos de una fila por notch) y drive() completa el resto
# con easing hasta la fila destino. El rumbo se calcula desde el destino pendiente para que dos
# notches seguidos avancen dos filas y ninguno sienta resistencia ni vuelva atras.
func wheel_step(direction: int) -> void:
	if _rows.empty() or direction == 0:
		return
	var base: float = _wheel_target if _wheel_target >= 0.0 else _scroll
	var current: int = int(clamp(round(base / ROW_HEIGHT), 0.0, float(_rows.size() - 1)))
	var target: int = int(clamp(current + direction, 0, _rows.size() - 1))
	_wheel_target = float(target) * ROW_HEIGHT
	_velocity = 0.0
	_scroll = clamp(_scroll + direction * ROW_HEIGHT * WHEEL_STEP_FRACTION, 0.0, _max_scroll())
	update()


# Scroll relativo del mouse/dedo: mueve la lista unos pixeles y el snap de drive() la asienta sola
# en la fila mas cercana. Sin puntero: la fila CENTRADA es la elegida, como el arma del radial.
func scroll_by(pixels: float) -> void:
	if _rows.empty() or pixels == 0.0:
		return
	_wheel_target = -1.0
	_scroll = clamp(_scroll + pixels, 0.0, _max_scroll())
	_velocity = 0.0
	update()


# --- Acciones ---

func activate() -> void:
	activate_row(focused_index())


# Acciona la fila indicada sin tocar el scroll: es el camino del mouse, que elige donde apunta.
func activate_row(index: int) -> void:
	var id: String = row_id(index)
	if not id.empty():
		emit_signal("screen_chosen", id)


# X sobre la fila enfocada. El deny del 7mo favorito se pinta aca; quien decide es SuitOS.
func toggle_favorite(suit_os: Node) -> void:
	toggle_favorite_row(focused_index(), suit_os)


func toggle_favorite_row(index: int, suit_os: Node) -> void:
	if index < 0 or index >= _rows.size() or suit_os == null or not suit_os.has_method("toggle_favorite"):
		return
	var id: String = String(_rows[index]["id"])
	if suit_os.toggle_favorite(id):
		_rows[index]["favorite"] = suit_os.is_favorite(id)
		Haptics.confirm()
		emit_signal("favorite_toggled", id, bool(_rows[index]["favorite"]))
	else:
		_deny(index)
	update()


func _deny(row: int) -> void:
	_deny_row = row
	_deny_msec = OS.get_ticks_msec()
	Haptics.pulse(Haptics.LIFT_MSEC)


func is_denying() -> bool:
	return OS.get_ticks_msec() - _deny_msec < DENY_MSEC


# Un punto (pantalla) sobre una fila: devuelve su indice, o -1. Con el mouse y el dedo la fila se
# elige tocandola, sin pasar por el foco. Toda la fila es fila: la estrella de favorito se elimino
# (O13r), asi que el margen izquierdo ya no es una zona aparte.
func row_at(point: Vector2) -> int:
	var k: float = UIScaleCompensator.scale_for(self)
	for i in range(_rows.size()):
		if _row_rect(i, k).has_point(point):
			return i
	return -1


func focus_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_wheel_target = -1.0
	_scroll = index * ROW_HEIGHT
	_velocity = 0.0
	update()


func _max_scroll() -> float:
	return max(0.0, float(_rows.size() - 1)) * ROW_HEIGHT


# --- Dibujo ---

func _row_rect(index: int, k: float) -> Rect2:
	var center: Vector2 = rect_size * 0.5
	var size := Vector2(ROW_WIDTH, ROW_HEIGHT - 6.0) * k
	var y: float = center.y + (index * ROW_HEIGHT - _scroll) * k - size.y * 0.5
	return Rect2(Vector2(center.x - size.x * 0.5, y), size)


func _draw_drawer() -> void:
	var k: float = UIScaleCompensator.scale_for(self)
	var font: Font = get_font("font")
	if font == null:
		return
	var focus: int = focused_index()
	var grouped: bool = _rows.size() >= GROUPING_MIN_ROWS
	var last_initial: String = ""
	for i in range(_rows.size()):
		var rect: Rect2 = _row_rect(i, k)
		if rect.end.y < 0.0 or rect.position.y > rect_size.y:
			last_initial = _initial_of(i)
			continue
		var row: Dictionary = _rows[i]
		var hot: bool = i == focus
		var denied: bool = i == _deny_row and is_denying()
		draw_rect(rect, COLOR_PANEL_HOT if hot else COLOR_PANEL)
		var edge: Color = COLOR_AMBER if denied else (COLOR_HOT if hot else COLOR_DIM)
		draw_rect(rect, Color(edge.r, edge.g, edge.b, 0.8 if hot else 0.35), false, 2.0 * k if hot else 1.0)

		var initial: String = _initial_of(i)
		if grouped and initial != last_initial:
			# Cabecera de letra solo cuando cambia: lo que hace legible una lista larga sin
			# agregar una jerarquia que no existe.
			draw_string(font, rect.position + Vector2(-22.0 * k, rect.size.y * 0.7), initial,
				Color(COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 0.8))
		last_initial = initial

		var text_color: Color = COLOR_AMBER if denied else (COLOR_HOT if hot else COLOR_DIM)
		if String(row.get("source", "online")) == "offline":
			text_color = Color(text_color.r, text_color.g, text_color.b, 0.55)
		draw_string(font, rect.position + Vector2(TITLE_PAD_LEFT * k, rect.size.y * 0.68),
			tr(String(row.get("title", row.get("id", "")))), text_color)
		var tag: String = ""
		if bool(row.get("alarm", false)):
			tag = "ALERTA"
		elif String(row.get("source", "online")) == "offline":
			tag = "OFFLINE"
		if not tag.empty():
			draw_string(font, rect.position + Vector2(rect.size.x - 96.0 * k, rect.size.y * 0.68),
				tr(tag), COLOR_AMBER if tag == "ALERTA" else Color(COLOR_DIM.r, COLOR_DIM.g, COLOR_DIM.b, 0.6))
	if is_denying():
		draw_string(font, Vector2(rect_size.x * 0.5 - 70.0 * k, rect_size.y - 40.0 * k),
			tr("RADIAL LLENO"), COLOR_AMBER)


func _initial_of(index: int) -> String:
	return String(_rows[index]["sort_key"]).substr(0, 1)
