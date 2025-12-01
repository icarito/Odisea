extends Node

export(String) var target_scene_path = "res://scenes/levels/act1/puente.tscn"

func _ready():
	var area = get_parent()
	if area and area.has_signal("body_entered"):
		area.connect("body_entered", self, "_on_area_body_entered")

func _on_area_body_entered(body):
	if body and body.has_method("get_class") and body.get_class() == "KinematicBody":
		get_tree().change_scene(target_scene_path)
