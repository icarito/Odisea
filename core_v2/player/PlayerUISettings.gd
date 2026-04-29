extends Node
class_name PlayerUISettings

export(float, 0.1, 5.0) var terminal_cursor_sensitivity := 1.8
export(float, 0.35, 1.0) var holo_projector_resolution_scale := 0.75

func get_terminal_cursor_sensitivity() -> float:
	return terminal_cursor_sensitivity

func get_holo_projector_resolution_scale() -> float:
	return holo_projector_resolution_scale
