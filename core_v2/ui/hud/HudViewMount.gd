extends Reference

# HudViewMount.gd - Vista de la pantalla elegida en el modo HUD (FD-296 F3, spec 4.3b).
# Con view_scene(): presentador 3D config-only (HudViewPresenter.tscn = HelmetHUDV2 + config)
# que nace en el terminal de origen y TerminalHUDBridge engancha a la camara con la transicion
# del casco; se lee como holograma por hud_cfg_background_alpha/emission. Si la pantalla presta
# su Viewport, el presentador usa esa misma textura. Sin view_scene(): widget ampliado en 2D.
# view_2d (el control remoto, que no tiene mundo ni camara): la vista va en un Viewport 2D a su
# resolucion de diseño y lo que se escala es esa textura, como la arma el presentador.

const PresenterScene = preload("res://core_v2/ui/hud/HudViewPresenter.tscn")
const HoloScreen2DShader = preload("res://core_v2/visual/HoloScreen2D.shader")
# Widget ampliado de un hudable sin pantalla completa. Era 3.0: se veia demasiado grande.
const WIDGET_ZOOM := 1.8
# Sin posicion de origen, el presentador arranca a esta distancia frente a la camara.
const FRONT_DISTANCE := 1.5
# Tiempo para que el presentador se encoja (anim_duration del casco) antes de liberarlo.
const FREE_DELAY := 0.6
# B3a: los paneles de widget y el vidrio del presentador van semi-transparentes (alfa ~0.7).
# En tier LOW (Mali) se quedan como vengan: paneles translucidos sobre el mundo son overdraw
# puro en un GPU tile-based, justo lo que el gate evita.
const WIDGET_PANEL_ALPHA := 0.7

var _presenter: Spatial = null
var _widget: Control = null
var _presenter_snapped: bool = false
var _shared_screen: Object = null
# La pantalla del widget ampliado: su state_changed lo refresca, como a los widgets de los slots (sin
# esto, oprimir ENCENDER en el ampliado prendia la linterna pero su rotulo seguia en APAGADA).
var _widget_screen: Object = null
var view_2d: bool = false
var _view_frame: Control = null
var _view_node: Control = null

# B3a helper unico: alfa de panel/vidrio segun tier. LOW = 1.0 (opaco), resto = 0.7.
static func widget_alpha() -> float:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var gate = (loop as SceneTree).root.get_node_or_null("GLES3VendorGate")
		if gate != null and gate.has_method("is_low_tier") and gate.is_low_tier():
			return 1.0
	return WIDGET_PANEL_ALPHA

# Baja el alfa del StyleBoxFlat "panel" de un Control y de sus hijos. Duplica el stylebox
# antes de tocarlo (el del tema es compartido) y usa min(): nunca sube la opacidad, asi un
# panel del tema (0.62) no queda mas tapado que antes. En tier LOW no hace nada.
static func apply_widget_panel_alpha(node: Node, alpha: float = -1.0) -> void:
	if not is_instance_valid(node):
		return
	var a: float = widget_alpha() if alpha < 0.0 else alpha
	if a >= 1.0:
		return
	if node is Control:
		var ctrl := node as Control
		var box: StyleBox = ctrl.get_stylebox("panel")
		if box is StyleBoxFlat:
			var flat: StyleBoxFlat = (box as StyleBoxFlat).duplicate() as StyleBoxFlat
			var bg: Color = flat.bg_color
			bg.a = min(bg.a, a)
			flat.bg_color = bg
			ctrl.add_stylebox_override("panel", flat)
	for child in node.get_children():
		apply_widget_panel_alpha(child, a)

func is_showing() -> bool:
	return is_instance_valid(_presenter) or is_instance_valid(_widget) or is_instance_valid(_view_frame)

