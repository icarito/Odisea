extends SceneTree

# Saca el octree de capture de un .lmbake, sin volver a hornear.
#
# El octree es la GI para objetos dinamicos y ocupa el 99.99% del archivo
# (58.129.272 de 58.136.190 bytes en Dome_Intro). En este proyecto no aporta NADA:
# medido sobre el frame, apagar el lightmap dejando la capture da media 14.2914, y
# soltar light_data entero —que se lleva tambien la capture— da 14.2819. Diferencia:
# 0.01 sobre 255. El capture de lightmap es una via de GLES3, y este proyecto es GLES2.
#
# Las 40 texturas del lightmap NO se tocan: viven en PNG aparte y son las que se ven.
#
# Uso:
#   godot3-bin --no-window -s tools/strip_lightmap_capture.gd -- --data=res://<ruta>.lmbake
#   ... --check   (solo informa, no escribe)

func _init() -> void:
	var data_path := _arg("data", "res://core_v2/levels/interiors/Dome_Intro.lmbake")
	var check_only := _has_flag("check")
	var data = load(data_path)
	if data == null or not (data is BakedLightmapData):
		push_error("[strip_capture] no es un BakedLightmapData: %s" % data_path)
		quit(1)
		return
	var octree: PoolByteArray = data.get("octree")
	var before: int = octree.size()
	var users: int = data.get_user_count()
	if before == 0:
		print("[strip_capture] %s ya no tiene octree (users=%d)" % [data_path, users])
		quit(0)
		return
	if check_only:
		print("[strip_capture] %s: octree=%d bytes, users=%d (--check, no se escribe)" % [data_path, before, users])
		quit(0)
		return
	data.set("octree", PoolByteArray())
	var err: int = ResourceSaver.save(data_path, data)
	if err != OK:
		push_error("[strip_capture] no pude guardar %s: %d" % [data_path, err])
		quit(1)
		return
	# Releer del disco: la unica prueba de que las texturas sobrevivieron al guardado.
	var reloaded = load(data_path)
	var users_after: int = reloaded.get_user_count() if reloaded != null else -1
	if users_after != users:
		push_error("[strip_capture] users %d -> %d: el guardado perdio texturas" % [users, users_after])
		quit(1)
		return
	print("[strip_capture] %s: octree %d -> 0 bytes, users intactos=%d" % [data_path, before, users_after])
	quit(0)

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_args():
		var arg := String(raw)
		if arg.begins_with("--%s=" % name):
			return arg.substr(len(name) + 3, len(arg))
	return fallback

func _has_flag(name: String) -> bool:
	for raw in OS.get_cmdline_args():
		if String(raw) == "--%s" % name:
			return true
	return false
