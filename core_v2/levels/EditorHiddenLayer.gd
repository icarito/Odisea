tool
extends Spatial

export(bool) var hidden_in_editor := true
export(bool) var visible_in_game := true

func _enter_tree() -> void:
	_apply_visibility()

func _ready() -> void:
	_apply_visibility()

func _apply_visibility() -> void:
	if Engine.is_editor_hint():
		visible = not hidden_in_editor
	else:
		visible = visible_in_game
