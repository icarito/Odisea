extends SceneTree

# Corre un replay por inputs con ventana y reporta el avance: si se corta, donde, y con
# cuanta desviacion contra final_expected_state. Uso:
#   DBG_REPLAY=user://replay_XXXX.json godot3-bin --path . -s tools/dbg_replay_run.gd

func _init() -> void:
	var path: String = OS.get_environment("DBG_REPLAY")
	if path == "":
		path = "user://replay_1786401125.json"
	yield(self, "idle_frame")

	var sm = get_root().get_node_or_null("SessionManager")
	if sm == null:
		print("[r] sin SessionManager"); quit(); return

	var f := File.new()
	if f.open(path, File.READ) != OK:
		print("[r] no se pudo abrir ", path); quit(); return
	var data = JSON.parse(f.get_as_text()).result
	f.close()
	var esperado: Dictionary = data.get("final_expected_state", {})
	var total: int = data.get("buffer", []).size()
	print("[r] escena=%s  buffer=%d" % [data.get("meta", {}).get("scene", "?"), total])

	sm.load_and_play(path)

	var esperado_pos := Vector3.ZERO
	if esperado.has("position"):
		var e = esperado["position"]
		esperado_pos = Vector3(e[0], e[1], e[2])

	var _peor_desfase := 0
	var espera := 0
	var ultimo_frame := -1
	var estancado := 0
	while espera < 20000:
		yield(self, "idle_frame")
		espera += 1
		var fr: int = int(sm.get("_replay_frame"))
		if fr != ultimo_frame:
			ultimo_frame = fr
			estancado = 0
		else:
			estancado += 1
		# Doble consumo: por cada frame de replay el buffer deberia avanzar exactamente 1.
		# Si playback_index corre mas rapido que _replay_frame, alguien mas llama
		# get_input() y se come entradas: eso es lo que se ve como yank de camara.
		if is_instance_valid(sm.player) and ("input_provider" in sm.player) and is_instance_valid(sm.player.input_provider):
			var idx: int = int(sm.player.input_provider.playback_index)
			if idx - fr > _peor_desfase:
				_peor_desfase = idx - fr
				print("[r] DESFASE buffer: playback_index=%d vs _replay_frame=%d (adelanto=%d)" % [idx, fr, idx - fr])
		if fr % 300 == 0 and fr != 0 and estancado == 0:
			var p = sm.player.global_transform.origin if is_instance_valid(sm.player) else Vector3.ZERO
			print("[r] frame %d/%d  pos=%s" % [fr, total, p])
		if not sm.is_replaying:
			print("[r] replay TERMINO en frame %d de %d" % [fr, total])
			break
		if estancado > 600:
			print("[r] ATASCADO en frame %d de %d (600 frames sin avanzar)" % [fr, total])
			break

	if is_instance_valid(sm.player):
		var real = sm.player.global_transform.origin
		print("[r] esperada=%s" % esperado_pos)
		print("[r] real    =%s" % real)
		print("[r] DRIFT   =%.4f m" % real.distance_to(esperado_pos))
	quit()
