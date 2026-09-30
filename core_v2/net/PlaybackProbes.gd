extends Reference

# PlaybackProbes.gd - FD-316: sondas A/B del costo FIJO de render del render-esclavo. El
# playback de la traza (tarea DD, ODISEA_SNAPSHOT_PLAYBACK) mide un render_ms casi constante
# que no baja con geometria ni draw calls; estas sondas lo descomponen apagando UNA cosa.
#
# Tarea JJ: las sondas originales (FF/GG) partian la traza en ventanas de 60 frames y cada
# sonda media su propia porcion del recorrido. Eso confunde la VARIACION DE RUTA con el costo:
# la ventana "base" (63 ms) no representaba la mediana global (58.7 ms), asi que ocultar algo
# barato parecia ahorrar y ocultar algo caro parecia costar. Ahora las sondas se INTERCALAN: se
# alternan bloques cortos base/sonda (por defecto 10 frames cada uno, con `discard_frames` de
# descarte tras cada cambio) rotando las sondas a lo largo de TODO el recorrido. Cada bloque de
# sonda se compara contra los bloques base ADYACENTES (delta pareado) y se reporta la mediana y
# el rango p25-p75 de esos deltas por sonda.
#
# Sondas: base (referencia), 3d (cull_mask=0 en la camara), ui (CanvasLayer + Controls),
# env (Environment del World), scale (render_scale 1.0), vsync (OS.vsync_enabled=false) y una
# por subarbol de HUD (subtree:widgets, subtree:mobileui, subtree:overlays,
# subtree:virtualmouse, subtree:debugconsole, subtree:vpalways).
#
# Toggles de corrida completa (A/B verdaderos, una cosa apagada TODA la corrida): se leen al
# arrancar el playback y se restauran exacto al salir. Sirven para validar contra la mediana
# global cuando el intercalado no alcanza:
#   ODISEA_BENCH_NO_UI=1  - oculta todos los CanvasLayer/Controls de HUD.
#   ODISEA_BENCH_NO_3D=1  - cull_mask=0 en la camara activa.
#   ODISEA_BENCH_NO_ENV=1 - sin Environment.
#
# Se activa el intercalado con ODISEA_PLAYBACK_PROBES=1. Es solo perf: no entra a replay_sync
# ni cambia la simulacion; toda mutacion se guarda y se revierte.

const PROBES_ENV := "ODISEA_PLAYBACK_PROBES"
const REFERENCE_LABEL := "base"
const VP_ALWAYS_LABEL := "subtree:vpalways"
const BENCH_NO_UI_ENV := "ODISEA_BENCH_NO_UI"
const BENCH_NO_3D_ENV := "ODISEA_BENCH_NO_3D"
const BENCH_NO_ENV_ENV := "ODISEA_BENCH_NO_ENV"
# Tarea HH: medidor de refresco de los Viewports de widget. Responde por que el ahorro a 10 Hz
# de los widgets no baja su costo (composicion del canvas vs. otro sistema en UPDATE_ALWAYS).
const HudRedrawMeterScript = preload("res://core_v2/net/HudRedrawMeter.gd")

# Frames utiles por bloque (base o sonda) y frames de descarte tras cada cambio de bloque
# (deja asentar el pipeline/viewport antes de medir). Bloques cortos para que cada sonda
# muestree varios tramos del recorrido en vez de uno solo.
var block_frames: int = 10
var discard_frames: int = 2
# Rota la secuencia indefinidamente mientras dure la traza (default). false la agota una vez.
var loop_schedule: bool = true

# Sondas en orden de aparicion. La referencia "base" se ignora aca: el intercalado la inserta
# entre sondas y en los extremos (ver _build_schedule).
var sequence: Array = ["base", "3d", "ui", "env", "scale", "vsync"]

# Tarea GG: sondas por subarbol de HUD. `include_subtrees` las descubre del arbol la primera
# vez que corre un step; `_subtree_probes` mapea etiqueta -> nodo (tests y overrides).
var include_subtrees: bool = true
var _subtree_probes: Dictionary = {}
var _subtrees_built := false
# Tarea HH: muestrea el refresco de los Viewports de widget durante los bloques base.
var _redraw_meter = null

