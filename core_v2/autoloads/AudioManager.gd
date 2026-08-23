extends Node

# AudioManager.gd
# Manages global audio state, specifically BGM cross-fading and zone management.
# BGM zones are prioritized by volume (smaller volume = higher priority).
# INTEGRATION: Supports 'Godot-Mixing-Desk' plugin if available (MixingDeskMusic node).

var _bgm_player_1: AudioStreamPlayer
var _bgm_player_2: AudioStreamPlayer
var _active_player: AudioStreamPlayer = null
var _tween: Tween

var _active_zones := []
var _mdm_instance: Node = null # MixingDeskMusic instance
var _mds_instance: Node = null # MixingDeskSound instance (if used globally)
var _music_paused_by_focus := false
var _music_paused_by_menu := false

# Cancion pedida a mano (crossfade_to_song). Mientras este fijada MANDA sobre las zonas:
# _update_bgm() no puede volver a derivar la BGM del BGMZoneV2 que contenga al jugador.
# Sin esto cualquier evento de zona (entrar al ascensor, cambiar de piso) devolvia la
# musica de la sala encima de la que habia pedido el guion, aunque siguiera sonando.
var _song_override := ""
var _song_override_volume_db := 0.0
var _active_zone: Node = null
var _zone_playback_positions := {}
var _headless_audio_muted := false
var _focus_audio_muted := false
var _level_audio_muted := false
var _cinematic_listener: Listener = null
var _cinematic_listener_engaged := false
var _mobile_web_audio_guard_enabled := false

export(bool) var follow_active_camera_for_spatial_sfx := true
export(bool) var follow_active_camera_only_during_cinematics := true

const HEADLESS_MUTE_ENV := "ODISEA_MUTE_AUDIO_HEADLESS"
const FORCE_MUTE_ENV := "ODISEA_FORCE_MUTE_AUDIO"
const MOBILE_WEB_MASTER_GAIN_DB := -6.0

func _ready():
	_configure_runtime_audio_safeguards()
	_headless_audio_muted = _should_mute_audio_for_runtime()
	_apply_headless_audio_mute(_headless_audio_muted)

	_bgm_player_1 = AudioStreamPlayer.new()
	_bgm_player_1.bus = "Music"
	_bgm_player_1.name = "BGMPlayer1"
	add_child(_bgm_player_1)

	_bgm_player_2 = AudioStreamPlayer.new()
	_bgm_player_2.bus = "Music"
	_bgm_player_2.name = "BGMPlayer2"
	add_child(_bgm_player_2)

	_tween = Tween.new()
	_tween.name = "FadeTween"
	add_child(_tween)

	# Try to find Mixing Desk Music in the scene tree (usually autoload or root child)
	# Since autoloads are children of root, we can check siblings or children of root
	call_deferred("_find_mixing_desk")

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		_set_focus_audio_muted(true)
		_set_music_focus_paused(true)
	elif what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_set_focus_audio_muted(false)
		_set_music_focus_paused(false)

func _exit_tree() -> void:
	var tree = get_tree()
	if tree and tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.disconnect("node_added", self, "_on_tree_node_added")

func _configure_runtime_audio_safeguards() -> void:
	_mobile_web_audio_guard_enabled = _should_enable_mobile_web_audio_guard(OS.get_name(), OS.has_touchscreen_ui_hint())
	if not _mobile_web_audio_guard_enabled:
		return

	var master_idx = _get_master_bus_index()
	_ensure_master_limiter(master_idx)
	var current_master_db = AudioServer.get_bus_volume_db(master_idx)
	if current_master_db > MOBILE_WEB_MASTER_GAIN_DB:
		AudioServer.set_bus_volume_db(master_idx, MOBILE_WEB_MASTER_GAIN_DB)

	var tree = get_tree()
	if tree and tree.root:
		_apply_mobile_web_audio_policy_to_subtree(tree.root)
	if tree and not tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.connect("node_added", self, "_on_tree_node_added")

	print("[AudioManager] Mobile web audio safeguards enabled (master %.1fdB, limiter, out-of-range pause)" % MOBILE_WEB_MASTER_GAIN_DB)

func _should_enable_mobile_web_audio_guard(os_name: String, has_touchscreen_hint: bool) -> bool:
	return os_name == "HTML5" and has_touchscreen_hint

func _get_master_bus_index() -> int:
	var master_idx = AudioServer.get_bus_index("Master")
	return master_idx if master_idx >= 0 else 0

