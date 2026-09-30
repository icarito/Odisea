extends Node

# LowViewportOptimizer.gd - FD-316 (tareas KK/MM): recorta el costo de los Viewports que un
# dueno dejo en refresco por frame (render_target_update_mode = UPDATE_ALWAYS o
# UPDATE_WHEN_VISIBLE) en el render-esclavo del handheld.
#
# El playback midio ~5 ms solo en Viewports con UPDATE_ALWAYS (sonda subtree:vpalways): cada
# uno re-renderiza su contenido (2D o el World 3D compartido) cada frame aunque nadie lo vea
# o aunque su contenido no cambie. La tarea MM sumo el caso UPDATE_WHEN_VISIBLE, que la
# pantalla de un terminal visible fuera de foco re-ponia cada tick y que este optimizador
# antes ignoraba (solo reconocia ALWAYS). En tier LOW se aplica una politica conservadora:
#   - no visible: ningun nodo visible muestra su textura -> UPDATE_DISABLED;
#   - visible: refresco a ~10 Hz (UPDATE_ONCE periodico via LowHzViewportRedraw).
# El piso de 10 Hz es obligatorio: nunca se deja una pantalla VISIBLE congelada, aunque su
# contenido sea estatico. Fuera de LOW (o con ODISEA_LOW_UI_OPT=0) no se toca nada y se
# restaura el modo exacto de lo que se haya tocado.
#
# "Visible" = su ViewportTexture la referencia un CanvasItem/Spatial que esta visible en el
# arbol (propiedad `texture`, albedo de material o un ViewportContainer), incluidos los
# displays holograficos que pintan la textura en una malla. Un Viewport que no la muestra
# nadie es, por definicion, offscreen: apagarlo no congela nada visible.
#
# Solo se ocupa del render-esclavo: lo instala RemoteSimClient mientras el offload o el
# playback estan activos (en un host que simula, el Viewport lo maneja el propio juego).

const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")
const LowHzViewportRedrawScript = preload("res://core_v2/ui/hud/LowHzViewportRedraw.gd")

# Driver de 10 Hz con el que se refresca un Viewport visible.
const DRIVER_NAME := "LowHzRedraw"
# Parametros de ShaderMaterial que pueden llevar un ViewportTexture (displays holograficos).
const SHADER_TEXTURE_PARAMS := [
	"texture_albedo", "albedo", "texture", "viewport_texture", "screen_texture", "albedo_texture"
]

# Intervalo entre barridos del arbol. Un widget que aparece o desaparece no necesita
# reaccion inmediata y recorrer el arbol cuesta: 2 Hz alcanza para el piso de 10 Hz.
const SCAN_INTERVAL := 0.5

# Arbol del que se cuelga (null = get_tree()). Se expone para los tests sin SceneTree.
var tree = null
# path -> { vp, original_mode, driver, shown, size, update_mode } de lo que este nodo toco.
var _managed: Dictionary = {}
# instance_id -> true: Viewports que demostraron querer UPDATE_ALWAYS por un dueno externo
# (una terminal con foco exige ALWAYS para el cursor suave, HoloTerminalV2:614). A esos no
# se los vuelve a tocar; el ahorro cede ante el contrato de inmersión.
var _exempt: Dictionary = {}
var _elapsed := 0.0
# El censo se imprime UNA vez, en el primer barrido con algo para reportar.
var _reported := false


func _ready() -> void:
	# Node de servicio, sin input ni fisica: solo el barrido periodico.
	set_process(true)


func _process(delta: float) -> void:
	if not LowUiOptScript.enabled():
		# El A/B apago el ahorro (o se salio del tier): devolver todo como estaba.
		if not _managed.empty():
			restore_all()
		return
	_elapsed += delta
	if _elapsed < SCAN_INTERVAL:
		return
	_elapsed = 0.0
	scan_now()


# Devuelve el arbol a recorrer: el inyectado (tests) o el SceneTree real.
func _root():
	if tree != null and is_instance_valid(tree) and tree.root != null:
		return tree.root
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root
	return null


