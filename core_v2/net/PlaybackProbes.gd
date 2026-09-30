extends Reference

# PlaybackProbes.gd - FD-316 (tarea FF): sondas A/B del costo FIJO de render del
# render-esclavo. El playback de la traza (tarea DD, ODISEA_SNAPSHOT_PLAYBACK) mide un
# render_ms casi constante que no baja con geometria ni draw calls; estas sondas lo
# descomponen apagando UNA cosa por ventana y comparando contra una ventana base.
#
# La traza se parte en ventanas de WINDOW_FRAMES frames y en cada una se apaga un unico
# factor, restaurando el estado EXACTO al cerrar la ventana (y al terminar/cortar el
# playback). Cada muestra del playback sale etiquetada con la sonda activa ("sonda").
# Al final se imprime la mediana de frame_ms/render_ms por sonda contra la base.
#
# Sondas (una por ventana, en este orden):
#   base  - sin tocar nada (referencia).
#   3d    - camara activa con cull_mask=0: no dibuja geometria 3D.
#   ui    - oculta todos los CanvasLayer y Controls (HUD SuitOS, sub-Viewports, overlays).
#   env   - quita el Environment del World (WorldEnvironment / default_env): sin glow/tonemap/fog.
#   scale - SettingsManager.render_scale a 1.0 (quita el upscale del viewport escalado).
#   vsync - OS.vsync_enabled=false: deja de esperar el swap (mide el costo real de GPU/CPU).
#
# Se activa con ODISEA_PLAYBACK_PROBES=1. Es solo perf: no entra a replay_sync ni cambia
# la simulacion; toda mutacion se guarda y se revierte.

const PROBES_ENV := "ODISEA_PLAYBACK_PROBES"

# Frames por ventana. Con la traza del benchmark (~400 muestras alimentadas) entran la
# base y las 5 sondas sin cortar la comparacion.
var window_frames: int = 60

# Una ventana por elemento. Orden fijo para que la base quede primero.
var sequence: Array = ["base", "3d", "ui", "env", "scale", "vsync"]

var _tree = null
var _enabled := false
# Indice de la ventana actual dentro de sequence; == sequence.size() cuando ya no hay
# sondas (quedo todo restaurado).
var _window_index := 0
var _frames_in_window := 0
var _active := ""
# Estado guardado de la sonda activa (para restaurar exacto).
var _saved: Dictionary = {}
# Camara forzada para la sonda 3d (tests con un viewport sin camara activa detectable;
# en runtime se resuelve la camara real via CinematicManager).
var camera_override = null
# Muestras por sonda: { sonda: {"frame_ms": [], "render_ms": []} }.
var _samples: Dictionary = {}
var _closed := false

func _init(p_tree = null, p_enabled: bool = false) -> void:
	_tree = p_tree
	_enabled = p_enabled or _env_enabled()

# Activa las sondas por entorno; se evalua en la construccion.
func _env_enabled() -> bool:
	return OS.get_environment(PROBES_ENV).strip_edges().to_lower() in ["1", "true", "yes", "on"]

func is_enabled() -> bool:
	return _enabled

# Sonda activa en este frame ("" si las sondas no corren).
func active_probe() -> String:
	return _active

# Avanza una muestra del playback. Devuelve la etiqueta de sonda del frame ("" si no
# corren) y gestiona los cambios de ventana restaurando/aplicando en el limite.
func step(frame_ms: float, render_ms: float) -> String:
	if not _enabled or _closed:
		return ""
	if _window_index >= sequence.size():
		# Ya pasaron todas las sondas: todo restaurado, frames sin etiqueta.
		return ""
	if _frames_in_window >= window_frames:
		_restore_current()
		_window_index += 1
		_frames_in_window = 0
		if _window_index >= sequence.size():
			_active = ""
			return ""
	_apply_current()
	_record(frame_ms, render_ms)
	_frames_in_window += 1
	return _active

# Cierra las sondas: restaura el estado exacto, imprime las medianas por sonda contra la
# base y devuelve el resumen para la traza de perf. Idempotente.
func finish() -> Dictionary:
	if not _enabled:
		return {}
	_restore_current()
	_closed = true
	var summary := summary()
	_print_report(summary)
	return summary

# Restaura (si quedo algo aplicado) sin cerrar: para cortes del playback a mitad de una
# ventana. Idempotente.
func restore_all() -> void:
	_restore_current()

# Resumen de medianas por sonda. Vacio si no hay muestras.
func summary() -> Dictionary:
	if _samples.empty():
		return {}
	var base_frame := _median(_samples.get("base", {}).get("frame_ms", []))
	var base_render := _median(_samples.get("base", {}).get("render_ms", []))
	var probes: Dictionary = {}
	for label in _samples:
		var frame_ms := _median(_samples[label]["frame_ms"])
		var render_ms := _median(_samples[label]["render_ms"])
		probes[label] = {
			"n": _samples[label]["frame_ms"].size(),
			"frame_ms_p50": frame_ms,
			"render_ms_p50": render_ms,
			"frame_ms_p50_delta": frame_ms - base_frame if base_frame >= 0.0 else -1.0,
			"render_ms_p50_delta": render_ms - base_render if base_render >= 0.0 else -1.0,
		}
	return {"window_frames": window_frames, "probes": probes}

# --- ventana y acumulacion ---

