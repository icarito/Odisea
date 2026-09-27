extends Reference

# debug_metrics.gd - Colector de metricas para el HUD de debug (port de gdtk
# addons/debug_hud/debug_metrics.gd, ver SPEC-hud.md/SPEC-hud-remote.md en el repo gdtk).
#
# Muestrea los monitores de Performance en buffers circulares, mantiene el cursor de
# DebugLog (si el motor lo trae) y expone snapshot(). No depende de ImGui: corre igual
# en el binario pinneado de Odisea (v0.5.3, sin modulo imgui) que en uno con gdtk.
#
# DebugHud.gd (autoload) usa una sola instancia como colector local; no hay "espejo"
# remoto aca (Odisea manda el resumen al telefono via el contrato HUDable/SuitOS, no
# via el transporte TCP propio de gdtk).

const MAX_SAMPLES := 600
const MAX_LOGS := 2000

# Series que llegan por lineas de log del fork con FRT_PERF (no son monitores).
const FRT_SERIES := ["gpu", "frt_frame", "frt_idle", "frt_phys", "frt_phys_sum",
	"frt_steps", "frt_render", "frt_sync", "frt_other", "frt_fps"]

const MB := 0.0009765625 # 1/1024/1024

# [nombre, monitor, escala] (la escala deja el valor en la unidad que se grafica).
var MONITORS := []

# 0 = muestrear cada frame; > 0 limita la tasa del colector.
var sample_hz := 0.0
# Contador de muestras (equivale al indice del ultimo dato de cada serie).
var frame := 0
# nombre -> Array de valores (buffer circular de MAX_SAMPLES).
var series := {}
# nombre -> ultimo valor.
var latest := {}
# Buffer circular de dicts de DebugLog {id, time_ms, text, is_error}.
var logs := []
# {tier, flat, driver, gpu, render_local, frt_perf, sample_hz, frame}.
var profile := {}

var has_frt := false

var _frt := {}
var _log_cursor := 0
var _snapshot_log_cursor := 0


func _init() -> void:
	MONITORS = [
		["TIME_FPS", Performance.TIME_FPS, 1.0],
		["TIME_PROCESS", Performance.TIME_PROCESS, 1000.0],
		["TIME_PHYSICS_PROCESS", Performance.TIME_PHYSICS_PROCESS, 1000.0],
		["MEMORY_STATIC", Performance.MEMORY_STATIC, MB],
		["MEMORY_DYNAMIC", Performance.MEMORY_DYNAMIC, MB],
		["MEMORY_STATIC_MAX", Performance.MEMORY_STATIC_MAX, MB],
		["MEMORY_DYNAMIC_MAX", Performance.MEMORY_DYNAMIC_MAX, MB],
		["MEMORY_MESSAGE_BUFFER_MAX", Performance.MEMORY_MESSAGE_BUFFER_MAX, MB],
		["RENDER_DRAW_CALLS_IN_FRAME", Performance.RENDER_DRAW_CALLS_IN_FRAME, 1.0],
		["RENDER_2D_DRAW_CALLS_IN_FRAME", Performance.RENDER_2D_DRAW_CALLS_IN_FRAME, 1.0],
		["RENDER_OBJECTS_IN_FRAME", Performance.RENDER_OBJECTS_IN_FRAME, 1.0],
		["RENDER_VERTICES_IN_FRAME", Performance.RENDER_VERTICES_IN_FRAME, 1.0],
		["RENDER_MATERIAL_CHANGES_IN_FRAME", Performance.RENDER_MATERIAL_CHANGES_IN_FRAME, 1.0],
		["RENDER_SHADER_CHANGES_IN_FRAME", Performance.RENDER_SHADER_CHANGES_IN_FRAME, 1.0],
		["RENDER_SURFACE_CHANGES_IN_FRAME", Performance.RENDER_SURFACE_CHANGES_IN_FRAME, 1.0],
		["RENDER_2D_ITEMS_IN_FRAME", Performance.RENDER_2D_ITEMS_IN_FRAME, 1.0],
		["RENDER_VIDEO_MEM_USED", Performance.RENDER_VIDEO_MEM_USED, MB],
		["RENDER_TEXTURE_MEM_USED", Performance.RENDER_TEXTURE_MEM_USED, MB],
		["RENDER_VERTEX_MEM_USED", Performance.RENDER_VERTEX_MEM_USED, MB],
		["RENDER_USAGE_VIDEO_MEM_TOTAL", Performance.RENDER_USAGE_VIDEO_MEM_TOTAL, MB],
		["OBJECT_COUNT", Performance.OBJECT_COUNT, 1.0],
		["OBJECT_RESOURCE_COUNT", Performance.OBJECT_RESOURCE_COUNT, 1.0],
		["OBJECT_NODE_COUNT", Performance.OBJECT_NODE_COUNT, 1.0],
		["OBJECT_ORPHAN_NODE_COUNT", Performance.OBJECT_ORPHAN_NODE_COUNT, 1.0],
		["PHYSICS_2D_ACTIVE_OBJECTS", Performance.PHYSICS_2D_ACTIVE_OBJECTS, 1.0],
		["PHYSICS_2D_COLLISION_PAIRS", Performance.PHYSICS_2D_COLLISION_PAIRS, 1.0],
		["PHYSICS_2D_ISLAND_COUNT", Performance.PHYSICS_2D_ISLAND_COUNT, 1.0],
		["PHYSICS_3D_ACTIVE_OBJECTS", Performance.PHYSICS_3D_ACTIVE_OBJECTS, 1.0],
		["PHYSICS_3D_COLLISION_PAIRS", Performance.PHYSICS_3D_COLLISION_PAIRS, 1.0],
		["PHYSICS_3D_ISLAND_COUNT", Performance.PHYSICS_3D_ISLAND_COUNT, 1.0],
		["AUDIO_OUTPUT_LATENCY", Performance.AUDIO_OUTPUT_LATENCY, 1.0],
	]
	series = {}
	latest = {}
	logs = []
	profile = {
		"tier": "unknown",
		"flat": false,
		"driver": _driver_name(),
		"gpu": -1.0,
		"render_local": true,
		"frt_perf": false,
		"sample_hz": 0.0,
		"frame": 0,
	}