var _tree = null
var _enabled := false
# Secuencia intercalada efectiva (base y sondas) y posicion actual.
var _schedule: Array = []
var _schedule_index := 0
# Ventana abierta: la sonda ya esta aplicada y se cuentan descarte/medicion.
var _window_open := false
var _frames_seen := 0
var _frames_recorded := 0
var _block_frames: Array = []
var _block_renders: Array = []
# Bloques cerrados: {label, frame_ms, render_ms, n}. Base de los deltas pareados.
var _blocks: Array = []
# Estado guardado de la sonda activa (para restaurar exacto).
var _active := ""
var _saved: Dictionary = {}
# Toggles de corrida completa: estado guardado aparte para no pisar las ventanas.
var _full_run_saved: Dictionary = {}
var _full_run_applied := false
var _full_run_labels: Array = []
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
	return _env_bool(PROBES_ENV)

func _env_bool(name: String) -> bool:
	return OS.get_environment(name).strip_edges().to_lower() in ["1", "true", "yes", "on"]

func is_enabled() -> bool:
	return _enabled

# Sonda activa en este frame ("" si las sondas no corren, el frame es de descarte/transicion o
# todavia no se midio nada del bloque).
func active_probe() -> String:
	return _active if _window_open and _frames_recorded > 0 else ""

# Avanza una muestra del playback. Devuelve la etiqueta de sonda del frame ("" si no corren o
# el frame es de descarte/transicion) y gestiona los cambios de bloque restaurando/aplicando.
func step(frame_ms: float, render_ms: float) -> String:
	if not _enabled or _closed:
		return ""
	# Tarea GG: las sondas de subarbol se descubren del arbol vivo en el primer step (recien
	# ahi la escena esta armada) y se agregan al final de la secuencia.
	_ensure_sequence()
	if _schedule.empty() or _schedule_index >= _schedule.size():
		_window_open = false
		return ""
	if not _window_open:
		_open_window()
	# Frames de transicion: la sonda ya esta aplicada pero no se mide todavia.
	if _frames_seen < discard_frames:
		_frames_seen += 1
		return ""
	var label := _active
	_record(label, frame_ms, render_ms)
	_block_frames.append(frame_ms)
	_block_renders.append(render_ms)
	_frames_recorded += 1
	# Tarea HH: los bloques base corren con el estado sin tocar: ahi se mide el refresco real
	# de los Viewports de widget antes de que las sondas empiecen a ocultar subarboles.
	if _redraw_meter != null and label == REFERENCE_LABEL:
		_redraw_meter.sample(frame_ms)
	if _frames_recorded >= block_frames:
		_close_window()
	return label

# Cierra las sondas: finaliza el bloque en curso, restaura el estado exacto y los toggles de
# corrida completa, imprime las medianas pareadas y devuelve el resumen. Idempotente.
func finish() -> Dictionary:
	if _enabled and _window_open:
		_close_window()
	restore_all()
	_closed = true
	if not _enabled:
		return {}
	var summary := summary()
	_print_report(summary)
	if _redraw_meter != null:
		_redraw_meter.print_report()
	return summary

# Restaura (si quedo algo aplicado) sin cerrar: para cortes del playback a mitad de un bloque.
# Idempotente.
func restore_all() -> void:
	_restore_current()
	restore_full_run_toggles()

# --- toggles de corrida completa (tarea JJ) ---

# Lee los envs y apaga por TODA la corrida lo pedido. Idempotente. Se llama al arrancar el
# playback; se revierte en restore_full_run_toggles (finish/restore_all).
func apply_full_run_toggles() -> void:
	if _full_run_applied:
		return
	_full_run_applied = true
	_full_run_labels = []
	# Reusa los aplicadores de sonda guardando en el diccionario de corrida completa.
	var prev_saved: Dictionary = _saved
	_saved = _full_run_saved
	if _env_bool(BENCH_NO_UI_ENV):
		_apply_ui()
		_full_run_labels.append(BENCH_NO_UI_ENV)
	if _env_bool(BENCH_NO_3D_ENV):
		_apply_3d()
		_full_run_labels.append(BENCH_NO_3D_ENV)
	if _env_bool(BENCH_NO_ENV_ENV):
		_apply_env()
		_full_run_labels.append(BENCH_NO_ENV_ENV)
	_full_run_saved = _saved
	_saved = prev_saved

# Devuelve todo lo que la corrida completa haya apagado. Idempotente.
func restore_full_run_toggles() -> void:
	if not _full_run_applied:
		return
	_full_run_applied = false
	var prev_saved: Dictionary = _saved
	_saved = _full_run_saved
	_restore_ui()
	_restore_3d()
	_restore_env()
	_saved = prev_saved
	_full_run_saved = {}
	_full_run_labels = []

func full_run_labels() -> Array:
	return _full_run_labels.duplicate()

