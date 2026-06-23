extends CanvasLayer
class_name PrologueDirector

export(AudioStream) var music_stream: AudioStream
export(String, FILE, "*.tscn") var next_scene_path: String = "res://core_v2/levels/interiors/Dome_Crio.tscn"

onready var _music: AudioStreamPlayer = $Music
onready var _countdown: Label = $Countdown

var _duration: float = 0.0
var _running: bool = false

func _ready() -> void:
	_countdown.hide()
	var session := get_node_or_null("/root/SessionManager")
	if session and session.has_method("register_oys_actor"):
		session.register_oys_actor("PrologueDirector", self)

func start_prologue() -> void:
	if _running or music_stream == null:
		return
	_running = true
	var playback_stream: AudioStream = music_stream.duplicate()
	if "loop" in playback_stream:
		playback_stream.set("loop", false)
	_duration = max(0.0, float(playback_stream.get_length()))
	_music.stream = playback_stream
	_music.play()
	_countdown.show()
	_update_countdown()

func _process(_delta: float) -> void:
	if not _running:
		return
	_update_countdown()
	if not _music.playing:
		_finish_prologue()

func _update_countdown() -> void:
	var remaining: float = max(0.0, _duration - _music.get_playback_position())
	var total_seconds: int = int(ceil(remaining))
	_countdown.text = "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]

func _finish_prologue() -> void:
	if not _running:
		return
	_running = false
	_countdown.text = "00:00"
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		scene_manager.goto_scene(next_scene_path, {
			"show_loading": true,
			"loading_message": "MÓDULO CRIOGENIA",
			"fade_out": 0.8,
			"fade_in": 0.8,
			"audio_fade_out": 0.5
		})
	else:
		get_tree().change_scene(next_scene_path)
