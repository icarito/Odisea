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

func _ready():
	_bgm_player_1 = AudioStreamPlayer.new()
	_bgm_player_1.bus = "Master"
	_bgm_player_1.name = "BGMPlayer1"
	add_child(_bgm_player_1)

	_bgm_player_2 = AudioStreamPlayer.new()
	_bgm_player_2.bus = "Master"
	_bgm_player_2.name = "BGMPlayer2"
	add_child(_bgm_player_2)

	_tween = Tween.new()
	_tween.name = "FadeTween"
	add_child(_tween)

	# Try to find Mixing Desk Music in the scene tree (usually autoload or root child)
	# Since autoloads are children of root, we can check siblings or children of root
	call_deferred("_find_mixing_desk")

func _find_mixing_desk():
	var root = get_tree().get_root()
	# Strategy 1: Look for node named "MixingDeskMusic"
	_mdm_instance = root.find_node("MixingDeskMusic", true, false)
	if _mdm_instance:
		print("[AudioManager] MixingDeskMusic found: ", _mdm_instance.name)
	else:
		print("[AudioManager] MixingDeskMusic NOT found. Using internal AudioStreamPlayers.")

	# Strategy 2: Look for MDS
	_mds_instance = root.find_node("MixingDeskSound", true, false)

func register_zone(zone):
	if not _active_zones.has(zone):
		_active_zones.append(zone)
		_update_bgm()

func unregister_zone(zone):
	if _active_zones.has(zone):
		_active_zones.erase(zone)
		_update_bgm()

func _update_bgm():
	# Sort zones by priority (volume)
	_active_zones.sort_custom(self, "_sort_zones")

	var target_stream = null
	var target_song = ""
	var target_pitch = 1.0
	var target_volume = 0.0
	var fade_time = 1.0

	if _active_zones.size() > 0:
		var top = _active_zones[0]
		target_stream = top.bgm_stream
		target_song = top.song_name
		target_pitch = top.pitch_scale
		target_volume = top.volume_db
		fade_time = top.fade_time

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
		return

	# Priority 2: Use internal AudioStreamPlayers
	_crossfade_to(target_stream, target_pitch, target_volume, fade_time)

func _sort_zones(a, b):
	if a.has_method("get_volume") and b.has_method("get_volume"):
		return a.get_volume() < b.get_volume()
	# Fallback if get_volume missing (shouldn't happen with V2)
	return false

func _crossfade_to(stream, pitch, vol, time):
	# If MDM was playing, stop it?
	if _mdm_instance and _mdm_instance.has_method("stop"):
		_mdm_instance.call("stop")

	# If current stream is same, update properties
	if _active_player and _active_player.stream == stream:
		if _active_player.playing:
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, vol, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_property(_active_player, "pitch_scale", _active_player.pitch_scale, pitch, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.start()
			return

	var next_player = _bgm_player_1
	if _active_player == _bgm_player_1:
		next_player = _bgm_player_2

	if stream:
		next_player.stream = stream
		next_player.pitch_scale = pitch
		next_player.volume_db = -80 # Start silent
		next_player.play()

		_tween.stop_all()
		_tween.interpolate_property(next_player, "volume_db", -80, vol, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)

		if _active_player and _active_player.playing:
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, -80, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_callback(_active_player, time, "stop")

		_tween.start()
		_active_player = next_player
	else:
		# Fade out active if no new stream
		if _active_player and _active_player.playing:
			_tween.stop_all()
			_tween.interpolate_property(_active_player, "volume_db", _active_player.volume_db, -80, time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.interpolate_callback(_active_player, time, "stop")
			_tween.start()
			_active_player = null

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
