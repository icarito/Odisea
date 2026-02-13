tool
extends Node

# SceneSnaper.gd
# Helper tool to snap all children transforms to a grid.
# Useful for voxel-style projects to ensure perfect shadow alignment.

export(float) var snap_amount = 0.125
export(bool) var trigger_snap = false setget set_trigger_snap

func set_trigger_snap(val):
	if val:
		snap_all_children(self)
		print("Scene snapped to grid: ", snap_amount)
	trigger_snap = false

func snap_all_children(node):
	for child in node.get_children():
		if child is Spatial:
			child.translation = child.translation.snapped(Vector3(snap_amount, snap_amount, snap_amount))
			# Recursively snap children of containers/groups
			if child.get_class() == "Spatial" or child is Node:
				snap_all_children(child)
