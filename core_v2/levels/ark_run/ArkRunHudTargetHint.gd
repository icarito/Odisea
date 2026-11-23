extends Control

# FD-324 F7 — marcador de destino 3D→2D (pantalla) con flecha al borde.
# Muestra un diamante/chevron luminoso sobre el objetivo con su distancia y, si
# queda fuera de pantalla o detrás de la cámara, lo ancla al borde con una flecha
# que apunta hacia dónde girar. Sólo presentación: no toca el estado del juego.

const MARGIN := 48.0
const MARKER_RADIUS := 11.0

var _marker: Line2D = null
var _label: Label = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_marker = Line2D.new()
	_marker.width = 2.5
	var points := PoolVector2Array([
		Vector2(0.0, -MARKER_RADIUS), Vector2(MARKER_RADIUS, 0.0),
		Vector2(0.0, MARKER_RADIUS), Vector2(-MARKER_RADIUS, 0.0),
		Vector2(0.0, -MARKER_RADIUS),
	])
	_marker.points = points
	add_child(_marker)
	_label = Label.new()
	_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	_label.add_constant_override("shadow_offset_x", 1)
	_label.add_constant_override("shadow_offset_y", 1)
	add_child(_label)
	visible = false

# Proyección pura y testeable: posición en pantalla, dirección de giro y
# distancia. Fuera de pantalla/detrás se ancla al borde con margen.
static func project_hint(camera: Camera, world: Vector3, viewport_size: Vector2,
		margin: float = MARGIN) -> Dictionary:
	if camera == null:
		return {"onscreen": false, "position": Vector2.ZERO, "direction": Vector2.ZERO, "distance": 0.0}
	var projected: Vector2 = camera.unproject_position(world)
	var behind: bool = camera.is_position_behind(world)
	var center: Vector2 = viewport_size * 0.5
	var direction: Vector2 = projected - center
	if behind:
		direction = -direction
	if direction.length_squared() < 0.0001:
		direction = Vector2(0.0, -1.0)
	var distance: float = camera.global_transform.origin.distance_to(world)
	var inside: bool = not behind and projected.x >= margin and projected.x <= viewport_size.x - margin \
		and projected.y >= margin and projected.y <= viewport_size.y - margin
	if inside:
		return {"onscreen": true, "position": projected, "direction": direction.normalized(), "distance": distance}
	var dir: Vector2 = direction.normalized()
	var half: Vector2 = center - Vector2(margin, margin)
	var tx: float = half.x / max(abs(dir.x), 0.0001)
	var ty: float = half.y / max(abs(dir.y), 0.0001)
	return {"onscreen": false, "position": center + dir * min(tx, ty), "direction": dir, "distance": distance}

func update_hint(camera: Camera, world: Vector3, label: String, color: Color) -> void:
	var hint: Dictionary = project_hint(camera, world, get_viewport_rect().size, MARGIN)
	visible = camera != null
	if not visible:
		return
	_marker.position = hint["position"]
	_marker.default_color = color
	var dir: Vector2 = hint["direction"]
	_marker.rotation = 0.0 if bool(hint["onscreen"]) else atan2(dir.y, dir.x) + PI * 0.5
	_label.text = "%s · %d m" % [label, int(round(float(hint["distance"])))]
	_label.add_color_override("font_color", color)
	_label.rect_position = (hint["position"] as Vector2) + Vector2(16.0, -10.0)
