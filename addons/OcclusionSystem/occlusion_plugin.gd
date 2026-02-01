tool
extends EditorPlugin

func _enter_tree():
	var gui = get_editor_interface().get_base_control()
	add_custom_type("OcclusionArea", "Area", preload("res://core_v2/components/OcclusionZoneV2.gd"), gui.get_icon("Area", "EditorIcons"))

func _exit_tree():
	remove_custom_type("OcclusionArea")
