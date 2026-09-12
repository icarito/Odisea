extends Control
class_name CoolantSchematicPanel

# CoolantSchematicPanel.gd - Schematic pipe diagram displaying real-time status
# of coolant valves and pipe fissures/leaks (FD-270).
# Designed for read-only rendering within holographic display viewports.

const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")

# Color palette
const COLOR_VALVE_OPEN := Color(0.1, 1.0, 0.3)
const COLOR_VALVE_CLOSED := Color(1.0, 0.15, 0.1)

const COLOR_PIPE_HEALTHY := Color(0.2, 0.7, 0.9, 0.8)
const COLOR_PIPE_WARNING := Color(1.0, 0.8, 0.1, 0.9)
const COLOR_PIPE_LEAKING := Color(1.0, 0.2, 0.8, 1.0)
const COLOR_PIPE_DEPRESSURIZED := Color(0.4, 0.4, 0.4, 0.6)

const COLOR_OFFLINE_VALVE := Color(0.5, 0.5, 0.5, 0.8)
const COLOR_OFFLINE_PIPE := Color(0.35, 0.35, 0.35, 0.5)
const COLOR_TEXT := Color(0.8, 0.9, 1.0, 0.85)

# Refrigerante corriendo por dentro del cano: se pinta ENCIMA del trazo de estado, con
# ancho y alfa proporcionales al caudal, para que un tramo sin caudal (valvula cerrada
# aguas abajo, tanque vacio) se lea apagado aunque el cano en si este sano.
const COLOR_FLOW := Color(0.35, 0.95, 1.0, 1.0)
const COLOR_DRY := Color(0.28, 0.32, 0.38, 0.85)

# Parpadeo de fisuras. El panel vive en un Viewport UPDATE_DISABLED, asi que redibujar
# cuesta: solo se pide mientras HAY algo parpadeando, y a 5 Hz, no por frame.
const BLINK_HZ := 2.5
const BLINK_REDRAW_INTERVAL := 0.2

# Vistas ortograficas del circuito real (FD-270, serpentina de dos rieles):
# ALZADO arriba (columnas de riser con valvulas y tramos de piso) y PLANTA abajo
# (proyeccion en planta: rieles en az 180/0 y 105/285, arcos de piso, bucles CryoLoop
# y tanques). Sin interlink: la interconexion oeste-este ya no existe fisicamente;
# si alguna escena trae una valvula interlink, se dibuja como diamante en P5.
const NUM_FLOORS := 6
const X_WEST := 64.0
const X_EAST := 204.0
const Y_BOTTOM := 252.0
const Y_STEP := 36.0
const RUN_LEN := 58.0
const CARD_MARGIN := 24.0

# Planta: origen del domo y escala. Las coordenadas de mundo (x,z) se proyectan
# a (cx + x*S, cy + z*S): planta mirando hacia abajo, +X derecha, +Z hacia abajo.
const PLANTA_CY := 420.0
const PLANTA_S := 7.2
const AZ_W_RAIL := 180.0   # riser oeste (Rail-A)
const AZ_E_RAIL := 0.0     # riser este
const AZ_W_TEE := 105.0    # fin de linea oeste (Rail-B)
const AZ_E_RAIL_B := 285.0 # fin de linea este
const AZ_HUB_W := 189.0    # T del bucle CryoLoop oeste (piso 2)
const AZ_HUB_E := 14.0     # T del bucle este
const DOME_R := 12.0

# Extension real del contenido dibujado, para centrarlo en el ancho disponible de la card.
const CONTENT_LEFT := 24.0
const CONTENT_WIDTH := 300.0

var _connected_valves := []
var _blink_phase := 0.0
var _blink_accum := 0.0
var _blink_on := false

# Estado recibido por apply_state() cuando este panel corre en el control remoto (no hay
# grupo coolant_valve ni gloo_patchable ahi): el mismo view model que collect_state()
# arma del mundo en el host. Dibuja de el; sin datos, dibuja offline como siempre.
var _remote_state: Dictionary = {}

# El bus (HoloTerminalHUDable) propaga esto al snapshot del terminal.
signal state_changed


func _ready() -> void:
	# Este panel vive dentro de un HoloTerminalV2 con static_content=true (Viewport en
	# UPDATE_DISABLED): antes recalculaba un hash sobre 13 valvulas + 24 fisuras CADA
	# frame de fisica, con reflection dinamica (.get()/.call()/has_method()) para
	# detectar si algo cambio. El caudal solo cambia cuando el jugador toca una valvula
	# o una fuga cruza de estado — ambos ya emiten señal. Conectarse a esas señales deja
	# el panel en reposo (0 costo de CPU) salvo cuando el diagrama realmente cambia.
	set_process(false)
	_setup_valve_connections()
	_setup_fissure_connections()
	update()
	# Sin _physics_process el panel ya no tiene un primer frame "gratis" que dispare
	# request_redraw() por su cuenta (asi corria antes, cada tick de fisica). El Viewport
	# padre esta en UPDATE_DISABLED (static_content) y solo redibuja cuando se lo piden
	# explicitamente: sin este pedido inicial, el primer contenido nunca llega a pintarse
	# si nada cambia de estado despues del arranque (fugas en HEALTHY, sin partidas con
	# fuga activa desde el primer segundo).
	_request_redraw()


