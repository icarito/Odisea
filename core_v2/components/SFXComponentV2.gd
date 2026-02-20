tool
extends AudioStreamPlayer3D
class_name SFXComponentV2

export(String) var sound_name = "" # For Mixing Desk Sound integration
export(bool) var loop_sample = false # Renamed to avoid loop conflict if any
export(float) var fade_in_time = 0.0
export(float) var fade_out_time = 0.0
export(String, "Active", "Interact", "OneShotActive", "OneShotInteract") var trigger_mode = "Active"

var _mds_node: Node # Reference to MixingDeskSound (if available)
var _tween: Tween = null
var _base_unit_db = 0.0

func _ready():
	_base_unit_db = unit_db
	_tween = Tween.new()
	add_child(_tween)
	
	# Configure loop on the stream itself if needed
	if stream and loop_sample and stream is AudioStreamSample:
		stream.loop_mode = AudioStreamSample.LOOP_FORWARD
	
	# Solo asignar default si no está configurado
	if unit_size <= 0:
		unit_size = 1.0
	bus = "Master"


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
	if trigger_mode == "Active" and loop_sample and parent.get("is_active"):
		_play_sfx()

func play_sfx():
	# Priority 1: Mixing Desk Sound via name
	var audio_manager = null
	if Engine.has_singleton("AudioManager"):
		audio_manager = Engine.get_singleton("AudioManager")
	if audio_manager and sound_name != "" and audio_manager.has_method("play_sound"):
		audio_manager.play_sound(sound_name, global_transform.origin)
		return

	# Priority 2: Local AudioStreamPlayer3D
	if stream:
		if not playing:
			if fade_in_time > 0 and _tween:
				unit_db = -80.0
				play()
				_tween.stop_all()
				_tween.interpolate_property(self, "unit_db", -80.0, _base_unit_db, fade_in_time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
				_tween.start()
			else:
				unit_db = _base_unit_db
				play()

func stop_sfx():
	# Mixing Desk stops are tricky unless we hold a reference to the specific voice instance.
	# For now, we only support stopping on the local player.
	# If using Mixing Desk for looping sounds, we'd need more complex integration.
	if playing:
		if fade_out_time > 0 and _tween:
			_tween.stop_all()
			_tween.interpolate_property(self, "unit_db", unit_db, -80.0, fade_out_time, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
			_tween.start()
			_tween.interpolate_callback(self, fade_out_time, "stop")
		else:
			stop()

func _play_sfx():
	# Backward compatibility / internal use
	play_sfx()

func _on_activated():
	if trigger_mode == "Active":
		_play_sfx()
	elif trigger_mode == "OneShotActive":
		_play_sfx()

func _on_deactivated():
	if trigger_mode == "Active" and loop_sample:
		stop_sfx()

func _on_interaction():
	if trigger_mode == "Interact" or trigger_mode == "OneShotInteract":
		_play_sfx()
