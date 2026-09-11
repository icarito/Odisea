extends Reference

# HudViewMount.gd - Vista de la pantalla elegida en el modo HUD (FD-296 F3, spec 4.3b).
# Con view_scene(): presentador 3D config-only (HudViewPresenter.tscn = HelmetHUDV2 + config)
# que nace en el terminal de origen y TerminalHUDBridge engancha a la camara con la transicion
# del casco; se lee como holograma por hud_cfg_background_alpha/emission. Su Viewport es propio
# (nada de ViewportTexture del mundo). Sin view_scene(): el widget del slot, ampliado, en 2D.

const PresenterScene = preload("res://core_v2/ui/hud/HudViewPresenter.tscn")
const WIDGET_ZOOM := 3.0
# Sin posicion de origen, el presentador arranca a esta distancia frente a la camara.
const FRONT_DISTANCE := 1.5
# Tiempo para que el presentador se encoja (anim_duration del casco) antes de liberarlo.
const FREE_DELAY := 0.6

var _presenter: Spatial = null
var _widget: Control = null

func is_showing() -> bool:
	return is_instance_valid(_presenter) or is_instance_valid(_widget)

func get_presenter() -> Spatial:
	return _presenter if is_instance_valid(_presenter) else null

func get_widget() -> Control:
	return _widget if is_instance_valid(_widget) else null

func show(screen: Object, snapshot: Dictionary, host: Control) -> void:
	close()
	var scene: PackedScene = screen.view_scene() if screen.has_method("view_scene") else null
	if scene == null or not _open_presenter(scene, screen, snapshot, host):
		_open_widget(screen, snapshot, host)

func close() -> void:
	if is_instance_valid(_widget):
		_widget.queue_free()
	_widget = null
	if is_instance_valid(_presenter):
		_presenter.set_active(false)
		_presenter.get_tree().create_timer(FREE_DELAY, true).connect("timeout", _presenter, "queue_free")
	_presenter = null

func _open_presenter(scene: PackedScene, screen: Object, snapshot: Dictionary, host: Control) -> bool:
	var world: Node = host.get_tree().current_scene
	if world == null:
		return false
	var presenter: Spatial = PresenterScene.instance()
	var design: Vector2 = screen.view_size() if screen.has_method("view_size") else Vector2.ZERO
	if design.x > 0.0 and design.y > 0.0:
		presenter.screen_resolution = design # antes del _ready: de ahi sale el tamaño del Viewport
	var mesh: CSGBox = presenter.get_node("ScreenContainer/ScreenMesh")
	mesh.width = mesh.height * presenter.screen_resolution.x / presenter.screen_resolution.y
	world.add_child(presenter)
	presenter.global_transform.origin = _origin(snapshot, host)
	# No es parte del mundo simulado (igual que DebugConsoleHUD) ni recibe input: ESC es del overlay.
	presenter.remove_from_group("replay_sync")
	var view: Control = scene.instance()
	presenter.get_node("Viewport").add_child(view)
	view.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	presenter.set_active(true)
	presenter.set_process_input(false)
	_presenter = presenter
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