func _setup_valve_connections() -> void:
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	for valve in valves:
		if is_instance_valid(valve) and valve.has_signal("valve_state_changed"):
			if not valve.is_connected("valve_state_changed", self, "_on_state_changed"):
				valve.connect("valve_state_changed", self, "_on_state_changed")
				_connected_valves.append(valve)


func _setup_fissure_connections() -> void:
	var patch_points: Array = get_tree().get_nodes_in_group("gloo_patchable")
	for patch_point in patch_points:
		if not is_instance_valid(patch_point):
			continue
		if patch_point.has_signal("patch_applied") and not patch_point.is_connected("patch_applied", self, "_on_state_changed"):
			patch_point.connect("patch_applied", self, "_on_state_changed")
		if patch_point.has_signal("patch_expired") and not patch_point.is_connected("patch_expired", self, "_on_state_changed"):
			patch_point.connect("patch_expired", self, "_on_state_changed")
		var leak = patch_point.get("_leak") if "_leak" in patch_point else null
		if leak and is_instance_valid(leak) and leak.has_signal("state_changed"):
			if not leak.is_connected("state_changed", self, "_on_state_changed"):
				leak.connect("state_changed", self, "_on_state_changed")


func _on_state_changed(_arg = null) -> void:
	update()
	_request_redraw()
	emit_signal("state_changed")


# --- DATA BRIDGE (FD-296 F4: el control remoto dibuja del snapshot, no del mundo) ---

# Estado efectivo de un punto de parche: el estado de su fuga, o el degradado que deja
# un parche aun no firme. Es la misma regla que ya usaba el dibujo de planta y
# _map_fissures_to_segments; unificada aca para que collect_state y el dibujo coincidan.
func _effective_patch_state(patch_point) -> int:
	var leak_node = patch_point.get("_leak") if "_leak" in patch_point else null
	var leak_state = CoolantLeak.State.HEALTHY
	if leak_node and is_instance_valid(leak_node) and leak_node.has_method("get_state"):
		leak_state = leak_node.call("get_state")
	if not (patch_point.has_method("is_patched") and patch_point.call("is_patched")):
		return int(leak_state)
	var is_firm: bool = patch_point.call("is_firmly_patched") if patch_point.has_method("is_firmly_patched") else false
	return int(CoolantLeak.State.HEALTHY if is_firm else CoolantLeak.State.WARNING)


func _valve_is_open(valve) -> bool:
	if valve == null or not is_instance_valid(valve) or not ("is_active" in valve):
		return true # sin valvula no hay nada que corte el caudal
	return bool(valve.get("is_active"))


func _valves_open_flags(valves: Array) -> Array:
	var flags: Array = []
	for valve in valves:
		flags.append(_valve_is_open(valve))
	return flags


# Fugas de anillo para la planta: posicion real de mundo + estado efectivo, JSON-safe.
func _collect_planta_leaks(patch_points: Array) -> Array:
	var leaks: Array = []
	for patch_point in patch_points:
		if not is_instance_valid(patch_point):
			continue
		var label_str: String = _floor_label(patch_point).to_lower() + " " + patch_point.name.to_lower()
		if "interlink" in label_str or not ("ring" in label_str):
			continue
		var pos = patch_point.get("global_position") if patch_point is Spatial else null
		if pos == null:
			continue
		var floor_idx: int = _extract_floor_index(label_str)
		leaks.append({
			"pos": [float(pos.x), float(pos.z)],
			"ring": int(clamp(floor_idx, 1, NUM_FLOORS - 1)),
			"state": _effective_patch_state(patch_point)
		})
	return leaks


# Posicion de la fuga del bucle CryoLoop de un lado (piso 2): mismo matcheo que usaba
# el dibujo (primer punto de parche de ese lado). [] si la escena no la trae.
func _collect_hub_pos(patch_points: Array, side: String) -> Array:
	for patch_point in patch_points:
		if not is_instance_valid(patch_point):
			continue
		var label_str: String = _floor_label(patch_point).to_lower() + " " + patch_point.name.to_lower()
		if (side == "east") != ("east" in label_str):
			continue
		var pos = patch_point.get("global_position") if patch_point is Spatial else null
		if pos != null:
			return [float(pos.x), float(pos.z)]
	return []


# Tanques para la planta: posicion + nivel, JSON-safe.
func _collect_tanks() -> Array:
	var out: Array = []
	for tank in get_tree().get_nodes_in_group("coolant_source"):
		if not is_instance_valid(tank) or not ("tank_level" in tank):
			continue
		var pos = tank.get("global_position") if tank is Spatial else null
		if pos == null:
			continue
		out.append({
			"pos": [float(pos.x), float(pos.z)],
			"level": clamp(float(tank.get("tank_level")), 0.0, 1.0)
		})
	return out