func _apply_current() -> void:
	var probe := String(sequence[_window_index]) if _window_index < sequence.size() else ""
	if probe == _active:
		return
	# Cambio de sonda sin pasar por _restore_current (no deberia pasar): no aplicar encima.
	if _active != "":
		_restore_current()
	_active = probe
	_saved = {}
	match probe:
		"3d":
			_apply_3d()
		"ui":
			_apply_ui()
		"env":
			_apply_env()
		"scale":
			_apply_scale()
		"vsync":
			_apply_vsync()
		_:
			pass

func _restore_current() -> void:
	if _active == "" or _saved.empty():
		_active = ""
		_saved = {}
		return
	match _active:
		"3d":
			_restore_3d()
		"ui":
			_restore_ui()
		"env":
			_restore_env()
		"scale":
			_restore_scale()
		"vsync":
			_restore_vsync()
		_:
			pass
	_saved = {}
	_active = ""

func _record(frame_ms: float, render_ms: float) -> void:
	if _active == "":
		return
	if not _samples.has(_active):
		_samples[_active] = {"frame_ms": [], "render_ms": []}
	_samples[_active]["frame_ms"].push_back(frame_ms)
	_samples[_active]["render_ms"].push_back(render_ms)

# --- sonda 3d: cull_mask=0 en la camara activa ---

func _active_camera():
	if camera_override != null and is_instance_valid(camera_override) and camera_override is Camera:
		return camera_override
	if _tree == null or _tree.root == null:
		return null
	var cinematic = _tree.root.get_node_or_null("CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var cam = cinematic.call("get_active_camera")
		if cam != null and is_instance_valid(cam) and cam is Camera:
			return cam
	var vp = _tree.root
	return vp.get_camera() if vp is Viewport else null

func _apply_3d() -> void:
	var cam = _active_camera()
	if cam == null:
		return
	_saved["cam"] = cam
	_saved["cull_mask"] = cam.cull_mask
	cam.cull_mask = 0

func _restore_3d() -> void:
	if _saved.has("cam") and is_instance_valid(_saved["cam"]):
		_saved["cam"].cull_mask = int(_saved["cull_mask"])

# --- sonda ui: oculta CanvasLayer y Controls ---

func _apply_ui() -> void:
	var touched: Array = []
	if _tree == null:
		return
	var stack: Array = [_tree.root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if not (node is CanvasLayer or node is Control):
			continue
		touched.append([node, node.visible])
		node.visible = false
	_saved["ui"] = touched

func _restore_ui() -> void:
	for entry in _saved.get("ui", []):
		var node = entry[0]
		if is_instance_valid(node):
			node.visible = bool(entry[1])

# --- sonda env: quita el Environment ---

func _apply_env() -> void:
	var touched: Array = []
	if _tree == null or _tree.root == null:
		return
	# El Environment vive en el World del viewport (default_env.tres o el que registra el
	# WorldEnvironment). Se guarda ANTES de tocar nodos para que la restauracion no dependa
	# del orden.
	if _tree.root is Viewport:
		var world = _tree.root.find_world()
		if world != null:
			touched.append([world, "environment", world.environment])
			world.environment = null
	var stack: Array = [_tree.root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if node is WorldEnvironment:
			touched.append([node, "environment", node.environment])
			node.environment = null
	_saved["env"] = touched

func _restore_env() -> void:
	for entry in _saved.get("env", []):
		var node = entry[0]
		if is_instance_valid(node):
			node.set(String(entry[1]), entry[2])

# --- sonda scale: render_scale 1.0 ---

func _settings_manager():
	if _tree == null or _tree.root == null:
		return null
	return _tree.root.get_node_or_null("SettingsManager")

func _apply_scale() -> void:
	var sm = _settings_manager()
	if sm == null or not ("render_scale" in sm):
		return
	_saved["sm"] = sm
	_saved["render_scale"] = sm.render_scale
	sm.render_scale = 1.0
	if sm.has_method("apply_render_resolution"):
		sm.call("apply_render_resolution")

func _restore_scale() -> void:
	if _saved.has("sm") and is_instance_valid(_saved["sm"]):
		_saved["sm"].render_scale = float(_saved["render_scale"])
		if _saved["sm"].has_method("apply_render_resolution"):
			_saved["sm"].call("apply_render_resolution")

# --- sonda vsync ---

func _apply_vsync() -> void:
	_saved["vsync"] = OS.vsync_enabled
	OS.vsync_enabled = false

func _restore_vsync() -> void:
	if _saved.has("vsync"):
		OS.vsync_enabled = bool(_saved["vsync"])

# --- reporte ---

func _median(values: Array) -> float:
	var n: int = values.size()
	if n <= 0:
		return -1.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5

func _print_report(summary: Dictionary) -> void:
	if summary.empty():
		return
	var probes: Dictionary = summary["probes"]
	var base: Dictionary = probes.get("base", {})
	var base_frame: float = float(base.get("frame_ms_p50", -1.0))
	var base_render: float = float(base.get("render_ms_p50", -1.0))
	print("[PlaybackProbes] sondas A/B (", window_frames, " frames/ventana, base frame_ms_p50=",
		"%.2f" % base_frame, " render_ms_p50=", "%.2f" % base_render, ")")
	for label in sequence:
		if not probes.has(label):
			continue
		var p: Dictionary = probes[label]
		print("[PlaybackProbes] ", label,
			" n=", p["n"],
			" frame_ms_p50=", "%.2f" % p["frame_ms_p50"],
			" (d=", "%.2f" % p["frame_ms_p50_delta"], ")",
			" render_ms_p50=", "%.2f" % p["render_ms_p50"],
			" (d=", "%.2f" % p["render_ms_p50_delta"], ")")