func _driver_name() -> String:
	var driver: int = OS.get_current_video_driver()
	var name: String = OS.get_video_driver_name(driver)
	if name == "":
		name = str(driver)
	return name


func sample() -> void:
	var t0: int = OS.get_ticks_usec()
	_fetch_logs()
	for entry in MONITORS:
		_push(entry[0], Performance.get_monitor(entry[1]) * entry[2])
	if has_frt:
		for name in FRT_SERIES:
			_push(name, _frt.get(name, 0.0))
	var cost: float = float(OS.get_ticks_usec() - t0)
	_push("collector_us", cost)
	frame += 1
	if frame % 60 == 0:
		profile["driver"] = _driver_name()
	profile["sample_hz"] = sample_hz
	profile["frame"] = frame


func _push(name: String, value: float) -> void:
	var arr = series.get(name)
	if arr == null:
		arr = []
		series[name] = arr
	arr.append(value)
	while arr.size() > MAX_SAMPLES:
		arr.pop_front()
	latest[name] = value


func _series_len() -> int:
	var arr = series.get("TIME_FPS")
	if arr == null:
		return 0
	return arr.size()


# Crea las series FRT_PERF rellenando el pasado con 0 para que queden alineadas
# con los monitores (asi snapshot() puede cortar por indice).
func _init_frt_series() -> void:
	var n: int = _series_len()
	for name in FRT_SERIES:
		if not series.has(name):
			var arr := []
			arr.resize(n)
			for i in range(n):
				arr[i] = 0.0
			series[name] = arr


func _fetch_logs() -> void:
	if not Engine.has_singleton("DebugLog"):
		return
	var debug_log = Engine.get_singleton("DebugLog")
	var incoming: Array = debug_log.get_entries(_log_cursor)
	for entry in incoming:
		logs.append(entry)
		_log_cursor = int(entry["id"])
		_ingest_log(str(entry["text"]))
	while logs.size() > MAX_LOGS:
		logs.pop_front()