func _ensure_master_limiter(bus_idx: int) -> void:
	if bus_idx < 0:
		return
	for effect_idx in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, effect_idx)
		if effect and effect.get_class() == "AudioEffectLimiter":
			return
	AudioServer.add_bus_effect(bus_idx, AudioEffectLimiter.new(), 0)

func _on_tree_node_added(node: Node) -> void:
	if not _mobile_web_audio_guard_enabled:
		return
	_apply_mobile_web_audio_policy_to_subtree(node)

func _apply_mobile_web_audio_policy_to_subtree(node: Node) -> void:
	if not node:
		return
	if node is AudioStreamPlayer3D:
		_configure_mobile_web_3d_player(node as AudioStreamPlayer3D)
	for child in node.get_children():
		if child is Node:
			_apply_mobile_web_audio_policy_to_subtree(child)

func _configure_mobile_web_3d_player(player: AudioStreamPlayer3D) -> void:
	if not player:
		return
	if player.max_distance > 0.0 and player.out_of_range_mode != AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE:
		player.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE

func _should_mute_audio_for_runtime() -> bool:
	var force_mute = OS.get_environment(FORCE_MUTE_ENV).to_lower().strip_edges()
	if force_mute in ["1", "true", "yes", "on"]:
		return true
	if force_mute in ["0", "false", "no", "off"]:
		return false

	var mute_headless = OS.get_environment(HEADLESS_MUTE_ENV).to_lower().strip_edges()
	if mute_headless in ["0", "false", "no", "off"]:
		return false

	if _cmdline_has_any(["--no-window", "--headless"]):
		return true

	return OS.get_name() == "Server" or OS.has_feature("Server") or OS.has_feature("server")

func _cmdline_has_any(flags: Array) -> bool:
	var args = OS.get_cmdline_args()
	for arg in args:
		if str(arg) in flags:
			return true
	return _proc_cmdline_has_any(flags)

func _proc_cmdline_has_any(flags: Array) -> bool:
	if not OS.get_name() in ["X11", "Linux", "Server"]:
		return false
	var cmdline = _read_process_cmdline()
	if cmdline == "":
		return false
	for flag in flags:
		if String(flag) in cmdline:
			return true
	return false

func _read_process_cmdline() -> String:
	var pid = OS.get_process_id()
	var proc_path = "/proc/%d/cmdline" % pid
	var file = File.new()
	if not file.file_exists(proc_path):
		return ""
	if file.open(proc_path, File.READ) != OK:
		return ""
	var raw := ""
	var guard := 0
	while not file.eof_reached() and guard < 32768:
		var b = int(file.get_8())
		if b == 0:
			raw += " "
		else:
			raw += char(b)
		guard += 1
	file.close()
	return raw

func _apply_headless_audio_mute(muted: bool) -> void:
	_headless_audio_muted = muted
	_apply_master_audio_mute_state()
	if muted:
		print("[AudioManager] Master bus muted for headless/runtime policy")

func _set_focus_audio_muted(muted: bool) -> void:
	if _focus_audio_muted == muted:
		return
	_focus_audio_muted = muted
	_apply_master_audio_mute_state()

# El nivel sigue corriendo detrás de la pantalla de muerte (el hielo sube, el fuego
# crepita, la BGM avanza), pero no debe oírse: morir corta el audio del mundo. Lo maneja
# ScreenEffectsManager junto con el cover, no cada sistema por su cuenta.
func set_level_audio_muted(muted: bool) -> void:
	if _level_audio_muted == muted:
		return
	_level_audio_muted = muted
	_apply_master_audio_mute_state()

func is_level_audio_muted() -> bool:
	return _level_audio_muted

func _apply_master_audio_mute_state() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		master_idx = 0
	AudioServer.set_bus_mute(master_idx, _headless_audio_muted or _focus_audio_muted or _level_audio_muted)

func _find_mixing_desk():
	var root = get_tree().get_root()
	# Strategy 1: Look for node named "MixingDeskMusic"
	_mdm_instance = root.find_node("MixingDeskMusic", true, false)
	# Strategy 2: Look for MDS
	_mds_instance = root.find_node("MixingDeskSound", true, false)

func _physics_process(_delta):
	_update_spatial_listener_for_cinematics()

func register_zone(zone):
	if not _active_zones.has(zone):
		_active_zones.append(zone)
		_update_bgm()

func unregister_zone(zone):
	if _active_zones.has(zone):
		_active_zones.erase(zone)
		_update_bgm()

func is_music_paused() -> bool:
	return _music_paused_by_focus or _music_paused_by_menu

