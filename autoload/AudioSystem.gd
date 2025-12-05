extends Node

# AudioSystem (autoload: "AudioSystem")
# Responsibility: Playback and management of all audio sources (BGM, SFX).

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array = []
const MAX_SFX_PLAYERS = 16 # Max concurrent SFX sounds
var _current_bgm_path: String = ""
var _loop_bgm: bool = true

func _ready() -> void:
	# BGM Player Setup
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "Master" # Use a dedicated "Music" bus if available
	_bgm_player.connect("finished", self, "_on_bgm_finished")
	add_child(_bgm_player)

	# SFX Player Pool Setup
	for i in range(MAX_SFX_PLAYERS):
		var sfx_player = AudioStreamPlayer.new()
		sfx_player.name = "SFXPlayer_" + str(i)
		add_child(sfx_player)
		_sfx_players.append(sfx_player)

# --- Public API ---

func play_sfx(sound_path: String, volume_db: float = 0.0) -> void:
	for player in _sfx_players:
		if not player.playing:
			var stream = load(sound_path)
			if stream is AudioStream:
				player.stream = stream
				player.volume_db = volume_db
				player.play()
				return
			else:
				push_error("AudioSystem: Failed to load SFX at path: " + sound_path)
				return
	push_warning("AudioSystem: No available SFX players to play sound: " + sound_path)

func play_bgm(music_path: String, fade_time: float = 0.0, loop: bool = true, volume_db: float = -6.0) -> void:
	_current_bgm_path = music_path
	_loop_bgm = loop

	var stream = load(music_path)
	if not stream is AudioStream:
		push_error("AudioSystem: Failed to load BGM at path: " + music_path)
		return

	if _bgm_player.playing and fade_time > 0:
		_fade_out_and_in(stream, fade_time, volume_db)
	else:
		_bgm_player.stream = stream
		_bgm_player.volume_db = volume_db
		_bgm_player.play()

func stop_all_sfx() -> void:
	for player in _sfx_players:
		player.stop()

func stop_bgm(fade_time: float = 0.0) -> void:
	if not _bgm_player.playing:
		return
	if fade_time > 0:
		_fade_audio(_bgm_player, _bgm_player.volume_db, -80.0, fade_time, true)
	else:
		_bgm_player.stop()

# --- Private Helper Functions ---

func _on_bgm_finished() -> void:
	if _loop_bgm and not _current_bgm_path.empty():
		_bgm_player.play()

func _fade_out_and_in(new_stream: AudioStream, duration: float, new_volume_db: float):
	var tween = create_tween()
	# Fade out
	tween.tween_property(_bgm_player, "volume_db", -80.0, duration / 2.0)
	tween.tween_callback(self, "_on_fade_out_finished", [new_stream, new_volume_db, duration / 2.0])

func _on_fade_out_finished(new_stream: AudioStream, new_volume_db: float, fade_in_duration: float):
	_bgm_player.stream = new_stream
	_bgm_player.play()
	# Fade in
	_fade_audio(_bgm_player, -80.0, new_volume_db, fade_in_duration)

func _fade_audio(player: AudioStreamPlayer, from_db: float, to_db: float, duration: float, stop_after: bool = false):
	var tween = create_tween()
	player.volume_db = from_db
	tween.tween_property(player, "volume_db", to_db, duration)
	if stop_after:
		tween.tween_callback(player, "stop")

func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		stop_all_sfx()
		_bgm_player.stop()