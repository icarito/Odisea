extends Node

export (AudioStream) var default_bgm
export (float) var default_volume_db := -6.0
export (bool) var loop_bgm := true

onready var _music := AudioStreamPlayer.new()

func _ready() -> void:
	add_child(_music)
	_music.bus = "Master" # Cambia a "Music" si existe un bus dedicado
	_music.volume_db = default_volume_db
	if default_bgm:
		_music.stream = default_bgm
		_play_internal()

func play_bgm(stream: AudioStream = null, volume_db: float = INF, loop: bool = true) -> void:
	if stream:
		_music.stream = stream
	if volume_db != INF:
		_music.volume_db = volume_db
	loop_bgm = loop
	_play_internal()

func stop_bgm() -> void:
	if _music.playing:
		_music.stop()
		if _music.is_connected("finished", self, "_on_music_finished"):
			_music.disconnect("finished", self, "_on_music_finished")

func set_volume_db(db: float) -> void:
	_music.volume_db = db

func is_playing() -> bool:
	return _music.playing

func _play_internal() -> void:
	if not _music.stream:
		return
	if _music.is_connected("finished", self, "_on_music_finished"):
		_music.disconnect("finished", self, "_on_music_finished")
	if loop_bgm:
		_music.connect("finished", self, "_on_music_finished", [], CONNECT_ONESHOT)
	_music.play()

func _on_music_finished() -> void:
	if loop_bgm and _music.stream:
		_music.play()

func change_track_on_death(death_track: AudioStream) -> void:
	stop_bgm()
	play_bgm(death_track, default_volume_db, false)

func restart_level_music() -> void:
	stop_bgm()
	play_bgm(default_bgm, default_volume_db, true)
