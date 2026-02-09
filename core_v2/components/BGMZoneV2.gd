tool
extends "res://core_v2/components/BaseZoneV2.gd"
class_name BGMZoneV2

export(AudioStream) var bgm_stream
export(float) var fade_time = 2.0
export(float, 0.1, 4.0) var pitch_scale = 1.0
export(float, -80, 24) var volume_db = 0.0

func _on_zone_entered(body: Node):
	if not Engine.editor_hint:
		AudioManager.register_zone(self)

func _on_zone_exited(body: Node):
	if not Engine.editor_hint:
		AudioManager.unregister_zone(self)
