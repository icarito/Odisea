extends Node

# Presupuesto adaptativo GENERAL para sistemas visuales "lentos" (GasParticleManager,
# PipeCoolantRun, luces, cualquier cosa que un dispositivo debil no necesite al 100%).
#
# Diseño invertido respecto a AdaptiveRenderScale/MobileLightBudget: esos arrancan al
# maximo y SOLO bajan (nunca vuelven a subir, documentado en MobileLightBudget.gd —
# GLES2 recompila variantes de shader al cambiar cuantas luces alcanzan una superficie,
# y oscilar pagaria ese costo una y otra vez). Este autoload arranca CONSERVADOR y sube
# de a poco si el dispositivo aguanta, en vez de arrancar caro y podar despues. Sirve
# para sistemas cuyo "nivel" es cuantas instancias trabajan a la vez, no un parametro
# de render global — subir no dispara recompilacion de shader, solo activa mas
# instancias de un componente que ya existe.
#
# Uso: cualquier sistema que quiera escalar con el budget se registra una vez con
# register_consumer(), recibe niveles incrementales via un Callable/callback, y el
# autoload decide cuando subir o bajar el nivel global segun fps sostenido.
#
#   AdaptiveVisualBudget.register_consumer(self, "_on_budget_level_changed", 4)
#   func _on_budget_level_changed(level: int, max_level: int) -> void:
#       # level va de 0 (minimo, arranque) a max_level (dispositivo aguanta todo)
#       ...
#
# El nivel es GLOBAL y compartido entre todos los consumers: todos suben o bajan
# juntos, un escalon a la vez, así ningún consumer individual necesita su propia
# lógica de fps — solo reacciona a los niveles que le tocan.
#
# LECCION del sistema anterior (OptionalNodeManager, eliminado por heurísticas de
# plataforma demasiado simples que se activaban donde no hacía falta — ver
# git b7636f07): el fix no era solo medir mejor, era que el enfoque "instanciar/
# destruir por nivel" es una trampa. El costo de instanciar un nodo en Godot no se
# recupera facil desactivandolo despues, y volver a instanciarlo cuesta de nuevo.
# Los CONSUMERS de este budget NUNCA deben crear/destruir nodos por nivel: las
# instancias tienen que existir siempre (como GasParticleManager/PipeCoolantRun, que
# ya son parte fija de la escena), y el nivel solo decide CUANTAS de las que YA
# EXISTEN tienen su _physics_process activo — el mismo patron que PhysicsProcessLOD.gd
# ya usa para distancia, ahora combinado con presupuesto global.

const DISABLE_ENV := "ODISEA_DISABLE_VISUAL_BUDGET"
const MOBILE_ENV := "ODISEA_FORCE_MOBILE_PROFILE"

# Niveles totales del budget. 0 = arranque conservador, MAX_LEVEL = todo activo.
export(int, 1, 10) var max_level := 4
# fps por debajo de esto sostenido: baja un nivel.
export(float, 5.0, 60.0, 1.0) var fps_floor := 20.0
# fps por encima de esto sostenido: sube un nivel.
export(float, 10.0, 90.0, 1.0) var fps_ceiling := 40.0
export(float, 0.5, 20.0, 0.5) var seconds_to_drop := 2.0
# Subir es mas lento que bajar a proposito: un pico de fps no debe animar al budget a
# subir de golpe, pero un frame malo si debe hacerlo bajar rapido (misma asimetria que
# AdaptiveRenderScale).
export(float, 1.0, 30.0, 0.5) var seconds_to_raise := 6.0
# Los primeros segundos de una escena estan dominados por la carga, no por el
# rendimiento real.
export(float, 0.0, 30.0, 0.5) var grace_seconds := 5.0
export(bool) var desktop_starts_at_max := true

var _level := 0
var _below_floor := 0.0
var _above_ceiling := 0.0
var _grace := 0.0
var _enabled := true
# Array de {node: WeakRef, method: String}
var _consumers := []


func _ready() -> void:
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		_enabled = false
		set_process(false)
		return
	if desktop_starts_at_max and not _is_mobile():
		_level = max_level
		set_process(false)
		return
	_level = 0
	_grace = grace_seconds
	set_process(true)


func _is_mobile() -> bool:
	if OS.get_environment(MOBILE_ENV) in ["1", "true", "yes", "on"]:
		return true
	return OS.get_name() in ["Android", "iOS"]


# node: el consumer. method: nombre del metodo a llamar como method(level:int, max_level:int).
# Se llama una vez de inmediato con el nivel actual, y de nuevo cada vez que el nivel
# global cambia. own_max_level permite que un consumer tenga menos escalones que el
# budget global (ej. un sistema con solo 2 estados en vez de 4): se remapea
# proporcionalmente, así que 0 y max_level global siempre coinciden con los extremos.
func register_consumer(node: Object, method: String, own_max_level: int = -1) -> void:
	if not is_instance_valid(node) or not node.has_method(method):
		return
	_consumers.append({"ref": weakref(node), "method": method, "own_max": own_max_level if own_max_level > 0 else max_level})
	_notify_one(_consumers.back())


func get_level() -> int:
	return _level


func _process(delta: float) -> void:
	if not _enabled:
		return
	if _grace > 0.0:
		_grace -= delta
		return
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	if fps <= 0.0:
		return
	if fps < fps_floor:
		_below_floor += delta
		_above_ceiling = 0.0
	elif fps > fps_ceiling:
		_above_ceiling += delta
		_below_floor = 0.0
	else:
		_below_floor = 0.0
		_above_ceiling = 0.0

	if _below_floor >= seconds_to_drop and _level > 0:
		_set_level(_level - 1)
	elif _above_ceiling >= seconds_to_raise and _level < max_level:
		_set_level(_level + 1)


func _set_level(new_level: int) -> void:
	new_level = int(clamp(new_level, 0, max_level))
	if new_level == _level:
		return
	_level = new_level
	_below_floor = 0.0
	_above_ceiling = 0.0
	var alive := []
	for c in _consumers:
		if _notify_one(c):
			alive.append(c)
	_consumers = alive


func _notify_one(c: Dictionary) -> bool:
	var node = c.ref.get_ref()
	if node == null or not is_instance_valid(node):
		return false
	var own_max: int = c.own_max
	var remapped: int = _level if own_max == max_level else int(round(float(_level) / float(max(max_level, 1)) * float(own_max)))
	node.call(c.method, remapped, own_max)
	return true


func get_stats() -> Dictionary:
	return {
		"level": _level,
		"max_level": max_level,
		"consumers": _consumers.size(),
		"enabled": _enabled,
	}
