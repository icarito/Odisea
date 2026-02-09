extends Node

# AudioManager.gd
# Manages global audio state, specifically BGM cross-fading and zone management.
# BGM zones are prioritized by volume (smaller volume = higher priority).

var _bgm_player_1: AudioStreamPlayer
var _bgm_player_2: AudioStreamPlayer
var _active_player: AudioStreamPlayer = null
var _tween: Tween

var _active_zones := []

func _ready():
	_bgm_player_1 = AudioStreamPlayer.new()
	_bgm_player_1.bus = "Master" # Default to Master if Music bus not present
	_bgm_player_1.name = "BGMPlayer1"
	add_child(_bgm_player_1)

	_bgm_player_2 = AudioStreamPlayer.new()
	_bgm_player_2.bus = "Master"
	_bgm_player_2.name = "BGMPlayer2"
	add_child(_bgm_player_2)

	_tween = Tween.new()
	_tween.name = "FadeTween"
	add_child(_tween)

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
	# Assuming zone has get_volume() and smaller is higher priority
	_active_zones.sort_custom(self, "_sort_zones")

	var target_stream = null
	var target_pitch = 1.0
	var target_volume = 0.0
	var fade_time = 1.0

	if _active_zones.size() > 0:
		var top = _active_zones[0]
		target_stream = top.bgm_stream
		target_pitch = top.pitch_scale
		target_volume = top.volume_db
		fade_time = top.fade_time

	_crossfade_to(target_stream, target_pitch, target_volume, fade_time)

func _sort_zones(a, b):
	if a.has_method("get_volume") and b.has_method("get_volume"):
		return a.get_volume() < b.get_volume()
	return false

func _crossfade_to(stream, pitch, vol, time):
	# If current stream is same, maybe update pitch/vol but don't restart
	if _active_player and _active_player.stream == stream:
		if _active_player.playing:
			# Just update properties with tween if needed?
			# For now, let's assume if stream is same, we keep playing.
			# We might want to fade volume/pitch if changed.
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