# Parsea las lineas del perfilador del fork. [FRT_GPU] trae el ms de GPU y
# [FRT_PERF] el resumen de tramos de CPU cada 120 frames.
func _ingest_log(text: String) -> void:
	if text.begins_with("[FRT_PERF]"):
		if not has_frt:
			has_frt = true
			_init_frt_series()
		_parse_frt(text.substr("[FRT_PERF]".length()))
		profile["frt_perf"] = true
	elif text.begins_with("[FRT_GPU]"):
		var gi: int = text.find("gpu=")
		if gi < 0:
			return
		if not has_frt:
			has_frt = true
			_init_frt_series()
		var rest: String = text.substr(gi + 4)
		var sp: int = rest.find("ms")
		if sp >= 0:
			_frt["gpu"] = float(rest.substr(0, sp))
			profile["gpu"] = _frt["gpu"]
			profile["frt_perf"] = true


func _parse_frt(s: String) -> void:
	for token in s.split(" ", false):
		var eq: int = token.find("=")
		if eq <= 0:
			continue
		var key: String = token.substr(0, eq)
		_frt["frt_" + key] = float(token.substr(eq + 1))


func stats(name: String) -> Dictionary:
	var arr = series.get(name)
	if arr == null or arr.size() == 0:
		return {"latest": latest.get(name, 0.0), "min": 0.0, "max": 0.0, "avg": 0.0, "n": 0}
	var mn = arr[0]
	var mx = arr[0]
	var sum := 0.0
	for value in arr:
		if value < mn:
			mn = value
		if value > mx:
			mx = value
		sum += value
	return {"latest": arr[arr.size() - 1], "min": mn, "max": mx, "avg": sum / float(arr.size()), "n": arr.size()}


# Snapshot compacto con los valores nuevos desde since_frame (-1 = todo el
# buffer), el ultimo valor de cada serie, los logs nuevos y el perfil.
func snapshot(since_frame: int = -1) -> Dictionary:
	var out_series := {}
	for name in series.keys():
		var arr = series[name]
		var n: int = arr.size()
		var start := 0
		if since_frame >= 0:
			var oldest: int = frame - n
			start = since_frame - oldest + 1
			if start < 0:
				start = 0
		if start < n:
			out_series[name] = arr.slice(start, n - 1)
		else:
			out_series[name] = []
	var new_logs := []
	for entry in logs:
		if int(entry["id"]) > _snapshot_log_cursor:
			new_logs.append(entry)
	if new_logs.size() > 0:
		_snapshot_log_cursor = int(new_logs[new_logs.size() - 1]["id"])
	return {
		"frame": frame,
		"time": float(OS.get_ticks_msec()) / 1000.0,
		"series": out_series,
		"latest": latest.duplicate(),
		"logs": new_logs,
		"profile": profile.duplicate(),
	}


# Ultimos n valores de una serie (para sparklines cortas: HUDable "Rendimiento").
func tail(name: String, n: int) -> Array:
	var arr = series.get(name)
	if arr == null:
		return []
	var size: int = arr.size()
	if size <= n:
		return arr.duplicate()
	return arr.slice(size - n, size - 1)


# Alimenta un DebugMetrics "espejo" con un snapshot remoto (no usado por Odisea hoy;
# se conserva por si algun consumidor externo lo necesita, ver README).
func apply_snapshot(snap: Dictionary) -> void:
	var incoming: Dictionary = snap.get("series", {})
	for name in incoming.keys():
		var arr = series.get(name)
		if arr == null:
			arr = []
			series[name] = arr
		for value in incoming[name]:
			arr.append(value)
		while arr.size() > MAX_SAMPLES:
			arr.pop_front()
	var incoming_latest: Dictionary = snap.get("latest", {})
	for name in incoming_latest.keys():
		latest[name] = incoming_latest[name]
	for entry in snap.get("logs", []):
		logs.append(entry)
	while logs.size() > MAX_LOGS:
		logs.pop_front()
	var incoming_profile = snap.get("profile", null)
	if incoming_profile != null:
		profile = incoming_profile.duplicate()
	frame = int(snap.get("frame", frame))
	if profile.has("gpu"):
		has_frt = bool(profile.get("frt_perf", has_frt))