# Resumen de medianas por sonda con delta pareado contra los bloques base adyacentes. Vacio si
# no hay muestras.
func summary() -> Dictionary:
	if _samples.empty():
		return {}
	var raw_base_frame := _median(_samples.get(REFERENCE_LABEL, {}).get("frame_ms", []))
	var raw_base_render := _median(_samples.get(REFERENCE_LABEL, {}).get("render_ms", []))
	var deltas := _paired_deltas()
	var probes: Dictionary = {}
	for label in _samples:
		var frame_ms := _median(_samples[label]["frame_ms"])
		var render_ms := _median(_samples[label]["render_ms"])
		var fd: Array = deltas.get(label, {}).get("frame", [])
		var rd: Array = deltas.get(label, {}).get("render", [])
		var fd_sorted: Array = fd.duplicate()
		var rd_sorted: Array = rd.duplicate()
		fd_sorted.sort()
		rd_sorted.sort()
		probes[label] = {
			"n": _samples[label]["frame_ms"].size(),
			"blocks": _count_blocks(label),
			"frame_ms_p50": frame_ms,
			"render_ms_p50": render_ms,
			"frame_ms_p50_delta": _median(fd) if not fd.empty() else 0.0,
			"render_ms_p50_delta": _median(rd) if not rd.empty() else 0.0,
			"frame_ms_delta_p25": _quantile(fd_sorted, 0.25),
			"frame_ms_delta_p75": _quantile(fd_sorted, 0.75),
			"render_ms_delta_p25": _quantile(rd_sorted, 0.25),
			"render_ms_delta_p75": _quantile(rd_sorted, 0.75),
		}
	var out := {
		"block_frames": block_frames,
		"discard_frames": discard_frames,
		"base_frame_ms_p50": raw_base_frame,
		"base_render_ms_p50": raw_base_render,
		"probes": probes,
	}
	if not _full_run_labels.empty():
		out["full_run"] = _full_run_labels.duplicate()
	if _redraw_meter != null:
		out["redraw"] = _redraw_meter.report()
	return out

# --- ventana y acumulacion ---

func _open_window() -> void:
	var label := String(_schedule[_schedule_index])
	_apply_probe(label)
	_window_open = true
	_frames_seen = 0
	_frames_recorded = 0
	_block_frames = []
	_block_renders = []

func _close_window() -> void:
	if not _block_frames.empty():
		_blocks.append({
			"label": _active,
			"frame_ms": _median(_block_frames),
			"render_ms": _median(_block_renders),
			"n": _block_frames.size(),
		})
	_restore_current()
	_window_open = false
	_frames_seen = 0
	_frames_recorded = 0
	_block_frames = []
	_block_renders = []
	_schedule_index += 1
	if _schedule_index >= _schedule.size() and loop_schedule:
		_schedule_index = 0

func _apply_probe(probe: String) -> void:
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
			if probe.begins_with("subtree:"):
				_apply_subtree(probe)

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
			if _active.begins_with("subtree:"):
				_restore_subtree()
	_saved = {}
	_active = ""

func _record(label: String, frame_ms: float, render_ms: float) -> void:
	if not _samples.has(label):
		_samples[label] = {"frame_ms": [], "render_ms": []}
	_samples[label]["frame_ms"].push_back(frame_ms)
	_samples[label]["render_ms"].push_back(render_ms)

func _count_blocks(label: String) -> int:
	var count := 0
	for block in _blocks:
		if String(block["label"]) == label:
			count += 1
	return count

# Delta pareado por bloque de sonda: mediana del bloque menos el promedio de las medianas de
# los bloques base inmediatamente anterior y siguiente (los unicos adyacentes, por construccion
# de la secuencia intercalada). Devuelve { label: {"frame": [...], "render": [...]} }.
func _paired_deltas() -> Dictionary:
	var deltas: Dictionary = {}
	for i in range(_blocks.size()):
		var block: Dictionary = _blocks[i]
		var label := String(block["label"])
		if label == REFERENCE_LABEL:
			continue
		var refs: Array = []
		if i - 1 >= 0 and String(_blocks[i - 1]["label"]) == REFERENCE_LABEL:
			refs.append(_blocks[i - 1])
		if i + 1 < _blocks.size() and String(_blocks[i + 1]["label"]) == REFERENCE_LABEL:
			refs.append(_blocks[i + 1])
		if refs.empty():
			continue
		var ref_frame := 0.0
		var ref_render := 0.0
		for ref in refs:
			ref_frame += float(ref["frame_ms"])
			ref_render += float(ref["render_ms"])
		ref_frame /= float(refs.size())
		ref_render /= float(refs.size())
		if not deltas.has(label):
			deltas[label] = {"frame": [], "render": []}
		deltas[label]["frame"].append(float(block["frame_ms"]) - ref_frame)
		deltas[label]["render"].append(float(block["render_ms"]) - ref_render)
	return deltas

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

