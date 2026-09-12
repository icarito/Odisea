extends Reference

# HudViewMount.gd - Vista de la pantalla elegida en el modo HUD (FD-296 F3, spec 4.3b).
# Con view_scene(): presentador 3D config-only (HudViewPresenter.tscn = HelmetHUDV2 + config)
# que nace en el terminal de origen y TerminalHUDBridge engancha a la camara con la transicion
# del casco; se lee como holograma por hud_cfg_background_alpha/emission. Si la pantalla presta
# su Viewport, el presentador usa esa misma textura. Sin view_scene(): widget ampliado en 2D.

const PresenterScene = preload("res://core_v2/ui/hud/HudViewPresenter.tscn")
const WIDGET_ZOOM := 3.0
# Sin posicion de origen, el presentador arranca a esta distancia frente a la camara.
const FRONT_DISTANCE := 1.5
# Tiempo para que el presentador se encoja (anim_duration del casco) antes de liberarlo.
const FREE_DELAY := 0.6

var _presenter: Spatial = null
var _widget: Control = null
var _presenter_snapped: bool = false
var _shared_screen: Object = null

func is_showing() -> bool:
	return is_instance_valid(_presenter) or is_instance_valid(_widget)

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
	if scene == null or not _open_presenter(scene, screen, snapshot, host, snap_to_camera):
		_open_widget(screen, snapshot, host)

func close() -> void:
	if is_instance_valid(_shared_screen) and _shared_screen.has_method("release_viewport"):
		_shared_screen.release_viewport()
	_shared_screen = null
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	if is_instance_valid(_presenter):
		if _presenter_snapped:
			_presenter.set_active(false) # devuelve el ScreenMesh reparentado antes de liberar el presentador
			_presenter.queue_free()
		else:
			_presenter.set_active(false)
			_presenter.get_tree().create_timer(FREE_DELAY, true).connect("timeout", _presenter, "queue_free")
	_presenter = null
	_presenter_snapped = false

func _open_presenter(scene: PackedScene, screen: Object, snapshot: Dictionary, host: Control, snap_to_camera: bool) -> bool:
	var world: Node = host.get_tree().current_scene
	if world == null:
		return false
	var presenter: Spatial = PresenterScene.instance()
	var design: Vector2 = screen.view_size() if screen.has_method("view_size") else Vector2.ZERO
	var shared_viewport: Viewport = screen.borrow_viewport() if snap_to_camera and screen.has_method("borrow_viewport") else null
	if design.x > 0.0 and design.y > 0.0:
		presenter.screen_resolution = design # antes del _ready: de ahi sale el tamaño del Viewport
	if snap_to_camera:
		presenter.hud_cfg_attach_transition_time = 0.0
		presenter.hud_cfg_screen_depth = 1.0
		presenter.hud_cfg_background_alpha = 0.0
		presenter.hud_cfg_ui_bridge_requires_focus = false
		presenter.enable_ui_interaction = shared_viewport == null
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

func _open_widget(screen: Object, snapshot: Dictionary, host: Control) -> void:
	# Y si tampoco hay widget, el titulo.
	var scene: PackedScene = screen.widget_scene() if screen.has_method("widget_scene") else null
	var widget: Control = scene.instance() if scene != null else Label.new()
	if scene == null:
		(widget as Label).text = String(snapshot.get("title", snapshot.get("id", "")))
	widget.name = "WidgetFallback"
	host.add_child(widget)
	if widget.has_method("update_snapshot"):
		widget.update_snapshot(snapshot)
	widget.set_anchors_and_margins_preset(Control.PRESET_CENTER)
	widget.rect_pivot_offset = widget.rect_size * 0.5
	widget.rect_scale = Vector2(WIDGET_ZOOM, WIDGET_ZOOM)
	_widget = widget