# Donde se dibuja la vista 2D (view_2d), en pantalla; vacio si no hay.
func get_view_rect() -> Rect2:
	if not is_instance_valid(_view_frame):
		return Rect2()
	var container: Control = _view_frame.get_node("ViewViewport")
	var xf: Transform2D = container.get_global_transform_with_canvas()
	return Rect2(xf.origin, container.rect_size * xf.get_scale())

func get_presenter() -> Spatial:
	return _presenter if is_instance_valid(_presenter) else null

func get_widget() -> Control:
	return _widget if is_instance_valid(_widget) else null

func reveal_presenter() -> void:
	if not is_instance_valid(_presenter):
		return
	var mesh = _presenter._get_hud_attach_target() if _presenter.has_method("_get_hud_attach_target") else _presenter.get_node_or_null("ScreenContainer/ScreenMesh")
	if is_instance_valid(mesh):
		mesh.visible = true
	if not _presenter_snapped:
		_presenter.set_physics_process(true)

func show(screen: Object, snapshot: Dictionary, host: Control, snap_to_camera: bool = false) -> void:
	close()
	var scene: PackedScene = screen.view_scene() if screen.has_method("view_scene") else null
	var opened: bool = false
	if scene != null:
		opened = _open_view_2d(scene, screen, snapshot, host) if view_2d \
			else _open_presenter(scene, screen, snapshot, host, snap_to_camera)
	if not opened:
		_open_widget(screen, snapshot, host)

func close() -> void:
	if is_instance_valid(_shared_screen) and _shared_screen.has_method("release_viewport"):
		_shared_screen.release_viewport()
	_shared_screen = null
	if is_instance_valid(_widget_screen) and _widget_screen.is_connected("state_changed", self, "_on_widget_screen_changed"):
		_widget_screen.disconnect("state_changed", self, "_on_widget_screen_changed")
	_widget_screen = null
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	if is_instance_valid(_view_frame):
		_view_frame.queue_free()
	_view_frame = null
	_view_node = null
	if is_instance_valid(_presenter):
		if _presenter_snapped:
			_presenter.set_active(false) # devuelve el ScreenMesh reparentado antes de liberar el presentador
			_presenter.queue_free()
		else:
			_presenter.set_active(false)
			# Al cerrar el juego el presenter ya puede estar fuera del arbol: get_tree() es null
			# y create_timer() reventaba. Sin arbol no hay transicion que esperar, se libera ya.
			if _presenter.is_inside_tree():
				_presenter.get_tree().create_timer(FREE_DELAY, true).connect("timeout", _presenter, "queue_free")
			else:
				_presenter.queue_free()
	_presenter = null
	_presenter_snapped = false

