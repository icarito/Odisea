tool
extends Spatial
class_name SFXComponentV2

export(String) var sound_name = "" # For Mixing Desk Sound integration
export(AudioStream) var audio_stream
export(float, -80, 24) var volume_db = 0.0 setget _set_volume_db
export(float, 0.1, 4.0) var pitch_scale = 1.0 setget _set_pitch_scale
export(float, 0, 100) var max_distance = 20.0 setget _set_max_distance
export(bool) var loop = false
export(String, "Active", "Interact", "OneShotActive", "OneShotInteract") var trigger_mode = "Active"

var _player: AudioStreamPlayer3D
var _mds_node: Node # Reference to MixingDeskSound (if available)

func _ready():
	_player = AudioStreamPlayer3D.new()
	_player.name = "SFXPlayer"
	# Ensure stream is set if available
	if audio_stream:
		_player.stream = audio_stream

	_player.unit_db = volume_db
	_player.pitch_scale = pitch_scale
	_player.max_distance = max_distance
	_player.unit_size = 1.0
	_player.bus = "Master"
	add_child(_player)

	# Try to find MixingDeskSound globally or in the tree
	if sound_name != "":
		# Common pattern: MDS might be an autoload or a specific node in the scene
		# We'll rely on AudioManager to provide access if it knows about it, or search manually
		pass

	if Engine.editor_hint: return

	var parent = get_parent()
	if not parent: return

	if parent.has_signal("activated"):
		parent.connect("activated", self, "_on_activated")
		parent.connect("deactivated", self, "_on_deactivated")
	if parent.has_signal("interaction_started"):
		parent.connect("interaction_started", self, "_on_interaction")

	# Initial state check
	if trigger_mode == "Active" and loop and parent.get("is_active"):
		_play_sfx()

func play_sfx():
	# Priority 1: Mixing Desk Sound via name
	if sound_name != "" and AudioManager.has_method("play_sound"):
		AudioManager.play_sound(sound_name, global_transform.origin)
		return

	# Priority 2: Local AudioStreamPlayer3D
	if _player.stream:
		if not _player.playing:
			_player.play()

func _play_sfx():
	# Backward compatibility / internal use
	play_sfx()

func _stop_sfx():
	# Mixing Desk stops are tricky unless we hold a reference to the specific voice instance.
	# For now, we only support stopping on the local player.
	# If using Mixing Desk for looping sounds, we'd need more complex integration.
	if _player.playing:
		_player.stop()

func _on_activated():
	if trigger_mode == "Active":
		_play_sfx()
	elif trigger_mode == "OneShotActive":
		_play_sfx()

func _on_deactivated():
	if trigger_mode == "Active" and loop:
		_stop_sfx()

func _on_interaction():
	if trigger_mode == "Interact" or trigger_mode == "OneShotInteract":
		_play_sfx()

# Setters for editor
func _set_volume_db(v):
	volume_db = v
	if _player: _player.unit_db = v

func _set_pitch_scale(v):
	pitch_scale = v
	if _player: _player.pitch_scale = v

func _set_max_distance(v):
	max_distance = v
	if _player: _player.max_distance = v
