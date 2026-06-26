extends SceneTree

func _init():
	var csg = CSGCombiner.new()
	if csg:
		print("CSGCombiner exists")
		var sphere = CSGSphere.new()
		if sphere:
			print("CSGSphere exists")
	quit()
