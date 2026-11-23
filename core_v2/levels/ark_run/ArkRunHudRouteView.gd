extends Reference

# FD-325 polish — lógica de HUD de rutas/estado del Ark Run, extraída para que
# ArkRunHudOverlay quede <200 líneas. Funciones puras sobre snapshots + helpers que
# manejan los marcadores 3D→2D (destino y waypoint secundario) y la línea de rumbo.

const TargetHintScript = preload("res://core_v2/levels/ark_run/ArkRunHudTargetHint.gd")
const RouteArrow = preload("res://core_v2/levels/ark_run/ArkRunRouteArrow.gd")
const BRIDGE_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const ENGINE_ORANGE := Color(1.0, 0.4, 0.15, 1.0)
const ROUTE_CYAN := Color(0.35, 0.92, 1.0, 1.0)

# Línea de estado (mapa): g, Δv y estado de cuerda.
static func stats_line(data: Dictionary) -> String:
	var g_mag: float = float(data.get("g", 0.0))
	var state := "g %.1f m/s² · Δv %d%%" % [g_mag, int(round(float(data.get("dv", 0.0)) * 100.0))]
	var rope: String = String(data.get("rope", "IDLE"))
	if rope == "ATTACHED":
		state += " · CUERDA ENGANCHADA"
	elif rope == "REELING":
		state += " · CUERDA RETRACCIÓN"
	elif rope == "READY":
		state += " · CUERDA LISTA (%d m)" % int(round(float(data.get("rope_distance", 0.0))))
	if bool(data.get("thrusting", false)):
		state = "PROPULSOR ACTIVO · " + state
	return state

# Marcador principal PUENTE/MOTOR (se oculta al ganar) y secundario cian de ruta.
static func update_markers(primary, secondary, data: Dictionary, cam) -> void:
	var target = data.get("target_pos", null)
	if not bool(data.get("target_visible", true)):
		if primary != null:
			primary.visible = false
	elif typeof(target) == TYPE_VECTOR3 and primary != null:
		var label: String = String(data.get("target_label", "PUENTE"))
		primary.update_hint(cam, target, label, BRIDGE_GOLD if label == "PUENTE" else ENGINE_ORANGE)
	elif primary != null:
		primary.visible = false
	var wp = data.get("next_waypoint_pos", null)
	if bool(data.get("next_waypoint_visible", false)) and typeof(wp) == TYPE_VECTOR3 and secondary != null:
		secondary.update_hint(cam, wp, "RUTA", ROUTE_CYAN)
	elif secondary != null:
		secondary.visible = false

# Texto de rumbo con flecha según dónde proyecta el objetivo en pantalla.
static func route_text(data: Dictionary, cam, view_size: Vector2) -> String:
	var text := String(data.get("route_arrow", ""))
	var target = data.get("target_pos", null)
	if text == "" or cam == null or typeof(target) != TYPE_VECTOR3:
		return text
	return RouteArrow.format_route(text, RouteArrow.arrow_for(cam.unproject_position(target), view_size))
