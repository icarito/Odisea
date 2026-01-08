extends MeshInstance
tool

func _ready():
	yield(get_tree().create_timer(.5), "timeout")
	for c in mesh.get_surface_count():
		var material = mesh.surface_get_material(c)
		material.albedo_color.a = 255
		material.flags_transparent = false
		set_surface_material(c, material)
		var material2 = get_surface_material(c)
		material2.albedo_color.a = 255
