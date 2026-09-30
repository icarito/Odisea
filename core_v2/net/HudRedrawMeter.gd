extends Reference

# HudRedrawMeter.gd - FD-316 (tarea HH): confirma si el espaciado a 10 Hz de los Viewports de
# HUD realmente se aplica y deja constancia de por que los widgets siguen costando aunque su
# animacion se espacie.
#
# En modo ODISEA_SLAVE_PROFILE/PROBES se muestrea por frame el render_target_update_mode de cada
# Viewport bajo los subarboles de widgets y se cuenta:
#   - always: frames que el Viewport renderiza por estar en UPDATE_ALWAYS (no se esta ahorrando);
#   - pulses: transiciones a UPDATE_ONCE (el driver LowHzViewportRedraw despierta uno cada 100 ms
#     en tier LOW). Una tasa de ~10/s confirma que el ahorro se aplica; ~60/s delata otro sistema
#     poniendolo en UPDATE_ALWAYS.
#
# Los CanvasItem (Control) de widget NO tienen render_target_update_mode: el canvas 2D los
# recompone cada frame, asi que un refresco a 10 Hz no les baja el costo. Se cuenta cuantos hay
# visibles por frame para separar "el ahorro no se aplica" de "el costo es composicion del canvas
# y solo lo baja ocultar el subarbol".

const DRIVER_NAME := "LowHzRedraw"

var tree = null
var _viewports: Array = []
var _canvas_items: Array = []
var _low_hz_drivers := 0
var _elapsed_ms := 0.0
var _samples := 0
var _visible_canvas_items_sum := 0
var _last_report: Dictionary = {}

# Encuentra los subarboles de widgets (hosts SuitOS) y sus Viewports/CanvasItems. Idempotente:
# se puede volver a llamar cuando abre una pantalla nueva.
func capture(p_tree) -> void:
	tree = p_tree
	_viewports.clear()
	_canvas_items.clear()
	_low_hz_drivers = 0
	_elapsed_ms = 0.0
	_samples = 0
	_visible_canvas_items_sum = 0
	if tree == null or tree.root == null:
		return
	for host in tree.get_nodes_in_group("hud_widget_host"):
		if is_instance_valid(host):
			# Se camina el host entero (no solo su widget_root): los Viewport de una vista de
			# pantalla (HudViewMount) cuelgan del host, no del root de widgets.
			_capture_subtree(host)

func _capture_subtree(root: Node) -> void:
	var stack: Array = [root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if String(node.name) == DRIVER_NAME:
			_low_hz_drivers += 1
		if node is Viewport:
			_viewports.append({
				"node": node,
				"path": str(node.get_path()),
				"always": 0,
				"pulses": 0,
				"disabled": 0,
				"last_mode": -1,
			})
		elif node is CanvasItem:
			_canvas_items.append(node)

# delta_ms es el frame_ms del playback: se acumula para pasar los conteos a por segundo.
func sample(delta_ms: float) -> void:
	if tree == null:
		return
	_elapsed_ms += delta_ms
	_samples += 1
	var visible := 0
	for item in _canvas_items:
		if is_instance_valid(item) and item.visible:
			visible += 1
	_visible_canvas_items_sum += visible
	for entry in _viewports:
		var vp = entry["node"]
		if not is_instance_valid(vp):
			continue
		var mode: int = vp.render_target_update_mode
		if mode == Viewport.UPDATE_ALWAYS:
			entry["always"] = int(entry["always"]) + 1
		elif mode == Viewport.UPDATE_ONCE:
			# Un pulso cuenta una sola vez aunque el motor tarde en consumir el flag.
			if int(entry["last_mode"]) != Viewport.UPDATE_ONCE:
				entry["pulses"] = int(entry["pulses"]) + 1
		else:
			entry["disabled"] = int(entry["disabled"]) + 1
		entry["last_mode"] = mode

func report() -> Dictionary:
	var seconds: float = max(_elapsed_ms / 1000.0, 0.0001)
	var viewports: Dictionary = {}
	for entry in _viewports:
		viewports[entry["path"]] = {
			"always_per_s": float(entry["always"]) / seconds,
			"pulses_per_s": float(entry["pulses"]) / seconds,
			"disabled_frames": int(entry["disabled"]),
		}
	var visible_avg: float = float(_visible_canvas_items_sum) / float(max(_samples, 1))
	_last_report = {
		"window_s": seconds,
		"low_hz_drivers": _low_hz_drivers,
		"widget_canvas_items": _canvas_items.size(),
		"widget_visible_items_avg": visible_avg,
		"viewports": viewports,
	}
	return _last_report

func last_report() -> Dictionary:
	return _last_report

# Volcado legible para el log del device (el resumen crudo viaja en la traza de perf).
func print_report() -> void:
	var r: Dictionary = report()
	print("[HudRedrawMeter] ventana=", "%.1f" % float(r["window_s"]), "s",
		" drivers_10Hz=", r["low_hz_drivers"],
		" canvas_items=", r["widget_canvas_items"],
		" visibles_prom=", "%.1f" % float(r["widget_visible_items_avg"]))
	var viewports: Dictionary = r["viewports"]
	if viewports.empty():
		print("[HudRedrawMeter]   sin Viewports de widget (solo CanvasItem: el canvas 2D los recompone cada frame, el refresco a 10 Hz no los toca)")
		return
	for path in viewports:
		var v: Dictionary = viewports[path]
		print("[HudRedrawMeter]   ", path,
			" always=", "%.1f" % float(v["always_per_s"]), "/s",
			" pulses=", "%.1f" % float(v["pulses_per_s"]), "/s")
