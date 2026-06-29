extends CanvasLayer
class_name PrologueDirector

export(AudioStream) var music_stream: AudioStream
export(String, FILE, "*.tscn") var next_scene_path: String = "res://core_v2/levels/interiors/Dome_Crio.tscn"
export(String) var skip_action: String = "skip"

onready var _music: AudioStreamPlayer = $Music
onready var _countdown: Label = $Countdown
onready var _skip_hint: Label = $SkipHint

var _duration: float = 0.0
var _running: bool = false
var _transition_started: bool = false

func _ready() -> void:
	_countdown.hide()
	_skip_hint.hide()
	var session := get_node_or_null("/root/SessionManager")
	if session and session.has_method("register_oys_actor"):
		session.register_oys_actor("PrologueDirector", self)
	call_deferred("start_prologue")

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
	_skip_hint.show()
	_update_countdown()

func _process(_delta: float) -> void:
	if not _running:
		return
	_update_countdown()
	if not _music.playing:
		_finish_prologue()

func _unhandled_input(event: InputEvent) -> void:
	if _running and event.is_action_pressed(skip_action):
		get_tree().set_input_as_handled()
		_finish_prologue()

func _update_countdown() -> void:
	var remaining: float = max(0.0, _duration - _music.get_playback_position())
	var total_seconds: int = int(ceil(remaining))
	_countdown.text = "%02d:%02d" % [int(total_seconds / 60), total_seconds % 60]

func _finish_prologue() -> void:
	if not _running or _transition_started:
		return
	_transition_started = true
	_running = false
	_music.stop()
	_countdown.text = "00:00"
	_skip_hint.hide()
	var scene_manager := get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		scene_manager.goto_scene(next_scene_path, {
			"transition": "fade",
			"show_loading": false,
			"fade_out": 2.2,
			"wait_for_fade_out": true,
			"fade_in": 1.2,
			"audio_fade_out": 1.8,
			"preserve_player_state": false
		})
	else:
		get_tree().change_scene(next_scene_path)