# View model completo del circuito desde el mundo vivo. Es lo que viaja al control
# remoto como snapshot["cryo"]["schematic"] y lo unico que el dibujo consume.
func collect_state() -> Dictionary:
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	var patch_points: Array = get_tree().get_nodes_in_group("gloo_patchable")
	if valves.empty() and patch_points.empty():
		return {}

	var layout: Dictionary = _map_valves_to_layout(valves)
	var interlink_valve = layout.get("interlink", null)
	var segment_states: Dictionary = _map_fissures_to_segments(patch_points)

	return {
		"is_live": true,
		"west_open": _valves_open_flags(layout.get("west", [])),
		"east_open": _valves_open_flags(layout.get("east", [])),
		"has_interlink": interlink_valve != null and is_instance_valid(interlink_valve),
		"interlink_open": _valve_is_open(interlink_valve),
		"west_states": segment_states.get("west", []),
		"east_states": segment_states.get("east", []),
		"west_rings": segment_states.get("west_rings", []),
		"east_rings": segment_states.get("east_rings", []),
		"interlink_state": int(segment_states.get("interlink", CoolantLeak.State.HEALTHY)),
		"tank_west": _tank_level("west"),
		"tank_east": _tank_level("east"),
		"tanks": _collect_tanks(),
		"planta_leaks": _collect_planta_leaks(patch_points),
		"hub_west": _collect_hub_pos(patch_points, "west"),
		"hub_east": _collect_hub_pos(patch_points, "east")
	}


func apply_state(data: Dictionary) -> void:
	if typeof(data) != TYPE_DICTIONARY or data.empty():
		return
	_remote_state = data.duplicate(true)
	update()
	_request_redraw()


# El modelo de entrada del dibujo: mundo vivo si existe, si no los datos del host, y
# solo si no hay nada, el circuito offline de siempre (tests, escenas sin circuito).
func _gather_model() -> Dictionary:
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	var patch_points: Array = get_tree().get_nodes_in_group("gloo_patchable")
	if (not valves.empty()) or (not patch_points.empty()):
		return _build_live_model(valves, patch_points)
	if not _remote_state.empty():
		return _remote_state
	return _offline_model()


func _build_live_model(valves: Array, patch_points: Array) -> Dictionary:
	var layout: Dictionary = _map_valves_to_layout(valves)
	var interlink_valve = layout.get("interlink", null)
	var segment_states: Dictionary = _map_fissures_to_segments(patch_points)
	return {
		"is_live": true,
		"west_open": _valves_open_flags(layout.get("west", [])),
		"east_open": _valves_open_flags(layout.get("east", [])),
		"has_interlink": interlink_valve != null and is_instance_valid(interlink_valve),
		"interlink_open": _valve_is_open(interlink_valve),
		"west_states": segment_states.get("west", []),
		"east_states": segment_states.get("east", []),
		"west_rings": segment_states.get("west_rings", []),
		"east_rings": segment_states.get("east_rings", []),
		"interlink_state": int(segment_states.get("interlink", CoolantLeak.State.HEALTHY)),
		"tank_west": _tank_level("west"),
		"tank_east": _tank_level("east"),
		"tanks": _collect_tanks(),
		"planta_leaks": _collect_planta_leaks(patch_points),
		"hub_west": _collect_hub_pos(patch_points, "west"),
		"hub_east": _collect_hub_pos(patch_points, "east")
	}


func _offline_model() -> Dictionary:
	var states := []
	var rings := []
	for _i in range(NUM_FLOORS - 1):
		states.append(CoolantLeak.State.HEALTHY)
	for _i in range(NUM_FLOORS):
		rings.append(CoolantLeak.State.HEALTHY)
	return {
		"is_live": false,
		"west_open": [], "east_open": [], "has_interlink": false, "interlink_open": true,
		"west_states": states, "east_states": states.duplicate(),
		"west_rings": rings, "east_rings": rings.duplicate(),
		"interlink_state": CoolantLeak.State.HEALTHY,
		"tank_west": 1.0, "tank_east": 1.0,
		"tanks": _collect_tanks(),
		"planta_leaks": [], "hub_west": [], "hub_east": []
	}


func _flows_for(model: Dictionary) -> Dictionary:
	var west_flow: Dictionary = _solve_column_flow(model.get("west_open", []),
		model.get("west_states", []), model.get("west_rings", []), float(model.get("tank_west", 1.0)))
	var east_flow: Dictionary = _solve_column_flow(model.get("east_open", []),
		model.get("east_states", []), model.get("east_rings", []), float(model.get("tank_east", 1.0)))
	return {"west": west_flow, "east": east_flow}


