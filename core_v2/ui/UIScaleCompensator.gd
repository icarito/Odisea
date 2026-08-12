extends Control

# Mantiene una UI del mismo tamaño relativo a la pantalla aunque baje la escala de render.
#
# El proyecto usa stretch "viewport": TODO (3D y UI) se dibuja en un viewport de
# render_resolution * render_scale y se estira a la pantalla. Bajar la escala encoge
# ese espacio de coordenadas, y lo que este medido en pixeles fijos (un boton touch de
# 160x50, el rect_min_size de un panel) pasa a ocupar mucha mas pantalla: al 60% sobre
# 640x480 quedan 384x288, los controles crecen un 66% y llegan a taparse entre si o a
# caer fuera del borde.
#
# La compensacion es puro layout 2D: al Control objetivo se le da el tamaño que tendria
# el viewport a escala 1.0 y se lo encoge con rect_scale por esa misma escala. Sus hijos
# siguen resolviendo anclas y margenes contra el espacio "nominal", asi que el resultado
# en pantalla es identico a escala 1.0 — solo con menos pixeles reales.
#
# No sirve tocar el size_override del viewport raiz para esto: eso redimensiona tambien
# el render target (medido: el 3D deja de ahorrar fill rate y el fps no cambia).

export(NodePath) var target_path: NodePath = NodePath("..")
# Algunas UI ya estan diseñadas para el espacio reducido; permite desactivarlo por escena.
export(bool) var enabled := true

var _target: Control = null
var _applying := false

func _ready() -> void:
	# Es un Control sin tamaño ni dibujo: hay codigo de UI que recorre los hijos de un
	# contenedor y les asigna `visible` (MobileUIManager._set_gameplay_controls_visible),
	# y con un Node pelado eso reventaba. Asi cualquier iteracion de ese tipo lo trata
	# como un hermano invisible mas y no rompe nada.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect_size = Vector2.ZERO
	if not enabled:
		return
	_target = get_node_or_null(target_path) as Control
	if _target == null:
		push_warning("[UIScaleCompensator] target no es un Control: %s" % str(target_path))
		return
	# Sin anclas automaticas el tamaño lo fijamos nosotros; con ellas el engine lo
	# reescribiria al viewport real en cada resize y perderiamos la compensacion.
	_target.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	var viewport := get_viewport()
	if viewport != null and not viewport.is_connected("size_changed", self, "apply"):
		viewport.connect("size_changed", self, "apply")
	apply()

func apply() -> void:
	if not enabled or _applying or not is_instance_valid(_target):
		return
	_applying = true
	var viewport := get_viewport()
	if viewport != null:
		var scale := _ui_scale()
		var available: Vector2 = viewport.get_visible_rect().size
		_target.rect_position = Vector2.ZERO
		_target.rect_size = available / scale
		_target.rect_scale = Vector2(scale, scale)
	_applying = false

# Escala de render vigente (1.0 cuando no hay reduccion o no hay SettingsManager).
func _ui_scale() -> float:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings == null:
		return 1.0
	return clamp(float(settings.render_scale), 0.5, 1.0)
