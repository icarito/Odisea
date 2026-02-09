tool
extends "res://core_v2/components/BaseZoneV2.gd"
class_name BGMZoneV2

export(String) var song_name = "" # For Mixing Desk Music integration
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

func get_volume() -> float:
	# Returns the physical volume of the zone for priority sorting.
	# Smaller volume = Higher priority.
	# BaseZoneV2 usually manages `zone_extents`, so we calculate volume from that.
	if get_node_or_null("CollisionShape") and get_node("CollisionShape").shape is BoxShape:
		var ext = get_node("CollisionShape").shape.extents
		return ext.x * ext.y * ext.z * 8.0
	# Fallback if zone_extents is available on self
	if "zone_extents" in self:
		var ext = self.zone_extents
		return ext.x * ext.y * ext.z * 8.0
	return 999999.0 # Low priority default