func _draw() -> void:
	# Mismo theme "ship OS" que el resto de terminales (retro_scifi.tres, Panel/styles/panel):
	# este Control dibuja a mano, no es un Panel, asi que el fondo/borde holografico hay que
	# pedirselo al theme heredado y pintarlo nosotros mismos.
	# La card ocupa el rect propio MENOS un respiro CARD_MARGIN en cada borde: si se pinta el
	# rect completo, tres columnas vecinas se ven como un solo bloque de color pegado, no
	# como tres cards separadas.
	var panel_style: StyleBox = get_stylebox("panel", "Panel")
	var half_gap := CARD_MARGIN * 0.5
	if panel_style != null:
		var inset := Rect2(Vector2(half_gap, half_gap), rect_size - Vector2(CARD_MARGIN, CARD_MARGIN))
		panel_style.draw(get_canvas_item(), inset)

	# El resto del diagrama va desplazado adentro del borde de la card, en vez de pegado al
	# filo que acaba de pintar panel_style. El contenido dibujado ocupa un ancho fijo de
	# CONTENT_WIDTH: centrarlo en el ancho disponible en vez de pegarlo al borde izquierdo.
	var available_width: float = rect_size.x - CARD_MARGIN * 2.0
	var center_offset: float = max((available_width - CONTENT_WIDTH) * 0.5, 0.0)
	draw_set_transform(Vector2(CARD_MARGIN + center_offset - CONTENT_LEFT, CARD_MARGIN), 0.0, Vector2.ONE)

	var model: Dictionary = _gather_model()
	var flows: Dictionary = _flows_for(model)

	var font = get_font("font")
	var blinking := false
	blinking = _draw_alzado(model, flows, font) or blinking
	blinking = _draw_planta(model, flows, font) or blinking

	_set_blinking(blinking)


# Vista ortografica ALZADO: las dos columnas de riser con sus valvulas, y el tramo de
# piso de cada nivel corriendo hacia adentro hasta su T de fin en Rail-B. Ya no hay
# medio-toros que se encuentren en un LINK central: esa interconexion no existe.
# Consume el view model (valvulas como flags open/closed, estados como ints), no nodos:
# asi el mismo dibujo sirve en el host (modelo del mundo) y en el control remoto
# (modelo recibido por apply_state).
func _draw_alzado(model: Dictionary, flows: Dictionary, font) -> bool:
	var blinking := false
	var is_live: bool = bool(model.get("is_live", false))
	var west_open: Array = model.get("west_open", [])
	var east_open: Array = model.get("east_open", [])
	var west_states: Array = model.get("west_states", [])
	var east_states: Array = model.get("east_states", [])
	var west_rings: Array = model.get("west_rings", [])
	var east_rings: Array = model.get("east_rings", [])
	var west_flow: Dictionary = flows["west"]
	var east_flow: Dictionary = flows["east"]
	var interlink_state: int = int(model.get("interlink_state", CoolantLeak.State.HEALTHY))
	if font != null:
		draw_string(font, Vector2(X_WEST - 20, 16), "OESTE", COLOR_TEXT)
		draw_string(font, Vector2(X_EAST - 14, 16), "ESTE", COLOR_TEXT)
		draw_string(font, Vector2(X_WEST - 40, Y_BOTTOM + Y_STEP + 6), "ALZADO", COLOR_TEXT)

	# 1-2. Columnas verticales (riser). Tramo i = del piso i al piso i+1.
	for i in range(NUM_FLOORS - 1):
		var y_a: float = Y_BOTTOM - float(i) * Y_STEP
		var y_b: float = Y_BOTTOM - float(i + 1) * Y_STEP
		_draw_pipe(Vector2(X_WEST, y_a), Vector2(X_WEST, y_b),
			int(west_states[i]) if i < west_states.size() else CoolantLeak.State.HEALTHY,
			float(west_flow["trunk"][i]), is_live, 3.5)
		_draw_pipe(Vector2(X_EAST, y_a), Vector2(X_EAST, y_b),
			int(east_states[i]) if i < east_states.size() else CoolantLeak.State.HEALTHY,
			float(east_flow["trunk"][i]), is_live, 3.5)

	# 3. Tramo de piso por nivel: del riser hacia adentro hasta Rail-B, donde la linea
	# termina en su T (la geometria real: no hay loop que cruce al otro lado).
	for f in range(1, NUM_FLOORS):
		var y: float = Y_BOTTOM - float(f) * Y_STEP
		var w_state: int = int(west_rings[f]) if f < west_rings.size() else CoolantLeak.State.HEALTHY
		var e_state: int = int(east_rings[f]) if f < east_rings.size() else CoolantLeak.State.HEALTHY
		var dir_w := Vector2(1, 0)
		var dir_e := Vector2(-1, 0)
		_draw_pipe(Vector2(X_WEST, y), Vector2(X_WEST, y) + dir_w * RUN_LEN, w_state,
			float(west_flow["ring"][f]), is_live, 3.0)
		_draw_pipe(Vector2(X_EAST, y), Vector2(X_EAST, y) + dir_e * RUN_LEN, e_state,
			float(east_flow["ring"][f]), is_live, 3.0)
		# T de fin (Rail-B): vareta perpendicular al tramo.
		var end_w := Vector2(X_WEST, y) + dir_w * RUN_LEN
		var end_e := Vector2(X_EAST, y) + dir_e * RUN_LEN
		draw_line(end_w + Vector2(0, -4), end_w + Vector2(0, 4), COLOR_OFFLINE_PIPE, 2.0, true)
		draw_line(end_e + Vector2(0, -4), end_e + Vector2(0, 4), COLOR_OFFLINE_PIPE, 2.0, true)
		# La fisura del anillo vive pegada al riser (az 180): marcador al inicio del tramo.
		blinking = _draw_fissure_marker(Vector2(X_WEST + 12, y), w_state, is_live) or blinking
		blinking = _draw_fissure_marker(Vector2(X_EAST - 12, y), e_state, is_live) or blinking

	# 4-5. Valvulas de cada columna.
	for i in range(NUM_FLOORS):
		var pos_w := Vector2(X_WEST, Y_BOTTOM - float(i) * Y_STEP)
		var pos_e := Vector2(X_EAST, Y_BOTTOM - float(i) * Y_STEP)
		draw_circle(pos_w, 6.5, _valve_color(bool(west_open[i]) if i < west_open.size() else true, is_live))
		draw_circle(pos_e, 6.5, _valve_color(bool(east_open[i]) if i < east_open.size() else true, is_live))
		if font != null:
			draw_string(font, Vector2(X_WEST - 32, pos_w.y + 4), "P%d" % i, COLOR_TEXT)
			draw_string(font, Vector2(X_EAST + 12, pos_e.y + 4), "P%d" % i, COLOR_TEXT)

	# 6. Valvula de interconexion: solo si la escena trae una (el domo ya no la tiene).
	if bool(model.get("has_interlink", false)):
		var mid := Vector2((X_WEST + X_EAST) * 0.5, Y_BOTTOM - float(NUM_FLOORS - 1) * Y_STEP)
		draw_circle(mid, 7.5, _valve_color(bool(model.get("interlink_open", true)), is_live))
		if _is_compromised(int(interlink_state)):
			blinking = _draw_fissure_marker(mid, int(interlink_state), is_live) or blinking

	# 7. Marcador de fisura del tronco sobre cada tramo comprometido, parpadeando.
	for i in range(NUM_FLOORS - 1):
		var y_mid: float = Y_BOTTOM - (float(i) + 0.5) * Y_STEP
		blinking = _draw_fissure_marker(Vector2(X_WEST, y_mid), int(west_states[i]) if i < west_states.size() else CoolantLeak.State.HEALTHY, is_live) or blinking
		blinking = _draw_fissure_marker(Vector2(X_EAST, y_mid), int(east_states[i]) if i < east_states.size() else CoolantLeak.State.HEALTHY, is_live) or blinking
	return blinking


