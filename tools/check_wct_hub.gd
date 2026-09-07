extends SceneTree

func _init() -> void:
	var rig: Node = (load("res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn") as PackedScene).instance()
	var body: MeshInstance = rig.find_node("Body", true, false)
	var verts: PoolVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bands := {"hub_550_700": 0, "platform_660_950": 0, "mid_400_550": 0, "legs_menor_400": 0}
	for v in verts:
		if v.y > 550 and v.y < 700 and abs(v.x) < 300:
			bands.hub_550_700 += 1
		elif v.y >= 660:
			bands.platform_660_950 += 1
		elif v.y >= 400:
			bands.mid_400_550 += 1
		else:
			bands.legs_menor_400 += 1
	for k in bands:
		print("[Hub] %s: %d verts" % [k, bands[k]])
	quit(0)
