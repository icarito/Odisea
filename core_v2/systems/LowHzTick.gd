extends Reference

# FD-316 (tarea GG): espacia un refresco de UI en tier LOW a ~10 Hz.
#
# Mismo contrato que LowTierTickStride pero en segundos: step(delta) devuelve el delta
# acumulado cuando toca refrescar y -1.0 cuando no. Fuera del tier LOW (o con el A/B
# ODISEA_LOW_UI_OPT=0) devuelve el mismo delta en cada llamada, asi el llamador no cambia
# de comportamiento. El acumulado viaja al llamador para que el tiempo no se pierda
# (un fade o un contador de inactividad sigue avanzando el reloj real).
#
#   var _paso_hz = preload("res://core_v2/systems/LowHzTick.gd").new()
#   func _process(delta):
#       delta = _paso_hz.step(delta)
#       if delta < 0.0:
#           return

const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")

var _hz: float = LowUiOptScript.HZ
var _acumulado := 0.0

func _init(hz: float = -1.0) -> void:
	if hz > 0.0:
		_hz = hz

func step(delta: float) -> float:
	if not LowUiOptScript.enabled():
		_acumulado = 0.0
		return delta
	_acumulado += delta
	if _acumulado < 1.0 / _hz:
		return -1.0
	var total := _acumulado
	_acumulado = 0.0
	return total