# Vista ortografica PLANTA: proyeccion superior del domo. Rieles en az 180/0
# (Rail-A, los risers) y 105/285 (Rail-B, el fin de cada linea), arcos de piso por
# nivel, bucles CryoLoop del piso 2 y tanques con su nivel. Los marcadores de fuga
# de anillo se dibujan en su posicion real del mundo (viajan en el modelo como [x,z]).
func _draw_planta(model: Dictionary, flows: Dictionary, font) -> bool:
	var blinking := false
	var is_live: bool = bool(model.get("is_live", false))
	var west_rings: Array = model.get("west_rings", [])
	var east_rings: Array = model.get("east_rings", [])
	var west_flow: Dictionary = flows["west"]
	var east_flow: Dictionary = flows["east"]
	var patch_points: Array = model.get("planta_leaks", [])
	var cx := CONTENT_LEFT + CONTENT_WIDTH * 0.5
	var cy := PLANTA_CY

	# Cascaron del domo y cruz de centro, de referencia.
	draw_arc(Vector2(cx, cy), DOME_R * PLANTA_S, 0.0, TAU, 64, Color(COLOR_OFFLINE_PIPE, 0.55), 1.5, true)
	draw_line(Vector2(cx - 5, cy), Vector2(cx + 5, cy), Color(COLOR_OFFLINE_PIPE, 0.55), 1.0, true)
	draw_line(Vector2(cx, cy - 5), Vector2(cx, cy + 5), Color(COLOR_OFFLINE_PIPE, 0.55), 1.0, true)

	# Rieles: el riser es un punto en planta (tubo vertical); Rail-B una vareta.
	var rail_w := _planta_pt(-DOME_R, 0.0)
	var rail_e := _planta_pt(DOME_R, 0.0)
	draw_circle(rail_w, 4.0, COLOR_OFFLINE_PIPE)
	draw_circle(rail_e, 4.0, COLOR_OFFLINE_PIPE)
	draw_circle(_planta_pt(-DOME_R * cos(deg2rad(180.0 - AZ_W_TEE)), DOME_R * sin(deg2rad(180.0 - AZ_W_TEE))), 2.5, Color(COLOR_OFFLINE_PIPE, 0.8))
	draw_circle(_planta_pt(DOME_R * cos(deg2rad(180.0 - AZ_W_TEE)), -DOME_R * sin(deg2rad(180.0 - AZ_W_TEE))), 2.5, Color(COLOR_OFFLINE_PIPE, 0.8))

	# Arcos de piso: se abanican +-4 px por nivel para poder leerlos apilados; en la
	# geometria real todos viven a r=12.
	for f in range(1, NUM_FLOORS):
		var r_f: float = (DOME_R * PLANTA_S) + float(f - 3) * 4.0
		var w_state: int = int(west_rings[f]) if f < west_rings.size() else CoolantLeak.State.HEALTHY
		var e_state: int = int(east_rings[f]) if f < east_rings.size() else CoolantLeak.State.HEALTHY
		var w_col: Color = _get_pipe_color(w_state, is_live)
		var e_col: Color = _get_pipe_color(e_state, is_live)
		if is_live and _is_compromised(w_state):
			w_col = w_col.linear_interpolate(Color(1, 1, 1, 1), _blink_pulse() * 0.55)
		if is_live and _is_compromised(e_state):
			e_col = e_col.linear_interpolate(Color(1, 1, 1, 1), _blink_pulse() * 0.55)
		var flow_w: float = float(west_flow["ring"][f])
		var flow_e: float = float(east_flow["ring"][f])
		if is_live and flow_w <= 0.001:
			w_col = COLOR_DRY
		if is_live and flow_e <= 0.001:
			e_col = COLOR_DRY
		# Oeste: az 105 -> 189 (el tramo remanente hasta la T del bucle en el piso 2);
		# resto de pisos: az 105 -> 180. Este espejado: az 285 -> 374 / 360.
		var start_w := AZ_W_TEE
		var end_w := AZ_W_RAIL if f != 1 else AZ_HUB_W
		var start_e := AZ_E_RAIL_B
		var end_e := AZ_E_RAIL + 360.0 if f != 1 else AZ_HUB_E + 360.0
		draw_arc(Vector2(cx, cy), r_f, deg2rad(start_w), deg2rad(end_w), 24, w_col, 2.5, true)
		draw_arc(Vector2(cx, cy), r_f, deg2rad(start_e), deg2rad(end_e), 24, e_col, 2.5, true)
		if is_live and flow_w > 0.001:
			draw_arc(Vector2(cx, cy), r_f, deg2rad(start_w), deg2rad(end_w), 24,
				Color(COLOR_FLOW.r, COLOR_FLOW.g, COLOR_FLOW.b, 0.25 + 0.5 * flow_w), 1.0, true)
		if is_live and flow_e > 0.001:
			draw_arc(Vector2(cx, cy), r_f, deg2rad(start_e), deg2rad(end_e), 24,
				Color(COLOR_FLOW.r, COLOR_FLOW.g, COLOR_FLOW.b, 0.25 + 0.5 * flow_e), 1.0, true)

	# Bucles CryoLoop del piso 2: ramal desde su T (az 189 / 14) hasta la posicion real
	# de la fuga del bucle, y un circulito marcando el bucle.
	for hub in [{"az": AZ_HUB_W, "tag": "hub_west", "rings": west_rings}, {"az": AZ_HUB_E, "tag": "hub_east", "rings": east_rings}]:
		var hub_pos: Array = model.get(str(hub["tag"]), [])
		if hub_pos.size() < 2:
			continue
		var leak_pos := _planta_pt(float(hub_pos[0]), float(hub_pos[1]))
		var t0 := _planta_pt(DOME_R * cos(deg2rad(float(hub["az"]))), DOME_R * sin(deg2rad(float(hub["az"]))))
		var state_hub: int = int(hub["rings"][1]) if 1 < (hub["rings"] as Array).size() else CoolantLeak.State.HEALTHY
		draw_line(t0, leak_pos, _get_pipe_color(state_hub, is_live), 2.0, true)
		draw_circle(leak_pos, 3.5, _get_pipe_color(state_hub, is_live))
		blinking = _draw_fissure_marker(leak_pos, state_hub, is_live) or blinking

	# Tanques: circulo con relleno proporcional al nivel (posiciones viajan en el modelo).
	for tank in model.get("tanks", []):
		var tpos: Array = tank.get("pos", [])
		if tpos.size() < 2:
			continue
		var tp := _planta_pt(float(tpos[0]), float(tpos[1]))
		var level: float = clamp(float(tank.get("level", 1.0)), 0.0, 1.0)
		draw_circle(tp, 2.5 * PLANTA_S, Color(COLOR_OFFLINE_PIPE, 0.4))
		draw_arc(tp, 2.5 * PLANTA_S, 0.0, TAU, 32, COLOR_TEXT, 1.5, true)
		if level > 0.01:
			draw_circle(tp, (2.5 * PLANTA_S - 2.0) * level, Color(COLOR_FLOW.r, COLOR_FLOW.g, COLOR_FLOW.b, 0.45))

	# Marcadores de fuga de anillo en su posicion real, sobre el arco de su piso.
	for leak in patch_points:
		var lpos: Array = leak.get("pos", [])
		if lpos.size() < 2:
			continue
		var ring_idx: int = int(clamp(int(leak.get("ring", 1)), 1, NUM_FLOORS - 1))
		var leak_state: int = int(leak.get("state", CoolantLeak.State.HEALTHY))
		var r_f: float = (DOME_R * PLANTA_S) + float(ring_idx - 3) * 4.0
		var az := rad2deg(atan2(float(lpos[1]), float(lpos[0])))
		if az < 0.0:
			az += 360.0
		var mp := Vector2(cx + r_f * cos(deg2rad(az)), cy + r_f * sin(deg2rad(az)))
		blinking = _draw_fissure_marker(mp, int(leak_state), is_live) or blinking

	var font = get_font("font")
	if font != null:
		draw_string(font, Vector2(cx - DOME_R * PLANTA_S - 26, PLANTA_CY + DOME_R * PLANTA_S + 30), "PLANTA", COLOR_TEXT)
	return blinking