# --- tarea GG: sondas por subarbol de HUD ---

# Descubre una vez los subarboles del HUD, arma la secuencia intercalada y el medidor de
# refresco. Idempotente.
func _ensure_sequence() -> void:
	if _subtrees_built:
		return
	_subtrees_built = true
	if include_subtrees:
		discover_subtrees()
	_build_schedule()
	# Tarea HH: el medidor de refresco corre siempre que las sondas esten activas (no depende de
	# include_subtrees): mide los bloques base para saber si el ahorro a 10 Hz se aplica.
	_redraw_meter = HudRedrawMeterScript.new()
	_redraw_meter.capture(_tree)

# Arma la secuencia intercalada base/sonda: una base antes y otra despues de cada sonda, para
# que cada bloque de sonda tenga bases ADYACENTES contra las que compararse. La referencia se
# ignora del listado de sondas y se inserta sola.
func _build_schedule() -> void:
	_schedule = []
	for entry in sequence:
		var label := String(entry)
		if label == REFERENCE_LABEL:
			continue
		if not _schedule.empty():
			_schedule.append(REFERENCE_LABEL)
		_schedule.append(label)
	if _schedule.empty():
		_schedule = [REFERENCE_LABEL]
		return
	if String(_schedule[0]) != REFERENCE_LABEL:
		_schedule.push_front(REFERENCE_LABEL)
	if String(_schedule[_schedule.size() - 1]) != REFERENCE_LABEL:
		_schedule.append(REFERENCE_LABEL)

# Registra una sonda de subarbol manualmente (tests u overrides). El nodo tiene que ser un
# CanvasItem (CanvasLayer/Control) o el marcador VP_ALWAYS_LABEL para los Viewports ALWAYS.
func add_subtree_probe(label: String, node) -> void:
	if label == VP_ALWAYS_LABEL:
		_subtree_probes[label] = null
	else:
		_subtree_probes[label] = node
	if not sequence.has(label):
		sequence.append(label)

# Recorre el arbol buscando los subarboles de HUD que la tarea GG quiere desglosar. Cada uno
# se agrega con una etiqueta "subtree:<rol>". Devuelve las etiquetas nuevas.
func discover_subtrees() -> Array:
	var labels: Array = []
	if _tree == null or _tree.root == null:
		return labels
	var root: Node = _tree.root
	# Widgets de SuitOS: el root de la capa propia del host (widgets + shouldiers + ruler).
	for host in _tree.get_nodes_in_group("hud_widget_host"):
		if is_instance_valid(host) and host.has_method("get_widget_root"):
			var widget_root = host.call("get_widget_root")
			_add_subtree("subtree:widgets", widget_root, labels)
	# MobileUI: joystick/botones tactiles. Es una CanvasLayer hija de la raiz.
	_add_subtree("subtree:mobileui", root.get_node_or_null("MobileUIManager"), labels)
	# Overlays (InfoOverlay y viñetas) viven en OverlayUIManager (CanvasLayer 115).
	_add_subtree("subtree:overlays", root.get_node_or_null("OverlayUIManager"), labels)
	# Cursor virtual: la capa que lo contiene (grupo virtual_mouse).
	for cursor in _tree.get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(cursor):
			_add_subtree("subtree:virtualmouse", cursor.get_parent(), labels)
			break
	# Consola de debug: su Viewport comparte el World (Node sin `visible`, se apaga por modo).
	var console = root.get_node_or_null("DebugConsoleManager")
	var console_viewport = console.get("_viewport") if console != null else null
	_add_subtree("subtree:debugconsole", console_viewport, labels)
	# Viewport(s) de widget con UPDATE_ALWAYS: caso especial, se apagan en _apply_subtree.
	_add_subtree(VP_ALWAYS_LABEL, null, labels)
	return labels

func _add_subtree(label: String, node, labels: Array) -> void:
	if _subtree_probes.has(label):
		return
	if label != VP_ALWAYS_LABEL and not (_is_hideable(node) or (is_instance_valid(node) and node is Viewport)):
		return
	_subtree_probes[label] = node
	sequence.append(label)
	labels.append(label)

# CanvasLayer (MobileUIManager, VirtualMouseLayer) no es CanvasItem en Godot 3, pero tiene
# `visible`: se acepta igual que Control/Node2D. Viewport no tiene `visible` y se apaga por modo.
func _is_hideable(node) -> bool:
	return is_instance_valid(node) and (node is CanvasLayer or node is CanvasItem)

