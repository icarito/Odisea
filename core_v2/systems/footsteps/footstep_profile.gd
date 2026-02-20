extends Resource
class_name FootstepProfile

export(Array) var streams: Array = []
export(float, 0.5, 2.0) var random_pitch_min: float = 0.9
export(float, 0.5, 2.0) var random_pitch_max: float = 1.1
export(float, -40.0, 10.0) var random_volume_db_min: float = -2.0
export(float, -40.0, 10.0) var random_volume_db_max: float = 2.0

func get_random_stream() -> AudioStream:
	if streams.empty():
		return null
	var idx = randi() % streams.size()
	return streams[idx]

func get_random_pitch() -> float:
	return rand_range(random_pitch_min, random_pitch_max)

func get_random_volume_db() -> float:
	return rand_range(random_volume_db_min, random_volume_db_max)