# Punto de planta para coordenadas de mundo (x, z).
func _planta_pt(x_m: float, z_m: float) -> Vector2:
	return Vector2(CONTENT_LEFT + CONTENT_WIDTH * 0.5 + x_m * PLANTA_S, PLANTA_CY + z_m * PLANTA_S)


# Nivel del tanque de una rama, para que una columna sin refrigerante se lea seca aunque
# sus valvulas esten abiertas. Sin tanques en escena (tests, CoolantLab) asume lleno.
func _tank_level(side: String) -> float:
	var tanks: Array = get_tree().get_nodes_in_group("coolant_source")
	var fallback := -1.0
	for tank in tanks:
		if not is_instance_valid(tank) or not ("tank_level" in tank):
			continue
		var level: float = clamp(float(tank.get("tank_level")), 0.0, 1.0)
		var is_east: bool = "east" in tank.name.to_lower()
		if (side == "east") == is_east:
			return level
		if fallback < 0.0:
			fallback = level
	return fallback if fallback >= 0.0 else 1.0


# Mismo modelo que CoolantFlowAdapter.compute_flow(): la valvula del piso i corta el tramo
# que sube del piso i al i+1, la fisura de un tramo consume su caudal, y el medio toro del
# piso i+1 es un RAMAL alimentado por lo que sale de ese tramo. Las valvulas llegan como
# flags open/closed (así viajan en el modelo): sin flag asume abierta, igual que una
# valvula ausente en el grupo no cortaba nada.
func _solve_column_flow(valve_open: Array, trunk_states: Array, ring_states: Array, tank_level: float) -> Dictionary:
	var trunk := []
	var ring := []
	for _i in range(NUM_FLOORS):
		ring.append(0.0)
	var carrying: float = clamp(tank_level, 0.0, 1.0)
	for i in range(NUM_FLOORS - 1):
		var open: bool = bool(valve_open[i]) if i < valve_open.size() else true
		if not open:
			carrying = 0.0
		var t_state: int = int(trunk_states[i]) if i < trunk_states.size() else CoolantLeak.State.HEALTHY
		carrying = carrying * (1.0 - _leak_loss(t_state))
		trunk.append(carrying)
		var r_state: int = int(ring_states[i + 1]) if i + 1 < ring_states.size() else CoolantLeak.State.HEALTHY
		ring[i + 1] = carrying * (1.0 - _leak_loss(r_state))
	return {"trunk": trunk, "ring": ring}