func _update_bgm():
	if is_music_paused():
		return

	# Hay una cancion fijada a mano: las zonas no opinan hasta que se la suelte con
	# clear_song_override().
	if _song_override != "":
		return

	# Zona vacía transitoria (p.ej. la cabina del ascensor mientras sube y sale de los
	# límites del BGMZoneV2 de la sala): no hay zona activa, pero eso no es una orden
	# de silenciar. Solo una zona con contenido propio puede cortar la música; que no
	# haya ninguna zona registrada deja sonando lo que ya sonaba.
	if _active_zones.empty():
		return

	# Sort zones by priority (volume)
	_active_zones.sort_custom(self, "_sort_zones")

	var top = _active_zones[0]
	var top_zone = top
	var target_stream = top.bgm_stream
	var target_song = top.song_name
	var target_pitch = top.pitch_scale
	var target_volume = top.volume_db
	var fade_time = top.fade_time

	if top_zone != _active_zone:
		_save_active_zone_playback()

	# Priority 1: Use Mixing Desk if available and song name is provided
	if _mdm_instance and target_song != "":
		# Assuming MDM API: play(song_name) or queue_bar_transition(song_name)
		if _mdm_instance.has_method("play"):
			# If we are already playing this song, do nothing? MDM usually handles this.
			# But we might want to check current song state if MDM exposes it.
			# For now, just call play(), MDM should be smart enough or we rely on it.
			print("[AudioManager] Delegating BGM to MixingDeskMusic: ", target_song)
			_mdm_instance.call("play", target_song)

			# Ensure our internal players are silent
			if _active_player and _active_player.playing:
				_active_player.stop()
		_active_zone = top_zone
		return

	# Priority 2: Use internal AudioStreamPlayers
	_crossfade_to(target_stream, target_pitch, target_volume, fade_time, top_zone)

func _sort_zones(a, b):
	if a.has_method("get_volume") and b.has_method("get_volume"):
		return a.get_volume() < b.get_volume()
	# Fallback if get_volume missing (shouldn't happen with V2)
	return false