# Aplica la politica al arbol completo. Publica para los tests (no depende del _process).
# No-op si el ahorro esta apagado. Devuelve true si barrio.
func scan_now() -> bool:
	if not LowUiOptScript.enabled():
		return false
	var root = _root()
	if root == null:
		return false
	var displayed := _visible_texture_ids(root)
	var seen: Dictionary = {}
	var stack: Array = [root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if not (node is Viewport) or node == root:
			continue
		var vp := node as Viewport
		# Un Viewport exento (un dueno externo lo quiere en ALWAYS) no se toca nunca mas.
		if _exempt.has(vp.get_instance_id()):
			continue
		var path := String(vp.get_path())
		seen[path] = true
		var shown := _is_shown(vp, displayed)
		var first_sight := false
		if not _managed.has(path):
			# Solo se toca lo que un dueno dejo en refresco por frame: UPDATE_ALWAYS o
			# UPDATE_WHEN_VISIBLE (una pantalla de terminal visible fuera de foco se quedaba
			# asi y re-renderizaba cada frame, que es justo lo que esta tarea mide). Un
			# Viewport ya espaciado (ONCE/DISABLED) es de otro sistema y se respeta.
			if vp.render_target_update_mode != Viewport.UPDATE_ALWAYS \
					and vp.render_target_update_mode != Viewport.UPDATE_WHEN_VISIBLE:
				continue
			_managed[path] = {
				"vp": vp,
				"original_mode": int(vp.render_target_update_mode),
				"driver": null,
				"shown": shown,
			}
			first_sight = true
		var entry: Dictionary = _managed[path]
		if not is_instance_valid(entry["vp"]):
			_managed.erase(path)
			continue
		# Si ya lo gestionamos (nunca le ponemos ALWAYS nosotros: nuestro reposo es DISABLED
		# y el driver emite ONCE) y ahora esta en ALWAYS, lo pidio un dueno externo con un
		# contrato de tasa completa (foco de terminal, HUD prestando el Viewport): ceder.
		if not first_sight and vp.render_target_update_mode == Viewport.UPDATE_ALWAYS:
			_yield_external(vp, entry)
			continue
		_apply(vp, entry, shown)
		entry["shown"] = shown
	# Soltar los Viewports que ya no estan en el arbol (cambio de escena/streaming).
	for path in _managed.keys():
		if not seen.has(path) or not is_instance_valid(_managed[path]["vp"]):
			_restore_entry(path)
	_print_census_once()
	return true


# Un Viewport esta "visible" si su textura la muestra algun nodo visible del arbol.
func _is_shown(vp: Viewport, displayed: Dictionary) -> bool:
	var tex = vp.get_texture()
	return tex != null and displayed.has(tex.get_instance_id())


# Aplica el modo al Viewport segun visibilidad. Visible = driver de 10 Hz; no visible =
# DISABLED. Idempotente: no re-crea el driver ni reescribe el modo si ya esta.
func _apply(vp: Viewport, entry: Dictionary, shown: bool) -> void:
	var driver = entry.get("driver", null)
	if shown:
		if driver == null or not is_instance_valid(driver):
			vp.render_target_update_mode = Viewport.UPDATE_DISABLED
			driver = LowHzViewportRedrawScript.new()
			driver.name = DRIVER_NAME
			driver.viewport = vp
			vp.add_child(driver)
			entry["driver"] = driver
		elif vp.render_target_update_mode == Viewport.UPDATE_DISABLED \
				or vp.render_target_update_mode == Viewport.UPDATE_ONCE:
			# DISABLED es el reposo del driver; ONCE es el pulso ya pedido. Cualquier otro
			# modo (WHEN_VISIBLE/ALWAYS) lo re-puso un dueno y volveria al refresco por
			# frame: el driver manda la cadencia de 10 Hz mientras el Viewport este visible.
			pass
		else:
			vp.render_target_update_mode = Viewport.UPDATE_DISABLED
	else:
		if driver != null and is_instance_valid(driver):
			_drop_driver(driver)
			entry["driver"] = null
		if vp.render_target_update_mode != Viewport.UPDATE_DISABLED:
			vp.render_target_update_mode = Viewport.UPDATE_DISABLED


# Saca el driver del arbol YA (queue_free solo lo libera al final del frame) para que
# get_node_or_null("LowHzRedraw") deje de resolver en cuanto se restaura.
func _drop_driver(driver) -> void:
	if driver == null or not is_instance_valid(driver):
		return
	var parent = driver.get_parent()
	if parent != null:
		parent.remove_child(driver)
	driver.queue_free()


# Cede un Viewport que un dueno externo volvio a poner en ALWAYS: le saca nuestro driver y
# lo marca exento para no volver a pisarlo en esta sesion. No toca el modo (ya es ALWAYS).
func _yield_external(vp: Viewport, entry: Dictionary) -> void:
	var driver = entry.get("driver", null)
	if driver != null and is_instance_valid(driver):
		_drop_driver(driver)
	_exempt[vp.get_instance_id()] = true
	_managed.erase(String(vp.get_path()))


# Devuelve TODO como estaba (modo original + sin drivers). Idempotente.
func restore_all() -> void:
	for path in _managed.keys():
		_restore_entry(path)
	_managed.clear()
	_exempt.clear()
	_elapsed = 0.0
	_reported = false


func _restore_entry(path: String) -> void:
	var entry: Dictionary = _managed.get(path, {})
	if entry.empty():
		return
	var driver = entry.get("driver", null)
	if driver != null and is_instance_valid(driver):
		_drop_driver(driver)
	var vp = entry.get("vp", null)
	if vp != null and is_instance_valid(vp):
		vp.render_target_update_mode = int(entry.get("original_mode", Viewport.UPDATE_ALWAYS))
	_managed.erase(path)


# Censo de los Viewport tocados: ruta, tamano, si su textura se muestra y el modo aplicado.
# Es el "listar cuales son" del que salen las decisiones de tier LOW.
func report() -> Array:
	var out: Array = []
	for path in _managed:
		var entry: Dictionary = _managed[path]
		var vp = entry.get("vp", null)
		if vp == null or not is_instance_valid(vp):
			continue
		out.append(
			{
				"path": String(path),
				"size": [vp.size.x, vp.size.y],
				# Que dibuja: 3D compartido (re-renderiza el World) o solo 2D.
				"has_3d": _viewport_has_3d(vp),
				"shown": bool(entry.get("shown", false)),
				"update_mode": int(vp.render_target_update_mode),
				"original_mode": int(entry.get("original_mode", Viewport.UPDATE_ALWAYS)),
				"driver_10hz": entry.get("driver", null) != null,
			}
		)
	out.sort_custom(self, "_sort_by_path")
	return out


# 3D habilitado = no desactiva 3D y su usage es de escena 3D. Mismo criterio que el censo de
# SessionManager: un Viewport asi comparte el World del root y lo re-renderiza entero.
func _viewport_has_3d(vp: Viewport) -> bool:
	if vp.disable_3d:
		return false
	return vp.usage == Viewport.USAGE_3D or vp.usage == Viewport.USAGE_3D_NO_EFFECTS


func _sort_by_path(a, b) -> bool:
	return String(a["path"]) < String(b["path"])


func _print_census_once() -> void:
	if _reported or _managed.empty():
		return
	_reported = true
	print(
		"[LowViewportOptimizer] Viewports por frame (ALWAYS/WHEN_VISIBLE) en tier LOW (",
		_managed.size(),
		"), politica: visible=10 Hz / no visible=DISABLED"
	)
	for info in report():
		print(
			"[LowViewportOptimizer]   ",
			info["path"],
			" size=",
			info["size"],
			" 3d=",
			info["has_3d"],
			" textura_visible=",
			info["shown"],
			" original=",
			info["original_mode"],
			" -> ",
			"10 Hz" if info["driver_10hz"] else "DISABLED"
		)


# --- recoleccion de texturas que se muestran ---


# IDs de instancia de las ViewportTexture referenciadas por algun nodo VISIBLE del arbol.
# Cubre la UI (propiedad `texture`, ViewportContainer) y los displays 3D (albedo del
# material, parametro de ShaderMaterial).
func _visible_texture_ids(root: Node) -> Dictionary:
	var ids: Dictionary = {}
	var stack: Array = [root]
	while not stack.empty():
		var node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			stack.append(child)
		if not _is_drawn(node):
			continue
		if node is ViewportContainer:
			for child in node.get_children():
				if child is Viewport:
					var ctex = (child as Viewport).get_texture()
					if ctex != null:
						ids[ctex.get_instance_id()] = true
		var tex = node.get("texture")
		if tex is Texture:
			ids[tex.get_instance_id()] = true
		# `material_override` (MeshInstance) y `material` (CSGShape/CanvasItem: el vidrio de
		# una terminal CSGBox o el shader de un Control).
		_collect_material_textures(node.get("material_override"), ids)
		_collect_material_textures(node.get("material"), ids)
		if node is MeshInstance:
			var mi := node as MeshInstance
			for i in range(mi.get_surface_material_count()):
				_collect_material_textures(mi.get_surface_material(i), ids)
	return ids


# Un nodo "dibuja" si es CanvasItem/Spatial y esta visible en el arbol (ancestros incluidos).
func _is_drawn(node) -> bool:
	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	if node is Spatial:
		return (node as Spatial).is_visible_in_tree()
	return false


func _collect_material_textures(mat, ids: Dictionary) -> void:
	if mat == null:
		return
	if mat is SpatialMaterial:
		var at = (mat as SpatialMaterial).albedo_texture
		if at is Texture:
			ids[at.get_instance_id()] = true
	elif mat is ShaderMaterial:
		for param in SHADER_TEXTURE_PARAMS:
			var stex = (mat as ShaderMaterial).get_shader_param(param)
			if stex is Texture:
				ids[stex.get_instance_id()] = true