func _open_presenter(scene: PackedScene, screen: Object, snapshot: Dictionary, host: Control, snap_to_camera: bool) -> bool:
	var world: Node = host.get_tree().current_scene
	if world == null:
		return false
	var presenter: Spatial = PresenterScene.instance()
	var design: Vector2 = screen.view_size() if screen.has_method("view_size") else Vector2.ZERO
	var share_viewport: bool = snap_to_camera \
		or (screen.has_method("view_requires_input") and screen.view_requires_input())
	var shared_viewport: Viewport = screen.borrow_viewport() if share_viewport and screen.has_method("borrow_viewport") else null
	if design.x > 0.0 and design.y > 0.0:
		presenter.screen_resolution = design # antes del _ready: de ahi sale el tamaño del Viewport
	# El alfa del vidrio pedido a mano por la pantalla, si lo pide: es el unico piso de
	# opacidad que tiene HoloScreen (ALPHA = max(coverage, albedo.a)). Sin el, una pantalla
	# enfocada contra una pared clara queda ilegible, porque la tinta compite con el mundo
	# que se ve a traves. El default del modo pegado a camara (0.0) se conserva para las
	# pantallas que no lo piden.
	var explicit_background_alpha = null
	if screen.has_method("view_hud_config"):
		var config: Dictionary = screen.view_hud_config()
		presenter.hud_cfg_screen_depth = float(config.get("depth", presenter.hud_cfg_screen_depth))
		presenter.hud_cfg_screen_scale = float(config.get("scale", presenter.hud_cfg_screen_scale))
		presenter.hud_cfg_background_emission = float(config.get("emission", presenter.hud_cfg_background_emission))
		if config.has("tint") and config["tint"] is Color:
			presenter.hud_cfg_background_tint = config["tint"]
		presenter.hud_cfg_background_contrast = float(config.get("contrast", presenter.hud_cfg_background_contrast))
		if config.has("background_alpha"):
			explicit_background_alpha = float(config["background_alpha"])
			presenter.hud_cfg_background_alpha = explicit_background_alpha
		else:
			presenter.hud_cfg_background_alpha = float(config.get("background_alpha", presenter.hud_cfg_background_alpha))
	if snap_to_camera:
		presenter.hud_cfg_attach_transition_time = 0.0
		presenter.hud_cfg_screen_depth = 1.0
		presenter.hud_cfg_background_alpha = 0.0 if explicit_background_alpha == null else explicit_background_alpha
		presenter.hud_cfg_ui_bridge_requires_focus = false
		presenter.enable_ui_interaction = shared_viewport == null
	# B3a: el vidrio del presentador no pasa de ~0.7 (en tier LOW queda como venga).
	presenter.hud_cfg_background_alpha = min(presenter.hud_cfg_background_alpha, widget_alpha())
	var mesh: CSGBox = presenter.get_node("ScreenContainer/ScreenMesh")
	mesh.width = mesh.height * presenter.screen_resolution.x / presenter.screen_resolution.y
	world.add_child(presenter)
	var viewport: Viewport = presenter.get_node("Viewport")
	presenter.global_transform.origin = _origin(snapshot, host)
	# No es parte del mundo simulado (igual que DebugConsoleHUD) ni recibe input: ESC es del overlay.
	presenter.remove_from_group("replay_sync")
	if shared_viewport != null:
		var material = mesh.material
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_param("texture_albedo", shared_viewport.get_texture())
		viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
		_shared_screen = screen
	else:
		if design.x > 0.0 and design.y > 0.0:
			viewport.size = design
		var view: Control = scene.instance()
		viewport.add_child(view)
		view.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	presenter.set_active(true)
	if snap_to_camera:
		mesh.visible = false
		if shared_viewport == null:
			viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
		else:
			viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
		presenter.set_physics_process(false)
	presenter.set_process_input(snap_to_camera and shared_viewport == null)
	_presenter = presenter
	_presenter_snapped = snap_to_camera
	return true

# "La pantalla se desprende del terminal y viene a tu casco": arranca donde esta la fuente.
func _origin(snapshot: Dictionary, host: Control) -> Vector3:
	var pos = snapshot.get("position")
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var camera: Camera = host.get_viewport().get_camera()
	if camera == null:
		return Vector3.ZERO
	return camera.global_transform.origin - camera.global_transform.basis.z * FRONT_DISTANCE

func _open_view_2d(scene: PackedScene, screen: Object, snapshot: Dictionary, host: Control) -> bool:
	var design: Vector2 = screen.view_size() if screen.has_method("view_size") else Vector2.ZERO
	if design.x <= 0.0 or design.y <= 0.0:
		return false
	var frame := Control.new()
	frame.name = "ViewFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(frame)
	frame.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var container := ViewportContainer.new()
	container.name = "ViewViewport"
	# stretch=false: el Viewport se queda en su tamaño de diseño; se escala como se dibuja.
	container.stretch = false
	container.rect_size = design
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	container.material = holo_material_2d()
	var viewport := Viewport.new()
	viewport.size = design
	viewport.usage = Viewport.USAGE_2D
	viewport.transparent_bg = true
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	frame.add_child(container)
	container.add_child(viewport)
	var view: Control = scene.instance()
	viewport.add_child(view)
	view.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_hydrate(view, snapshot)
	_view_frame = frame
	_view_node = view
	frame.connect("resized", self, "fit_view_2d")
	fit_view_2d()
	_watch_screen(screen)
	return true