func _crossfade_to(stream, pitch, vol, time, zone = null):
	if is_music_paused():
		return

	# If MDM was playing, stop it?
	if _mdm_instance and _mdm_instance.has_method("stop"):
		_mdm_instance.call("stop")

	# If current stream is same, update properties
	if _active_player and _active_player.stream == stream:
		if _active_player.playing:
			if zone != null and zone != _active_zone:
				_seek_player_to_zone_position(_active_player, zone)
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, vol, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_property(_active_player, "pitch_scale", _active_player.pitch_scale, pitch, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.start()
			_active_zone = zone
			return

	var next_player = _bgm_player_1
	if _active_player == _bgm_player_1:
		next_player = _bgm_player_2

	if stream:
		next_player.stream = stream
		next_player.pitch_scale = pitch
		next_player.volume_db = -80 # Start silent
		next_player.play()
		_seek_player_to_zone_position(next_player, zone)

		_tween.stop_all()
		_tween.interpolate_property(next_player, "volume_db", -80, vol, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)

		if _active_player and _active_player.playing:
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, -80, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_callback(_active_player, time, "stop")

		_tween.start()
		_active_player = next_player
		_active_zone = zone
	else:
		# Fade out active if no new stream
		if _active_player and _active_player.playing:
			_tween.stop_all()
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, -80, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_callback(_active_player, time, "stop")
			_tween.start()
			_active_player = null
		_active_zone = null
	
func reset():
	_save_active_zone_playback()
	_song_override = ""
	_song_override_volume_db = 0.0
	_active_zones.clear()
	_active_zone = null
	_zone_playback_positions.clear()
	if _mdm_instance and _mdm_instance.has_method("stop"):
		_mdm_instance.call("stop")
	
	if _active_player:
		_active_player.stop()
		_active_player = null
	
	if _bgm_player_1: _bgm_player_1.stop()
	if _bgm_player_2: _bgm_player_2.stop()
	
	if _tween:
		_tween.stop_all()
	_restore_default_spatial_listener()


# Reinicia la BGM de las zonas vigentes desde el compás inicial sin perder qué zona
# contiene al jugador. El respawn no reinstancia BGMZoneV2, por eso reset() no sirve:
# borraría sus zonas activas y dejaría la sala sin música hasta otra entrada física.
func restart_bgm_from_active_zones() -> void:
	_zone_playback_positions.clear()
	_active_zone = null
	if _tween:
		_tween.stop_all()
	if _mdm_instance and _mdm_instance.has_method("stop"):
		_mdm_instance.call("stop")
	if _active_player:
		_active_player.stop()
		_active_player = null
	if _bgm_player_1:
		_bgm_player_1.stop()
	if _bgm_player_2:
		_bgm_player_2.stop()
	# El respawn arranca limpio con la musica de la zona. Si el motivo del override sigue
	# vigente (una fuga que el checkpoint restaura abierta), lo vuelve a fijar quien lo
	# decide — ColdRuptureDirector al restaurar su snapshot — no este metodo: reinstalarlo
	# a ciegas aca dejaba el latido sonando en respawns donde ya no habia ninguna fuga.
	_song_override = ""
	_song_override_volume_db = 0.0
	_update_bgm()

func fade_out_current_bgm(duration: float = 0.35) -> void:
	var time = max(0.0, duration)
	if _mdm_instance and _mdm_instance.has_method("stop") and _active_player == null:
		# Fallback when MDM is controlling music and no internal stream is active.
		_mdm_instance.call("stop")
		return
	if not _active_player or not _active_player.playing:
		return
	if time <= 0.0:
		_active_player.stop()
		return
	_tween.stop_all()
	_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, -80.0, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	_tween.interpolate_callback(_active_player, time, "stop")
	_tween.start()

func refresh_bgm_from_zones(_fade_in_time: float = 0.35) -> void:
	# Zone update already carries fade_time and crossfade logic.
	_update_bgm()

func crossfade_to_song(song_name: String, fade_time: float = 1.0, volume_db: float = 0.0) -> void:
	if song_name == "":
		_song_override = ""
		_crossfade_to(null, 1.0, volume_db, fade_time)
		return

	var path = "res://assets/music/" + song_name
	var file = File.new()
	if not file.file_exists(path) and not path.ends_with(".mp3") and not path.ends_with(".ogg") and not path.ends_with(".wav"):
		path += ".mp3"

	if file.file_exists(path):
		var stream = load(path)
		if stream is AudioStream:
			_song_override = song_name
			_song_override_volume_db = volume_db
			_crossfade_to(stream, 1.0, volume_db, fade_time)
		else:
			printerr("[AudioManager] Failed to load AudioStream from: ", path)
	else:
		printerr("[AudioManager] Music file not found: ", path)

func set_music_paused_by_menu(paused: bool) -> void:
	if _music_paused_by_menu == paused:
		return

	var was_paused = is_music_paused()
	_music_paused_by_menu = paused
	var now_paused = is_music_paused()

	if now_paused and not was_paused:
		_pause_internal_bgm_players()
		_pause_mdm_music()
	elif was_paused and not now_paused:
		_resume_internal_bgm_players()
		_resume_mdm_music()
		_update_bgm()

# Suelta la cancion fijada y devuelve la BGM a las zonas activas. Lo llama quien la fijo
# cuando su motivo termino (en Dome_Intro: cuando ya no queda ninguna fuga viva).
func clear_song_override(fade_time: float = 1.0) -> void:
	if _song_override == "":
		return
	_song_override = ""
	_song_override_volume_db = 0.0
	if _active_zones.empty():
		# Sin zonas de las que derivar, apagar lo que quedo sonando por el override.
		_crossfade_to(null, 1.0, 0.0, fade_time)
		return
	_update_bgm()


func get_song_override() -> String:
	return _song_override


func _set_music_focus_paused(paused: bool) -> void:
	if _music_paused_by_focus == paused:
		return

	var was_paused = is_music_paused()
	_music_paused_by_focus = paused
	var now_paused = is_music_paused()

	if now_paused and not was_paused:
		_pause_internal_bgm_players()
		_pause_mdm_music()
	elif was_paused and not now_paused:
		_resume_internal_bgm_players()
		_resume_mdm_music()
		# _update_bgm() vuelve a derivar la BGM de las zonas activas, y eso PISA lo que
		# estaba sonando: una cancion puesta a mano con crossfade_to_song() (el latido de
		# la rotura, por ejemplo) no pertenece a ninguna zona, asi que al despausar o
		# recuperar el foco se volvia siempre a la cancion de la zona. Los players solo
		# quedaron en stream_paused: si alguno sigue sonando, no hay nada que re-derivar.
		if not _is_any_bgm_playing():
			_update_bgm()


func _is_any_bgm_playing() -> bool:
	if _mdm_instance != null and _mdm_instance.has_method("is_playing"):
		if bool(_mdm_instance.call("is_playing")):
			return true
	for player in [_bgm_player_1, _bgm_player_2]:
		if player != null and player.playing:
			return true
	return false

func _pause_internal_bgm_players() -> void:
	if _tween:
		_tween.stop_all()
	_save_active_zone_playback()
	for player in [_bgm_player_1, _bgm_player_2]:
		if not player or not player.playing:
			continue
		if player.has_method("set_stream_paused"):
			player.set_stream_paused(true)
		else:
			player.stop()

func _resume_internal_bgm_players() -> void:
	for player in [_bgm_player_1, _bgm_player_2]:
		if not player:
			continue
		if player.has_method("set_stream_paused"):
			player.set_stream_paused(false)

func _save_active_zone_playback() -> void:
	if not _active_zone or not _active_player or not _active_player.playing:
		return
	var key = _zone_playback_key(_active_zone)
	if key == "":
		return
	_zone_playback_positions[key] = _active_player.get_playback_position()

func _seek_player_to_zone_position(player: AudioStreamPlayer, zone: Node) -> void:
	if not player or not zone:
		return
	var key = _zone_playback_key(zone)
	if key == "" or not _zone_playback_positions.has(key):
		return
	var resume_pos = float(_zone_playback_positions[key])
	if resume_pos <= 0.0:
		return
	var stream_len = 0.0
	if player.stream and player.stream.has_method("get_length"):
		stream_len = float(player.stream.get_length())
	if stream_len > 0.0:
		resume_pos = fmod(resume_pos, max(0.01, stream_len - 0.01))
	player.seek(resume_pos)

func _zone_playback_key(zone: Node) -> String:
	if not zone:
		return ""
	if zone.is_inside_tree():
		return str(zone.get_path())
	return str(zone.name)

func _pause_mdm_music() -> void:
	if not _mdm_instance:
		return
	if _mdm_instance.has_method("pause"):
		_mdm_instance.call("pause")
	elif _mdm_instance.has_method("set_paused"):
		_mdm_instance.call("set_paused", true)
	elif _mdm_instance.has_method("stop"):
		_mdm_instance.call("stop")

func _resume_mdm_music() -> void:
	if not _mdm_instance:
		return
	if _mdm_instance.has_method("resume"):
		_mdm_instance.call("resume")
	elif _mdm_instance.has_method("set_paused"):
		_mdm_instance.call("set_paused", false)

# SFX Integration
func play_sound(sound_name: String, _pos: Vector3 = Vector3.ZERO):
	if _mds_instance and _mds_instance.has_method("play"):
		# MDS usually plays by container name
		# _pos is ignored unless we implement spatial MDS logic or the plugin supports it
		_mds_instance.call("play", sound_name)
	else:
		# Fallback: We can't play a 'named' sound without the plugin unless we have a dictionary of streams.
		# For now, SFXComponentV2 handles its own fallback if it has a stream.
		# This method is just for the name-based lookup.
		print("[AudioManager] Warning: Cannot play sound '%s' - MixingDeskSound not found." % sound_name)

func _update_spatial_listener_for_cinematics() -> void:
	if not follow_active_camera_for_spatial_sfx:
		_restore_default_spatial_listener()
		return

	var target_cam = _get_spatial_listener_target_camera()
	if target_cam and is_instance_valid(target_cam):
		_apply_cinematic_listener_to_camera(target_cam)
	else:
		_restore_default_spatial_listener()

func _get_spatial_listener_target_camera() -> Camera:
	var cm = get_node_or_null("/root/CinematicManager")
	if not cm or not is_instance_valid(cm):
		return null

	if follow_active_camera_only_during_cinematics:
		if not (cm.has_method("is_active") and cm.is_active()):
			return null

	if cm.has_method("get_active_camera"):
		var cam = cm.get_active_camera()
		if cam and is_instance_valid(cam):
			return cam
	return null

func _apply_cinematic_listener_to_camera(cam: Camera) -> void:
	if not _cinematic_listener or not is_instance_valid(_cinematic_listener):
		_cinematic_listener = Listener.new()
		_cinematic_listener.name = "CinematicAudioListener"
		add_child(_cinematic_listener)

	_cinematic_listener.global_transform = cam.global_transform
	_cinematic_listener.make_current()
	_cinematic_listener_engaged = true

func _restore_default_spatial_listener() -> void:
	if not _cinematic_listener_engaged:
		return

	if _cinematic_listener and is_instance_valid(_cinematic_listener):
		if _cinematic_listener.has_method("clear_current"):
			_cinematic_listener.clear_current()

	var player_listener = _find_player_listener()
	if player_listener and is_instance_valid(player_listener):
		player_listener.make_current()

	_cinematic_listener_engaged = false

func _find_player_listener() -> Listener:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		var l = p.get_node_or_null("AudioListener")
		if l and l is Listener:
			return l as Listener
	return null