func _leak_loss(state: int) -> float:
	if state == CoolantLeak.State.LEAKING:
		return 1.0
	return 0.0


# Trazo de un tramo: base opaca con el color de su estado, y encima el refrigerante que
# realmente circula. Una fisura activa pulsa entre su color y blanco.
func _draw_pipe(from: Vector2, to: Vector2, state: int, flow: float, is_live: bool, width: float) -> void:
	var base_col: Color = _get_pipe_color(state, is_live) if is_live else COLOR_OFFLINE_PIPE
	if is_live and _is_compromised(state):
		base_col = base_col.linear_interpolate(Color(1, 1, 1, 1), _blink_pulse() * 0.55)
	elif is_live and flow <= 0.001:
		base_col = COLOR_DRY
	draw_line(from, to, base_col, width, true)
	if is_live and flow > 0.001:
		var flow_col := COLOR_FLOW
		flow_col.a = 0.25 + 0.6 * flow
		draw_line(from, to, flow_col, width * (0.3 + 0.35 * flow), true)


func _draw_fissure_marker(pos: Vector2, state: int, is_live: bool) -> bool:
	if not is_live or not _is_compromised(state):
		return false
	var pulse: float = _blink_pulse()
	var col: Color = COLOR_PIPE_LEAKING if state == CoolantLeak.State.LEAKING else COLOR_PIPE_WARNING
	col.a = 0.35 + 0.65 * pulse
	draw_circle(pos, 4.0 + 3.0 * pulse, col)
	return true


func _is_compromised(state: int) -> bool:
	return state == CoolantLeak.State.LEAKING or state == CoolantLeak.State.WARNING


func _blink_pulse() -> float:
	return 0.5 + 0.5 * sin(_blink_phase * TAU * BLINK_HZ)


# El parpadeo es lo unico que necesita redibujos periodicos: se enciende solo mientras hay
# una fisura viva y se apaga en cuanto se sella, para que el Viewport vuelva a su reposo.
func _set_blinking(active: bool) -> void:
	if _blink_on == active:
		return
	_blink_on = active
	set_process(active)
	if not active:
		_blink_phase = 0.0
		_blink_accum = 0.0


func _process(delta: float) -> void:
	_blink_phase += delta
	_blink_accum += delta
	if _blink_accum < BLINK_REDRAW_INTERVAL:
		return
	_blink_accum = 0.0
	update()
	_request_redraw()


