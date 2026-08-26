extends SceneTree

# Imprime, una por linea, la ruta de cada textura del .lmbake.
#
# El postproceso las sacaba con "strings" sobre el archivo, y eso se rompe apenas Godot
# guarda el recurso comprimido (firma RSCC), que es lo que hace al recocer. Pedirselas
# al motor funciona con el recurso comprimido o sin comprimir.
#
#   godot3 --path . -s tools/dump_lightmap_paths.gd -- --data=res://.../Dome_Intro.lmbake

func _init():
	var data_path := "res://core_v2/levels/interiors/Dome_Intro.lmbake"
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--data="):
			data_path = arg.substr(7)
	var data = load(data_path)
	if data == null:
		printerr("[dump_lightmap_paths] no se pudo cargar ", data_path)
		quit(1)
		return
	for i in range(data.get_user_count()):
		var tex = data.get_user_lightmap(i)
		if tex != null and tex.resource_path != "":
			print(tex.resource_path)
	quit(0)
