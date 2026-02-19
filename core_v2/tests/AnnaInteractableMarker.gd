extends CSGBox

export(String) var interaction_text := "Inspect marker"
export(bool) var auto_interact := false
export(bool) var one_off := false

var _auto_triggered := false
var is_active := false
var _base_scale := Vector3.ONE

func _ready() -> void:
	_base_scale = scale

func set_highlighted(active: bool) -> void:
	scale = _base_scale * (1.08 if active else 1.0)