func _map_valves_to_layout(valves: Array) -> Dictionary:
	var west_valves := []
	var east_valves := []
	var interlink_valve = null

	var sorted_valves := valves.duplicate()
	sorted_valves.sort_custom(self, "_sort_by_floor_name")

	var unclassified := []

	for valve in sorted_valves:
		if not is_instance_valid(valve):
			continue
		var v_name: String = valve.name.to_lower()
		var p_name: String = _floor_label(valve).to_lower()

		if "interlink" in v_name or "interlink" in p_name:
			if interlink_valve == null:
				interlink_valve = valve
		elif "west" in v_name or "west" in p_name:
			west_valves.append(valve)
		elif "east" in v_name or "east" in p_name:
			east_valves.append(valve)
		else:
			unclassified.append(valve)

	# Distribute unclassified valves if explicit West/East names were not present
	for valve in unclassified:
		if west_valves.size() < NUM_FLOORS:
			west_valves.append(valve)
		elif east_valves.size() < NUM_FLOORS:
			east_valves.append(valve)
		elif interlink_valve == null:
			interlink_valve = valve

	return {
		"west": west_valves,
		"east": east_valves,
		"interlink": interlink_valve
	}


func _map_fissures_to_segments(patch_points: Array) -> Dictionary:
	# Dos familias de fisura por rama: las del TRONCO (Leak<Lado>Floor<N>, entrada del tramo
	# que sube del piso N al N+1) y las del MEDIO TORO de cada piso (Leak<Lado>Ring<N>).
	# Antes ambas caian al mismo array y, peor, _extract_floor_index() no reconocia "ring",
	# asi que TODAS las fisuras de anillo se pintaban en el piso 0.
	var west_states := []
	var east_states := []
	var west_rings := []
	var east_rings := []
	for _i in range(NUM_FLOORS - 1):
		west_states.append(CoolantLeak.State.HEALTHY)
		east_states.append(CoolantLeak.State.HEALTHY)
	for _i in range(NUM_FLOORS):
		west_rings.append(CoolantLeak.State.HEALTHY)
		east_rings.append(CoolantLeak.State.HEALTHY)
	var interlink_state = CoolantLeak.State.HEALTHY

	for patch_point in patch_points:
		if not is_instance_valid(patch_point):
			continue

		var effective_state: int = _effective_patch_state(patch_point)

		var label_str: String = _floor_label(patch_point).to_lower() + " " + patch_point.name.to_lower()
		var floor_idx: int = _extract_floor_index(label_str)
		var is_ring: bool = "ring" in label_str

		if "interlink" in label_str:
			interlink_state = _more_severe_state(int(interlink_state), int(effective_state))
			continue

		var is_east: bool = "east" in label_str
		if is_ring:
			# El anillo del piso 0 no existe (el primer medio toro esta bajo el piso 1).
			var ring_idx: int = int(clamp(floor_idx, 1, NUM_FLOORS - 1))
			var rings: Array = east_rings if is_east else west_rings
			rings[ring_idx] = _more_severe_state(int(rings[ring_idx]), int(effective_state))
		else:
			var seg_idx: int = int(clamp(floor_idx, 0, NUM_FLOORS - 2))
			var states: Array = east_states if is_east else west_states
			states[seg_idx] = _more_severe_state(int(states[seg_idx]), int(effective_state))

	return {
		"west": west_states,
		"east": east_states,
		"west_rings": west_rings,
		"east_rings": east_rings,
		"interlink": interlink_state
	}


# Reconoce tanto "floor<N>"/"piso<N>" (tronco) como "ring<N>" (medio toro): sin la variante
# ring, cada fisura de anillo devolvia 0 y se dibujaba en la planta baja.
func _extract_floor_index(text: String) -> int:
	for i in range(NUM_FLOORS):
		var n := str(i)
		for prefix in ["floor_", "floor", "piso_", "piso", "ring_", "ring"]:
			if (prefix + n) in text:
				return i
	return 0


func _more_severe_state(state_a: int, state_b: int) -> int:
	var priority := {
		CoolantLeak.State.LEAKING: 4,
		CoolantLeak.State.WARNING: 3,
		CoolantLeak.State.DEPRESSURIZED: 2,
		CoolantLeak.State.HEALTHY: 1,
		CoolantLeak.State.SEALED: 0
	}
	var prio_a = priority.get(state_a, 0)
	var prio_b = priority.get(state_b, 0)
	if int(prio_b) > int(prio_a):
		return state_b
	return state_a


func _get_pipe_color(leak_state: int, is_live: bool) -> Color:
	if not is_live:
		return COLOR_OFFLINE_PIPE

	match leak_state:
		CoolantLeak.State.LEAKING:
			return COLOR_PIPE_LEAKING
		CoolantLeak.State.WARNING:
			return COLOR_PIPE_WARNING
		CoolantLeak.State.DEPRESSURIZED:
			return COLOR_PIPE_DEPRESSURIZED
		_:
			return COLOR_PIPE_HEALTHY


func _valve_color(is_open: bool, is_live: bool) -> Color:
	if not is_live:
		return COLOR_OFFLINE_VALVE
	return COLOR_VALVE_OPEN if is_open else COLOR_VALVE_CLOSED


func _sort_by_floor_name(a: Node, b: Node) -> bool:
	return _floor_label(a) < _floor_label(b)


func _floor_label(node: Node) -> String:
	var parent: Node = node.get_parent()
	if parent != null and parent.name.begins_with("Floor_"):
		return parent.name
	return node.name


func _request_redraw() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()
