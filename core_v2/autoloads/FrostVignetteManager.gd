extends Node

# FD-051: registra la viñeta de frío en el OverlayUIManager y la ata al traje del jugador.
#
# Solo existe mientras hay un FireSystem en la escena. Es capa visual: si falla, la amenaza
# sigue funcionando idéntica.

const FrostVignetteScene = preload("res://core_v2/ui/overlay/FrostVignette.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"
const OVERLAY_SLOT := "Passive"
const FROST_PROXIMITY_RANGE := 10.0

var _overlay: Node = null
var _suit: Node = null
var _ice_level: Node = null
var _player: Spatial = null
var _warned_unavailable := false

func _ready() -> void:
	var _err = get_tree().connect("node_added", self, "_on_node_added")
	call_deferred("_try_bind")

func _process(_delta: float) -> void:
	# is_enabled() solo se consulta al enlazar, asi que si el overlay ya estaba montado
	# cuando arranca el replay habria seguido dibujandose. Se comprueba tambien aca.
	if not is_enabled():
		_remove_overlay()
		return
	if not is_instance_valid(_ice_level):
		var systems: Array = get_tree().get_nodes_in_group("ice_level") if get_tree() else []
		if systems.empty():
			_remove_overlay()
			return
		_try_bind()
	if not is_instance_valid(_overlay):
		_try_bind()
	if not is_instance_valid(_overlay) or not is_instance_valid(_ice_level):
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_player) or not _overlay.has_method("set_hazard_proximity"):
		return
	var distance_above_ice: float = _player.global_transform.origin.y - float(_ice_level.ice_height)
	var proximity := 1.0 - clamp(distance_above_ice / FROST_PROXIMITY_RANGE, 0.0, 1.0)
	_overlay.set_hazard_proximity(proximity)
	if _overlay.has_method("set_damage_direction"):
		_overlay.set_damage_direction(Vector2(0.0, 1.0), 0.9)

func is_enabled() -> bool:
	if OS.has_feature("Server"):
		return false
	# Un replay coloca al jugador con los transforms grabados, pero el nivel de hielo
	# arranca de cero y sube a su propio ritmo, asi que la altura del hielo no corresponde
	# a la que habia cuando se grabo. La comparacion "jugador por debajo de la linea" da
	# falsos positivos y aparece la vineta de dano por frio sin que el jugador este en
	# peligro. Mientras se reproduce, la vineta no tiene sentido.
	var sm := get_node_or_null("/root/SessionManager")
	if sm != null and bool(sm.get("is_replaying")):
		return false
	var env := OS.get_environment("ODISEA_FROST_VIGNETTE").strip_edges().to_lower()
	if env in ["0", "false", "no", "off"]:
		return false
	return true

func _on_node_added(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group("ice_level") or node.is_in_group("player"):
		call_deferred("_try_bind")

func _try_bind() -> void:
	if not is_enabled() or not get_tree():
		return

	var systems: Array = get_tree().get_nodes_in_group("ice_level")
	if systems.empty():
		_remove_overlay()
		return
	_ice_level = systems[0]
	_player = _find_player()

	if not _ensure_overlay():
		return

	var suit := _find_player_suit()
	if is_instance_valid(suit) and suit != _suit:
		bind_suit(suit)

	if is_instance_valid(_ice_level) and not _ice_level.is_connected("frost_contact", self, "_on_frost_contact"):
		var _err = _ice_level.connect("frost_contact", self, "_on_frost_contact")

# Vía explícita de rebind, usada por PlayerControllerV2 en cada (re)spawn: la viñeta vive
# en OverlayUIManager y sobrevive a la reinstanciación del Pilot, así que debe re-atarse al
# traje NUEVO y limpiar cualquier pulso/alpha residual del traje anterior.
func bind_suit(suit: Node) -> void:
	if not is_instance_valid(suit):
		return
	if not get_tree() or get_tree().get_nodes_in_group("ice_level").empty():
		_remove_overlay()
		return
	_suit = suit
	if not _ensure_overlay():
		return
	if _overlay.has_method("bind_suit"):
		_overlay.bind_suit(suit)
	if _overlay.has_method("set_damage_direction"):
		# El nivel mortal asciende desde debajo de Elías: concentra la escarcha abajo.
		_overlay.set_damage_direction(Vector2(0.0, 1.0), 0.9)

func _on_frost_contact(body: Node, _dps: float, _in_core: bool) -> void:
	if not is_instance_valid(_overlay) or not is_instance_valid(_suit):
		return
	# Solo reacciona al frío sobre el jugador que porta el traje enlazado.
	if not body.is_in_group("player"):
		return
	if _overlay.has_method("set_hazard_active"):
		_overlay.set_hazard_active(true)

func _find_player_suit() -> Node:
	var player := _find_player()
	if is_instance_valid(player):
		var suit = player.get_node_or_null("Logic/SuitThermalResistance")
		if is_instance_valid(suit):
			return suit
		if "thermal_resistance" in player and is_instance_valid(player.thermal_resistance):
			return player.thermal_resistance
	return null

func _find_player() -> Spatial:
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player is Spatial:
			return player
	return null

func _ensure_overlay() -> bool:
	if is_instance_valid(_overlay):
		return true
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("ensure_overlay"):
		_overlay = overlay_ui.ensure_overlay("FrostVignette", FrostVignetteScene, OVERLAY_SLOT)
	if not is_instance_valid(_overlay) and not _warned_unavailable:
		_warned_unavailable = true
		push_warning("[FrostVignetteManager] OverlayUIManager no disponible; sin viñeta de frío.")
	return is_instance_valid(_overlay)

func _remove_overlay() -> void:
	_ice_level = null
	_overlay = null
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("remove_overlay"):
		overlay_ui.remove_overlay("FrostVignette", OVERLAY_SLOT)