# El holograma del presentador en 2D: su shader de vidrio con los mismos valores, leidos de
# HudViewPresenter.tscn (el alfa del vidrio es hud_cfg_background_alpha, como en HoloTerminalV2).
static func holo_material_2d() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HoloScreen2DShader
	var albedo := Color(0.301961, 0.470588, 0.505882, 0.15)
	material.set_shader_param("emission_energy", 3.0)
	material.set_shader_param("hologram_alpha", 1.0)
	material.set_shader_param("ink_level", 0.686)
	var state: SceneState = PresenterScene.get_state()
	var glass_alpha = null
	for node in range(state.get_node_count()):
		for i in range(state.get_node_property_count(node)):
			var property: String = state.get_node_property_name(node, i)
			var value = state.get_node_property_value(node, i)
			if property == "hud_cfg_background_alpha":
				glass_alpha = value
			elif property == "material" and value is ShaderMaterial:
				for param in ["albedo", "emission_energy", "hologram_alpha", "ink_level"]:
					var source_value = value.get_shader_param(param)
					if param == "albedo" and source_value is Color:
						albedo = source_value
					elif source_value != null:
						material.set_shader_param(param, source_value)
	if glass_alpha != null:
		albedo.a = float(glass_alpha)
	material.set_shader_param("albedo", albedo)
	return material

# Escalado uniforme por el lado que sobra, y centrado en el lugar de la vista.
func fit_view_2d() -> void:
	if not is_instance_valid(_view_frame):
		return
	var container: Control = _view_frame.get_node("ViewViewport")
	var room: Vector2 = _view_frame.rect_size
	var design: Vector2 = container.rect_size
	if room.x <= 0.0 or room.y <= 0.0:
		return
	var factor: float = min(room.x / design.x, room.y / design.y)
	container.rect_scale = Vector2(factor, factor)
	container.rect_position = (room - design * factor) * 0.5

func _hydrate(node: Node, snapshot: Dictionary) -> void:
	if node.has_method("update_snapshot"):
		node.update_snapshot(snapshot)
	elif node.has_method("set_snapshot"):
		node.set_snapshot(snapshot)

func _watch_screen(screen: Object) -> void:
	if screen.has_signal("state_changed") and not screen.is_connected("state_changed", self, "_on_widget_screen_changed"):
		screen.connect("state_changed", self, "_on_widget_screen_changed")
		_widget_screen = screen

func _open_widget(screen: Object, snapshot: Dictionary, host: Control) -> void:
	# Y si tampoco hay widget, el titulo.
	var scene: PackedScene = screen.widget_scene() if screen.has_method("widget_scene") else null
	var widget: Control = scene.instance() if scene != null else Label.new()
	if scene == null:
		(widget as Label).text = String(snapshot.get("title", snapshot.get("id", "")))
	widget.name = "WidgetFallback"
	host.add_child(widget)
	# B3a: el panel del widget ampliado tambien va semi-transparente (opaco en tier LOW).
	apply_widget_panel_alpha(widget)
	if widget.has_method("update_snapshot"):
		widget.update_snapshot(snapshot)
	widget.set_anchors_and_margins_preset(Control.PRESET_CENTER)
	widget.rect_pivot_offset = widget.rect_size * 0.5
	widget.rect_scale = Vector2(WIDGET_ZOOM, WIDGET_ZOOM)
	_widget = widget
	_watch_screen(screen)

func _on_widget_screen_changed() -> void:
	if not is_instance_valid(_widget_screen) or not _widget_screen.has_method("widget_snapshot"):
		return
	for node in [_widget, _view_node]:
		if is_instance_valid(node):
			_hydrate(node, _widget_screen.widget_snapshot())