# "subtree:vpalways" lista los Viewport del arbol en UPDATE_ALWAYS y los deja DISABLED; el
# resto oculta su CanvasLayer/CanvasItem (o apaga su Viewport, que no tiene `visible`).
func _apply_subtree(label: String) -> void:
	if label == VP_ALWAYS_LABEL:
		_disable_always_viewports()
		return
	var node = _subtree_probes.get(label, null)
	if not is_instance_valid(node):
		return
	if node is Viewport:
		_saved["vps"] = [[node, node.render_target_update_mode]]
		node.render_target_update_mode = Viewport.UPDATE_DISABLED
		return
	if _is_hideable(node):
		_saved["nodes"] = [[node, node.visible]]
		node.visible = false

func _disable_always_viewports() -> void:
	var touched: Array = []
	if _tree == null or _tree.root == null:
		return
	var stack: Array = [_tree.root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if node is Viewport and node != _tree.root \
				and node.render_target_update_mode == Viewport.UPDATE_ALWAYS:
			touched.append([node, node.render_target_update_mode])
			node.render_target_update_mode = Viewport.UPDATE_DISABLED
	_saved["vps"] = touched

func _restore_subtree() -> void:
	for entry in _saved.get("nodes", []):
		if is_instance_valid(entry[0]):
			entry[0].visible = bool(entry[1])
	for entry in _saved.get("vps", []):
		if is_instance_valid(entry[0]):
			entry[0].render_target_update_mode = int(entry[1])

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

# Cuantil por interpolacion lineal sobre un array YA ordenado.
func _quantile(sorted_values: Array, q: float) -> float:
	var n: int = sorted_values.size()
	if n <= 0:
		return -1.0
	if n == 1:
		return float(sorted_values[0])
	var pos := q * float(n - 1)
	var lo := int(floor(pos))
	var hi := int(ceil(pos))
	if lo == hi:
		return float(sorted_values[lo])
	var frac := pos - float(lo)
	return float(sorted_values[lo]) * (1.0 - frac) + float(sorted_values[hi]) * frac

func _print_report(summary: Dictionary) -> void:
	if summary.empty():
		return
	var probes: Dictionary = summary["probes"]
	var base: Dictionary = probes.get(REFERENCE_LABEL, {})
	print("[PlaybackProbes] sondas A/B intercaladas (", block_frames, " frames/bloque, ",
		discard_frames, " descarte, base frame_ms_p50=", "%.2f" % float(base.get("frame_ms_p50", -1.0)),
		" render_ms_p50=", "%.2f" % float(base.get("render_ms_p50", -1.0)), ")")
	if not _full_run_labels.empty():
		print("[PlaybackProbes] toggles de corrida completa activos: ", _full_run_labels)
	for label in _report_order(probes):
		var p: Dictionary = probes[label]
		print("[PlaybackProbes] ", label,
			" n=", p["n"],
			" bloques=", p["blocks"],
			" frame_ms_p50=", "%.2f" % p["frame_ms_p50"],
			" (d= ", "%.2f" % p["frame_ms_p50_delta"],
			" [", "%.2f" % p["frame_ms_delta_p25"], ",", "%.2f" % p["frame_ms_delta_p75"], "])",
			" render_ms_p50=", "%.2f" % p["render_ms_p50"],
			" (d= ", "%.2f" % p["render_ms_p50_delta"],
			" [", "%.2f" % p["render_ms_delta_p25"], ",", "%.2f" % p["render_ms_delta_p75"], "])")
	# Tarea GG: ranking por lo que cuesta CADA subarbol (delta pareado al ocultarlo). Mas
	# negativo = mas caro. Es la lista que decide donde atacar primero.
	var ranked: Array = []
	for label in probes:
		ranked.append([label, float(probes[label]["frame_ms_p50_delta"])])
	ranked.sort_custom(self, "_rank_by_frame_delta")
	print("[PlaybackProbes] ranking por frame_ms_p50_delta pareado (mas negativo = mas caro ocultarlo):")
	for entry in ranked:
		print("[PlaybackProbes]   ", entry[0], " d=", "%.2f" % float(entry[1]))

func _report_order(probes: Dictionary) -> Array:
	var order: Array = []
	if probes.has(REFERENCE_LABEL):
		order.append(REFERENCE_LABEL)
	for label in sequence:
		var l := String(label)
		if l == REFERENCE_LABEL or not probes.has(l) or order.has(l):
			continue
		order.append(l)
	return order

func _rank_by_frame_delta(a, b) -> bool:
	return float(a[1]) < float(b[1])
