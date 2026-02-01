tool
extends EditorPlugin

var gizmo_plugin = preload("area_resize_gizmo_plugin.gd").new()

func _enter_tree():
	gizmo_plugin.undo_redo = get_undo_redo()
	add_spatial_gizmo_plugin(gizmo_plugin)

func _exit_tree():
	remove_spatial_gizmo_plugin(gizmo_plugin)
