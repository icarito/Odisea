extends Node

const ScreenEffectsOverlayScene = preload("res://core_v2/ui/overlay/ScreenEffectsOverlay.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"

var _overlay: Node = null
var _warned_unavailable := false
var _script_cinematic_depth := 0
# La pausa del árbol es compartida (menú, InfoOverlay, notificaciones): solo la soltamos
# si fuimos nosotros los que la pusimos.
var _death_pause_owned := false

func show_script_cinematic_bars(immediate: bool = false) -> void:
	_script_cinematic_depth += 1
	_set_script_cinematic_visible(true, immediate)

func hide_script_cinematic_bars(immediate: bool = false) -> void:
	_script_cinematic_depth = int(max(0, _script_cinematic_depth - 1))
	_set_script_cinematic_visible(_script_cinematic_depth > 0, immediate)

func begin_death_cover(params: Dictionary = {}):
	if not _ensure_overlay():
		_warn_unavailable_once("begin_death_cover")
		return null
	_script_cinematic_depth = 0
	_set_level_audio_muted(true)
	_set_world_paused(true)
	if _overlay.has_method("set_cinematic_bars_enabled"):
		_overlay.set_cinematic_bars_enabled(false, true)
	if _overlay.has_method("begin_death_cover"):
		return _overlay.begin_death_cover(params)
	return null

func end_death_cover(params: Dictionary = {}):
	# Antes del _ensure_overlay: aunque el overlay ya no esté, el audio y la simulación
	# tienen que volver igual (si no, un respawn sin overlay deja el juego mudo y congelado).
	_set_level_audio_muted(false)
	_set_world_paused(false)
	if not _ensure_overlay():
		_warn_unavailable_once("end_death_cover")
		return null
	if _overlay.has_method("end_death_cover"):
		return _overlay.end_death_cover(params)
	return null

func wait_for_death_confirm(params: Dictionary = {}):
	if _should_skip_death_confirm(params):
		return null
	if not _ensure_overlay():
		_warn_unavailable_once("wait_for_death_confirm")
		return null
	if _overlay.has_method("wait_for_death_confirm"):
		return _overlay.wait_for_death_confirm(params)
	return null

func reset(immediate: bool = true) -> void:
	_script_cinematic_depth = 0
	_set_level_audio_muted(false)
	_set_world_paused(false)
	if not _ensure_overlay():
		return
	if _overlay.has_method("reset_effects"):
		_overlay.reset_effects(immediate)

func is_enabled() -> bool:
	var env = OS.get_environment("OYS_SCREEN_EFFECTS").strip_edges().to_lower()
	if env != "":
		if env in ["1", "true", "yes", "on"]:
			return true
		if env in ["0", "false", "no", "off"]:
			return false
	if OS.has_feature("Server"):
		return false
	return true

func _should_skip_death_confirm(params: Dictionary) -> bool:
	if bool(params.get("skip", false)):
		return true
	if OS.has_feature("Server"):
		return true
	if OS.get_environment("OYS_AUTO_RUN").strip_edges() != "":
		return true
	var session = get_node_or_null("/root/SessionManager")
	if not session:
		return false
	if bool(session.get("is_cli_mode")):
		return true
	if bool(session.get("is_recording")):
		return true
	if bool(session.get("is_replaying")):
		return true
	if bool(session.get("_is_waiting_for_respawn_validation")):
		return true
	return false

# El cover de muerte tapa la pantalla pero no el mundo: el nivel sigue simulando detrás.
# Mientras dure, el audio del nivel (hielo, fuego, ambiente, BGM) queda mudo.
func _set_level_audio_muted(muted: bool) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("set_level_audio_muted"):
		audio.set_level_audio_muted(muted)

# Morir congela el mundo: el hielo deja de subir, las partículas quedan quietas y nada
# puede seguir dañando mientras el jugador mira la pantalla de muerte. El overlay vive en
# OverlayUIManager (PAUSE_MODE_PROCESS), así que el fundido y la tecla de confirmación
# siguen funcionando con el árbol pausado.
func _set_world_paused(paused: bool) -> void:
	var tree = get_tree()
	if not tree:
		return
	if paused:
		# Si ya estaba pausado por otro (menú, InfoOverlay), no nos adueñamos de esa pausa.
		if _death_pause_owned or tree.paused:
			return
		_death_pause_owned = true
		tree.paused = true
	else:
		if not _death_pause_owned:
			return
		_death_pause_owned = false
		tree.paused = false
	# Los controles táctiles (CanvasLayer 10/100) tapan cualquier overlay y se comerían el
	# toque de "continuar"; su autoload está congelado en pausa, hay que avisarle a mano.
	var mobile = get_node_or_null("/root/MobileUIManager")
	if mobile and mobile.has_method("refresh_for_pause"):
		mobile.refresh_for_pause()

func _set_script_cinematic_visible(enabled: bool, immediate: bool) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("script_cinematic")
		return
	if _overlay.has_method("set_cinematic_bars_enabled"):
		_overlay.set_cinematic_bars_enabled(enabled, immediate)

func _ensure_overlay() -> bool:
	if not is_enabled():
		return false
	if is_instance_valid(_overlay):
		return true
	if not get_tree() or not is_instance_valid(get_tree().root):
		return false
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("ensure_overlay"):
		_overlay = overlay_ui.ensure_overlay("ScreenEffectsOverlay", ScreenEffectsOverlayScene, "Passive")
	else:
		_overlay = ScreenEffectsOverlayScene.instance()
		if is_instance_valid(_overlay):
			_overlay.name = "ScreenEffectsOverlay"
			get_tree().root.add_child(_overlay)
	return is_instance_valid(_overlay)

func _warn_unavailable_once(context: String) -> void:
	if _warned_unavailable:
		return
	_warned_unavailable = true
	push_warning("[ScreenEffectsManager] unavailable in '%s'. Screen effects disabled." % context)
