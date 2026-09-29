extends Reference

# RemoteSimStats.gd - FD-316 (tarea E): acumulador de ventanas para la instrumentacion
# del render-esclavo y del sim host. Por frame solo suma/cuenta (sin alocaciones
# grandes); los percentiles se calculan una vez por ventana, al cerrarla.

const WINDOW_MS := 5000

# Instante (OS.get_ticks_msec) en que arranco la ventana actual. Publico para que los
# tests puedan forzar el vencimiento y para inspeccionarlo desde telemetria.
var window_start_ms: int = 0
var _samples: Dictionary = {}
var _sums: Dictionary = {}
var _counts: Dictionary = {}
var _maxima: Dictionary = {}

func _init() -> void:
	reset(OS.get_ticks_msec())

func reset(now_ms: int) -> void:
	window_start_ms = now_ms
	_samples.clear()
	_sums.clear()
	_counts.clear()
	_maxima.clear()

func is_due(now_ms: int) -> bool:
	return now_ms - window_start_ms >= WINDOW_MS

func elapsed_ms(now_ms: int) -> int:
	return now_ms - window_start_ms

# Muestra cruda para percentiles (RTT): una entrada chica por evento, no por frame.
func add_sample(name: String, value: float) -> void:
	if not _samples.has(name):
		_samples[name] = []
	_samples[name].push_back(value)

# Acumulador para promedios (suma) y contadores (tally).
func add(name: String, value: float) -> void:
	_sums[name] = float(_sums.get(name, 0.0)) + value

func tally(name: String, inc: int = 1) -> void:
	_counts[name] = int(_counts.get(name, 0)) + inc

# Maximo de la ventana sin guardar todas las muestras (gaps).
func observe_max(name: String, value: float) -> void:
	if value > float(_maxima.get(name, 0.0)):
		_maxima[name] = value

func sum(name: String) -> float:
	return float(_sums.get(name, 0.0))

func count(name: String) -> int:
	return int(_counts.get(name, 0))

func sample_count(name: String) -> int:
	return (_samples.get(name, []) as Array).size()

func max_value(name: String) -> float:
	return float(_maxima.get(name, 0.0))

# Percentil por rango mas cercano sobre la ventana cerrada. arr.sort() se paga aca, una
# vez por ventana, no en el camino por frame.
func percentile(name: String, p: float) -> float:
	var arr: Array = _samples.get(name, [])
	if arr.empty():
		return 0.0
	arr.sort()
	var idx := int(round(p * float(arr.size() - 1)))
	return float(arr[int(clamp(idx, 0, arr.size() - 1))])
