extends Line2D

export var trail_color := Color(0.2,0.8,1,0.7)
export var fade_speed := 2.0

func _process(delta):
	self.modulate.a = max(0.0, self.modulate.a - fade_speed * delta)
