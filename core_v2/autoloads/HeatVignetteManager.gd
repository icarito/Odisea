extends Node

# FD-051: registra la viñeta de calor en el OverlayUIManager y la ata al traje del jugador.
#
# Solo existe mientras hay un FireSystem en la escena. Es capa visual: si falla, la amenaza
# sigue funcionando idéntica.

const HeatVignetteScene = preload("res://core_v2/ui/overlay/HeatVignette.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"
const OVERLAY_SLOT := "Passive"
const HEAT_DISTORTION_RANGE := 10.0

var _overlay: Node = null
var _suit: Node = null
var _fire_system: Node = null
var _player: Spatial = null
var _warned_unavailable := false

func _ready() -> void:
	var _err = get_tree().connect("node_added", self, "_on_node_added")
	call_deferred("_try_bind")

func _process(_delta: float) -> void:
	if not is_instance_valid(_overlay) or not is_instance_valid(_fire_system):
		return
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_player) or not _overlay.has_method("set_heat_proximity"):
		return
	var distance_above_fire: float = _player.global_transform.origin.y - float(_fire_system.fire_height)
	var proximity := 1.0 - clamp(distance_above_fire / HEAT_DISTORTION_RANGE, 0.0, 1.0)
	_overlay.set_heat_proximity(proximity)

func is_enabled() -> bool:
	if OS.has_feature("Server"):
		return false
	var env := OS.get_environment("ODISEA_HEAT_VIGNETTE").strip_edges().to_lower()
	if env in ["0", "false", "no", "off"]:
		return false
	return true

func _on_node_added(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group("fire_system") or node.is_in_group("player"):
		call_deferred("_try_bind")

func _try_bind() -> void:
	if not is_enabled() or not get_tree():
		return

	var systems: Array = get_tree().get_nodes_in_group("fire_system")
	if systems.empty():
		# Sin fuego en escena no hace falta la viñeta.
		return
	_fire_system = systems[0]
	_player = _find_player()

	if not _ensure_overlay():
		return

	var suit := _find_player_suit()
	if is_instance_valid(suit) and suit != _suit:
		bind_suit(suit)

	if is_instance_valid(_fire_system) and not _fire_system.is_connected("heat_contact", self, "_on_heat_contact"):
		var _err = _fire_system.connect("heat_contact", self, "_on_heat_contact")

# Vía explícita de rebind, usada por PlayerControllerV2 en cada (re)spawn: la viñeta vive
# en OverlayUIManager y sobrevive a la reinstanciación del Pilot, así que debe re-atarse al
# traje NUEVO y limpiar cualquier pulso/alpha residual del traje anterior.
func bind_suit(suit: Node) -> void:
	if not is_instance_valid(suit):
		return
	_suit = suit
	if not _ensure_overlay():
		return
	if _overlay.has_method("bind_suit"):
		_overlay.bind_suit(suit)

func _on_heat_contact(body: Node, _dps: float, _in_core: bool) -> void:
	if not is_instance_valid(_overlay) or not is_instance_valid(_suit):
		return
	# Solo reacciona al calor sobre el jugador que porta el traje enlazado.
	if not body.is_in_group("player"):
		return
	if _overlay.has_method("set_heat_active"):
		_overlay.set_heat_active(true)

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
		_overlay = overlay_ui.ensure_overlay("HeatVignette", HeatVignetteScene, OVERLAY_SLOT)
	if not is_instance_valid(_overlay) and not _warned_unavailable:
		_warned_unavailable = true
		push_warning("[HeatVignetteManager] OverlayUIManager no disponible; sin viñeta de calor.")
	return is_instance_valid(_overlay)
