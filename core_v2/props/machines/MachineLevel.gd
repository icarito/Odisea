extends Spatial
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# FD-320: arma un nivel de maquinas a partir de un layout JSON. El mismo formato sirve
# para (a) los niveles prehechos, (b) guardar/cargar lo que arma el jugador y (c) el
# futuro editor. Contrato del formato: .operator-shared/specs/machine-layout.md
#
# Items (todos aceptan "name", "pos" [x,y,z] y "rot" [x,y,z] en grados):
#   block  — geometria estatica: "size", "color"
#   part   — MachinePart: "size", "density", "held", "color"
#   hinge  — MachineHinge: "a", "b" (nombres de items), "limit" [lo,hi], "motor" {speed,torque,on}, "axle" (bool)
#   scene  — instancia cualquier .tscn/.glb: "path", "props" {propiedad: valor}, "optional" (bool)
#   trigger — zona que emite "entered" una sola vez cuando entra el jugador: "size"
#   link   — conecta una senal: "from", "signal", "to", "method", "args", "delay" (s).
#            "to": "@level" apunta a este nodo (p. ej. method "say", args [texto, segundos])

const MachinePart = preload("res://core_v2/props/machines/MachinePart.gd")
const MachineHinge = preload("res://core_v2/props/machines/MachineHinge.gd")
const TriggerScript = preload("res://core_v2/props/machines/MachineTrigger.gd")
const LedgeV2 = preload("res://core_v2/components/LedgeV2.gd")
const SignagePanelScene = preload("res://core_v2/props/signage/SignagePanel.tscn")

export(String, FILE, "*.json") var layout_path := ""
export(bool) var enable_player_multi_tool := true

var _items := {} # name -> Node
var _pending := [] # links con retardo: [ticks_restantes, destino, metodo, args, total_ticks, from_name]
var _signal_links := {} # "from_name:signal" -> Array of [to, method, args, delay_ticks, from_name]
var _conduits := [] # Array of Dictionary: {"from": String, "to": Node, "mat": SpatialMaterial, "active_ticks": int}
var _subtitle_queue := [] # Array of [text, duration_sec]
var _subtitle_hold_ticks := 0
var _last_countdown_sec := -1
var _station_resets := 0
var _elapsed_ticks := 0
var _order_completed := false
var _void_kill_cooldown_ticks := 0


func _ready() -> void:
	add_to_group("replay_sync")
	set_physics_process(true)
	_apply_flat_lighting()
	if layout_path != "":
		load_layout_file(layout_path)
	call_deferred("_ensure_player_multi_tool")


func _apply_flat_lighting() -> void:
	var gate = get_node_or_null("/root/GLES3VendorGate")
	if gate == null:
		return
	if gate.has_method("set_flat_ambient"):
		gate.set_flat_ambient(0.55)
	if gate.has_method("set_flat_world_light"):
		gate.set_flat_world_light(0.95)
	if gate.has_method("set_flat_glow_floor"):
		gate.set_flat_glow_floor(0.35)


func _ensure_player_multi_tool() -> void:
	if not is_inside_tree():
		return
	var parent_node := get_parent()
	var spawn_node: Spatial = parent_node.get_node_or_null("SpawnPointV2") as Spatial if parent_node != null else null
	for player in get_tree().get_nodes_in_group("player"):
		if player == null or not is_instance_valid(player):
			continue
		if enable_player_multi_tool and player.has_method("set_multi_tool_enabled"):
			player.set_multi_tool_enabled(true)
		# Si el jugador vino de otra escena (p. ej. RingHub en x=31.8) y quedo fuera de EntryFloor,
		# ubicarlo sobre SpawnPointV2 mirando hacia +Z (adentro de la bahia).
		if spawn_node != null and player is Spatial and parent_node != null and parent_node.is_a_parent_of(player):
			var p_origin: Vector3 = (player as Spatial).global_transform.origin
			if abs(p_origin.x) > 8.0 or p_origin.y < -0.5 or p_origin.z < -9.0:
				var target_tf := Transform(Basis.IDENTITY, spawn_node.global_transform.origin)
				if player.has_method("teleport_to"):
					player.teleport_to(target_tf)
				else:
					(player as Spatial).global_transform = target_tf
				if "initial_transform" in player:
					player.initial_transform = target_tf
				if "yaw" in player:
					player.yaw = PI
				if "yaw_deg" in player:
					player.yaw_deg = 180.0
				if player.has_method("snap_camera_to_current_state"):
					player.snap_camera_to_current_state()
				var ts = get_node_or_null("/root/SessionManager/TeleportSystem")
				if ts != null and ts.has_method("force_initial_spawn"):
					ts.force_initial_spawn(target_tf, PI, 0.0)
				var cm = get_node_or_null("/root/CheckpointManager")
				if cm != null and cm.has_method("set_active_checkpoint"):
					cm.set_active_checkpoint(target_tf.origin, PI, 0.0)


func load_layout_file(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		push_error("MachineLevel: no se pudo abrir " + path)
		return false
	var parsed := JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not (parsed.result is Dictionary):
		push_error("MachineLevel: JSON invalido en %s (linea %d)" % [path, parsed.error_line])
		return false
	build(parsed.result)
	return true


func build(layout: Dictionary) -> void:
	var links := []
	for item in layout.get("items", []):
		if not (item is Dictionary):
			continue
		if str(item.get("type", "")) == "link":
			links.append(item)
			continue
		var node := _make(item)
		if node == null:
			continue
		node.name = str(item.get("name", node.name))
		node.set_meta("layout_item", item)
		_place(node, item)
		add_child(node)
		_items[node.name] = node
	for link in links:
		_connect_link(link)


func get_item(item_name: String) -> Node:
	return _items.get(item_name)


# Estado actual de las piezas moviles como layout, para guardar lo que armo el jugador.
func export_layout() -> Dictionary:
	var items := []
	for node in _items.values():
		if not is_instance_valid(node) or not node.has_meta("layout_item"):
			continue
		var item: Dictionary = node.get_meta("layout_item").duplicate(true)
		var t: Transform = (node as Spatial).transform
		var e := t.basis.get_euler()
		item["pos"] = [t.origin.x, t.origin.y, t.origin.z]
		item["rot"] = [rad2deg(e.x), rad2deg(e.y), rad2deg(e.z)]
		if item.has("held"):
			item["held"] = bool(node.get("held")) # una pieza ya soltada no vuelve retenida
		items.append(item)
	return {"items": items}


func save_layout_file(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		return false
	f.store_string(JSON.print(export_layout(), "\t"))
	f.close()
	return true


func _make(item: Dictionary) -> Spatial:
	match str(item.get("type", "")):
		"block":
			return _make_block(item)
		"part":
			var part = MachinePart.new()
			part.size = _vec(item.get("size", [2, 0.2, 1]))
			part.density = float(item.get("density", 150.0))
			part.held = bool(item.get("held", false))
			part.cuttable = bool(item.get("cuttable", false))
			if item.has("cut_time"):
				part.cut_heat_time = float(item["cut_time"])
			if item.has("color"):
				part.color = Color(str(item["color"]))
			elif part.cuttable:
				part.color = Color("#d94e1f")
			return part
		"hinge":
			var hinge = MachineHinge.new()
			# Las piezas son hermanas dentro de este nivel.
			hinge.body_a_path = NodePath("../" + str(item.get("a", "")))
			if str(item.get("b", "")) != "":
				hinge.body_b_path = NodePath("../" + str(item["b"]))
			if item.has("limit"):
				hinge.use_limit = true
				hinge.limit_lower_deg = float(item["limit"][0])
				hinge.limit_upper_deg = float(item["limit"][1])
			hinge.show_axle = bool(item.get("axle", true))
			var motor: Dictionary = item.get("motor", {})
			hinge.motor_speed = float(motor.get("speed", hinge.motor_speed))
			hinge.motor_torque = float(motor.get("torque", hinge.motor_torque))
			hinge.motor_enabled = bool(motor.get("on", false))
			return hinge
		"trigger":
			return _make_trigger(item)
		"ledge":
			return _make_ledge(item)
		"sign":
			return _make_sign(item)
		"scene":
			# "optional": decoracion cuyo import puede no existir (CI no importa assets nuevos).
			if bool(item.get("optional", false)) and not ResourceLoader.exists(str(item.get("path", ""))):
				return null
			var packed = load(str(item.get("path", "")))
			if not (packed is PackedScene):
				push_error("MachineLevel: escena invalida " + str(item.get("path", "")))
				return null
			var inst = packed.instance()
			var props: Dictionary = item.get("props", {})
			for key in props:
				var value = props[key]
				if value is Array and value.size() == 3:
					value = _vec(value)
				inst.set(key, value)
			if bool(item.get("optional", false)) or not bool(item.get("cast_shadow", true)):
				_disable_shadow_casting(inst)
			return inst as Spatial
	push_error("MachineLevel: tipo de item desconocido: " + str(item.get("type", "")))
	return null


func _make_block(item: Dictionary) -> StaticBody:
	var size := _vec(item.get("size", [1, 1, 1]))
	var body := StaticBody.new()
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = size * 0.5
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = size
	mesh.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(str(item.get("color", "#3a4048")))
	mat.roughness = 0.85
	mat.metallic = 0.2
	if bool(item.get("emissive", false)):
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy = float(item.get("emission_energy", 0.55))
	mesh.material_override = mat
	body.add_child(mesh)
	return body


func _make_ledge(item: Dictionary) -> StaticBody:
	var ledge := LedgeV2.new()
	ledge.ledge_width = float(item.get("width", 2.0))
	if item.has("color"):
		ledge.ledge_color = Color(str(item["color"]))
	ledge.ledge_emissive = bool(item.get("emissive", true))
	return ledge


func _make_sign(item: Dictionary) -> Spatial:
	var sign_node := SignagePanelScene.instance() as Spatial
	if sign_node == null:
		return null
	sign_node.set("text", str(item.get("text", "ESTACIÓN")))
	sign_node.set("color_preset", str(item.get("preset", "warning")))
	sign_node.set("double_sided", bool(item.get("double_sided", true)))
	sign_node.set("border_enabled", bool(item.get("border", true)))
	sign_node.set("panel_alpha", float(item.get("panel_alpha", 0.92)))
	sign_node.set("emission_energy", float(item.get("emission_energy", 1.35)))
	sign_node.set("text_color", Color(1.0, 0.98, 0.92, 1.0))
	if item.has("font_size"):
		sign_node.set("font_size", int(item["font_size"]))
	if item.has("scale"):
		var s = item["scale"]
		if s is Array and s.size() == 3:
			sign_node.scale = _vec(s)
		else:
			var f := float(s)
			sign_node.scale = Vector3(f, f, 1.0)
	_disable_shadow_casting(sign_node)
	return sign_node


func _make_conduit(from_node: Spatial, to_node: Spatial, from_name: String) -> void:
	if from_node == null or to_node == null:
		return
	var p_a: Vector3 = from_node.transform.origin + Vector3(0.0, 0.35, 0.0)
	var p_b: Vector3 = to_node.transform.origin
	var dist := p_a.distance_to(p_b)
	if dist < 0.25 or dist > 35.0:
		return
	var mesh_inst := MeshInstance.new()
	mesh_inst.name = "Conduit_%s_%s" % [from_name, to_node.name]
	var cube := CubeMesh.new()
	cube.size = Vector3(0.045, 0.045, dist)
	mesh_inst.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color("#d96b1f")
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color("#d96b1f")
	mat.emission_energy = 1.15
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var mid := (p_a + p_b) * 0.5
	var dir := (p_b - p_a).normalized()
	var up := Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var z_axis := -dir
	var x_axis := up.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	mesh_inst.transform = Transform(Basis(x_axis, y_axis, z_axis), mid)
	add_child(mesh_inst)
	_conduits.append({
		"from": from_name,
		"to": to_node,
		"mat": mat,
		"active_ticks": 0,
	})


func _make_trigger(item: Dictionary) -> Area:
	var area := Area.new()
	area.set_script(TriggerScript)
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = _vec(item.get("size", [2, 2, 2])) * 0.5
	shape.shape = box
	area.add_child(shape)
	return area


# Linea de la IA Odisea. Texto, no audio: la voz llega por el overlay de subtitulos y se
# registra en el log de comunicaciones del traje (SuitOS / SuitScreen).
func say(text: String, duration: float = 8.0) -> void:
	var effective_duration := max(7.5, duration)
	var suit_screen := _get_suit_screen()
	if suit_screen != null and suit_screen.has_method("ensure_model"):
		var model = suit_screen.ensure_model()
		if model != null and model.has_method("add_comms"):
			var clean := text
			if clean.begins_with("ODISEA: "):
				clean = clean.substr(8)
			model.add_comms("ODISEA", clean, "odisea")
			if suit_screen.has_method("notify_state_changed"):
				suit_screen.notify_state_changed()
	if _subtitle_hold_ticks > 0:
		for queued in _subtitle_queue:
			if str(queued[0]) == text:
				return
		_subtitle_queue.append([text, effective_duration])
		return
	_show_subtitle_now(text, effective_duration)


func _show_subtitle_now(text: String, duration: float) -> void:
	var subtitles := get_node_or_null("/root/SubtitlesOverlayManager")
	if subtitles != null and subtitles.has_method("show_subtitle"):
		subtitles.show_subtitle(tr(text), Color(0.55, 0.95, 1.0), duration)
	# Minimo de separacion entre lineas consecutivas en pantalla (3.2 s) para que nunca pasen rapido.
	_subtitle_hold_ticks = int(round(min(duration * 0.55, 3.4) * Engine.iterations_per_second))


func _get_suit_screen() -> Object:
	var suit_os := get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_method("get_screen"):
		var scr = suit_os.get_screen("suit:status")
		if scr != null:
			return scr
	if is_inside_tree():
		for player in get_tree().get_nodes_in_group("player"):
			if player != null and is_instance_valid(player):
				var found = player.find_node("SuitScreen", true, false)
				if found != null:
					return found
	return null


func start_work_order() -> void:
	var suit_screen := _get_suit_screen()
	if suit_screen == null or not suit_screen.has_method("ensure_model"):
		return
	var model = suit_screen.ensure_model()
	if model == null:
		return
	model.complete_objective("lights")
	if not model.objective_ids().has("order_0001"):
		model.add_objective("order_0001", "Orden 0001: Restablecer flujo en Bahía 3", model.OBJ_ACTIVE)
	elif model.objective_state("order_0001") != model.OBJ_DONE:
		model.set_objective_state("order_0001", model.OBJ_ACTIVE)
	if suit_screen.has_method("notify_state_changed"):
		suit_screen.notify_state_changed()


func complete_work_order() -> void:
	if _order_completed:
		return
	_order_completed = true
	var elapsed_sec := int(round(get_elapsed_seconds()))
	var resets := get_station_resets()
	var suit_screen := _get_suit_screen()
	if suit_screen != null and suit_screen.has_method("ensure_model"):
		var model = suit_screen.ensure_model()
		if model != null:
			model.complete_objective("lights")
			if not model.objective_ids().has("order_0001"):
				model.add_objective("order_0001", "Orden 0001: Restablecer flujo en Bahía 3", model.OBJ_DONE)
			else:
				model.complete_objective("order_0001")
			if not model.objective_ids().has("return_hub"):
				model.add_objective("return_hub", "Retornar al anillo de criogenia o aguardar Orden 0002", model.OBJ_ACTIVE)
			if suit_screen.has_method("notify_state_changed"):
				suit_screen.notify_state_changed()
	say("ODISEA: Orden de Trabajo 0001 cerrada. Flujo principal restablecido en Bahía 3.", 7.5)
	var line_eval := "ODISEA: Tiempo presupuestado: 240 s. Tiempo real: %d s. Rearmes de estación: %d." % [elapsed_sec, resets]
	var line_reprimand := "ODISEA: Amonestación 0001 archivada: uso no homologado de contrapesos y corte térmico de retenes."
	_on_link_fired(self, "say", [line_eval, 8.0], int(round(6.5 * Engine.iterations_per_second)))
	_on_link_fired(self, "say", [line_reprimand, 8.5], int(round(13.5 * Engine.iterations_per_second)))


func is_work_order_completed() -> bool:
	return _order_completed


func return_to_ring_hub() -> void:
	if not is_inside_tree():
		return
	var target_scene := "res://core_v2/levels/RingHub_Level.tscn"
	var scene_mgr = get_node_or_null("/root/SceneManager")
	if scene_mgr != null and scene_mgr.has_method("goto_scene"):
		scene_mgr.goto_scene(target_scene, {"preserve_player_state": false})
	else:
		get_tree().change_scene(target_scene)


func _disable_shadow_casting(root: Node) -> void:
	var stack := [root]
	while not stack.empty():
		var current: Node = stack.pop_back()
		if current is GeometryInstance:
			(current as GeometryInstance).cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		for child in current.get_children():
			stack.push_back(child)


func _calc_transform(item: Dictionary) -> Transform:
	var rot := _vec(item.get("rot", [0, 0, 0]))
	return Transform(
		Basis(Vector3(deg2rad(rot.x), deg2rad(rot.y), deg2rad(rot.z))),
		_vec(item.get("pos", [0, 0, 0])))


func _place(node: Spatial, item: Dictionary) -> void:
	node.transform = _calc_transform(item)


# Rearma las piezas, bisagras y controles de una estacion (o de todo el nivel si station_id <= 0).
func reset_station(station_id: int = 0) -> void:
	_station_resets += 1
	var target_nodes := []
	for node in _items.values():
		if not is_instance_valid(node) or not node.has_meta("layout_item"):
			continue
		var item: Dictionary = node.get_meta("layout_item")
		var item_station := int(item.get("station", 0))
		if station_id <= 0 or item_station == station_id:
			target_nodes.append(node)
	# Cancelar links pendientes dirigidos a nodos de esta estacion.
	var i := _pending.size() - 1
	while i >= 0:
		var entry: Array = _pending[i]
		var source: Node = get_item(str(entry[5])) if entry.size() > 5 else null
		if station_id <= 0 or target_nodes.has(entry[1]) or (entry[1] == self and target_nodes.has(source)):
			_pending.remove(i)
		i -= 1
	# Soltar cualquier pieza de esta estacion que el jugador tenga agarrada con el Multi-Tool
	# y eliminar proyectiles de gloo adheridos a piezas de esta estacion.
	if is_inside_tree():
		for player in get_tree().get_nodes_in_group("player"):
			if player != null and "multi_tool" in player and is_instance_valid(player.multi_tool):
				var mt = player.multi_tool
				if mt.has_method("get_grabbed_body") and target_nodes.has(mt.get_grabbed_body()):
					mt.release_grab()
		for blob in get_tree().get_nodes_in_group("gloo_blob"):
			if not is_instance_valid(blob):
				continue
			var anchor = blob.get("_anchor_collider")
			if target_nodes.has(anchor) or target_nodes.has(blob.get_parent()):
				if blob.has_method("fade_out"):
					blob.fade_out()
				else:
					blob.queue_free()
	# 1. Resetear piezas y escenas interactuables a su pose/estado original.
	var hinges := []
	for node in target_nodes:
		var item: Dictionary = node.get_meta("layout_item")
		var t := _calc_transform(item)
		var item_type := str(item.get("type", ""))
		if item_type == "part" and node.has_method("reset_to_layout"):
			node.reset_to_layout(item, t)
		elif item_type == "hinge":
			node.transform = t
			hinges.append(node)
		elif item_type == "scene":
			node.transform = t
			if node.has_method("set_active") and "is_active" in node and bool(node.is_active):
				node.set_active(false, true)
		else:
			if node is Spatial:
				(node as Spatial).transform = t
	for c in _conduits:
		if target_nodes.has(c.get("to", null)):
			c["active_ticks"] = 0
	# 2. Re-conectar bisagras despues de que los cuerpos esten en su pose inicial.
	for hinge in hinges:
		var item: Dictionary = hinge.get_meta("layout_item")
		var motor: Dictionary = item.get("motor", {})
		hinge.set_active(bool(motor.get("on", false)), true)
		if hinge.has_method("attach"):
			hinge.attach()


func get_station_resets() -> int:
	return _station_resets


func get_elapsed_seconds() -> float:
	return float(_elapsed_ticks) / float(max(1, Engine.iterations_per_second))


func _connect_link(link: Dictionary) -> void:
	var from_name := str(link.get("from", ""))
	var from := get_item(from_name)
	var to: Node = self if str(link.get("to", "")) == "@level" else get_item(str(link.get("to", "")))
	var sig := str(link.get("signal", "activated"))
	var method := str(link.get("method", "set_active"))
	if from == null or to == null or not from.has_signal(sig) or not to.has_method(method):
		push_error("MachineLevel: link invalido " + str(link))
		return
	# Las senales de los interactuables no llevan argumentos: se liga el valor aca.
	var args: Array = link.get("args", [])
	var delay_ticks := int(round(float(link.get("delay", 0.0)) * Engine.iterations_per_second))
	var key := from_name + ":" + sig
	if not _signal_links.has(key):
		_signal_links[key] = []
		from.connect(sig, self, "_on_signal_emitted", [key])
	_signal_links[key].append([to, method, args, delay_ticks, from_name])
	if to != self and from is Spatial and to is Spatial and sig == "activated" and bool(link.get("conduit", true)):
		_make_conduit(from as Spatial, to as Spatial, from_name)


func _on_signal_emitted(key: String) -> void:
	var list: Array = _signal_links.get(key, [])
	for entry in list:
		_on_link_fired(entry[0], entry[1], entry[2], entry[3], str(entry[4]) if entry.size() > 4 else "")


func _on_link_fired(to: Node, method: String, args: Array, delay_ticks: int, from_name: String = "") -> void:
	if delay_ticks <= 0:
		if is_instance_valid(to):
			to.callv(method, args)
			_mark_conduit_fired(to)
		return
	_pending.append([delay_ticks, to, method, args, delay_ticks, from_name])
	set_physics_process(true)


func _mark_conduit_fired(to_node: Node) -> void:
	var hold := int(round(2.5 * Engine.iterations_per_second))
	for c in _conduits:
		if c.get("to", null) == to_node:
			c["active_ticks"] = hold


# Los retardos se cuentan en ticks de fisica (no Timer): determinista bajo replay.
func _physics_process(_delta: float) -> void:
	if not _order_completed:
		_elapsed_ticks += 1
	if _void_kill_cooldown_ticks > 0:
		_void_kill_cooldown_ticks -= 1
	if _subtitle_hold_ticks > 0:
		_subtitle_hold_ticks -= 1
		if _subtitle_hold_ticks <= 0 and not _subtitle_queue.empty():
			var next_sub: Array = _subtitle_queue.pop_front()
			_show_subtitle_now(str(next_sub[0]), float(next_sub[1]))
	if is_inside_tree():
		var parent_node := get_parent()
		for player in get_tree().get_nodes_in_group("player"):
			if player == null or not is_instance_valid(player):
				continue
			if enable_player_multi_tool and "multi_tool" in player and player.multi_tool == null and player.has_method("set_multi_tool_enabled"):
				player.set_multi_tool_enabled(true)
			if parent_node != null and parent_node.is_a_parent_of(player) and player is Spatial:
				var py: float = (player as Spatial).global_transform.origin.y
				if py < -13.5 and _void_kill_cooldown_ticks <= 0:
					_void_kill_cooldown_ticks = 240
					_trigger_void_death(player)
	var min_mechanical_ticks := -1
	var i := _pending.size() - 1
	while i >= 0:
		var entry: Array = _pending[i]
		entry[0] -= 1
		if entry[1] != self and entry[0] > 0:
			if min_mechanical_ticks < 0 or int(entry[0]) < min_mechanical_ticks:
				min_mechanical_ticks = int(entry[0])
		if entry[0] <= 0:
			var target_node: Node = entry[1]
			_pending.remove(i)
			if is_instance_valid(target_node):
				target_node.callv(entry[2], entry[3])
				_mark_conduit_fired(target_node)
		i -= 1
	_update_diegetic_feedback(min_mechanical_ticks)


func _update_diegetic_feedback(min_mechanical_ticks: int) -> void:
	var ips := float(max(1, Engine.iterations_per_second))
	if min_mechanical_ticks > 0:
		var sec_left := int(ceil(float(min_mechanical_ticks) / ips))
		if sec_left != _last_countdown_sec and sec_left >= 1 and sec_left <= 5:
			_last_countdown_sec = sec_left
			var subtitles := get_node_or_null("/root/SubtitlesOverlayManager")
			if subtitles != null and subtitles.has_method("show_hint"):
				subtitles.show_hint("⏱ LIBERACIÓN MECÁNICA EN %d s..." % sec_left, Color(1.0, 0.78, 0.25), 0.95)
	else:
		_last_countdown_sec = -1
	for c in _conduits:
		var mat: SpatialMaterial = c.get("mat", null)
		if mat == null:
			continue
		var to_node: Node = c.get("to", null)
		var is_counting := false
		for entry in _pending:
			if entry[1] == to_node:
				is_counting = true
				break
		var active_ticks := int(c.get("active_ticks", 0))
		if active_ticks > 0:
			c["active_ticks"] = active_ticks - 1
		if is_counting:
			var pulse := 0.5 + 0.5 * sin(float(_elapsed_ticks) * 0.45)
			var col := Color("#ffaa00").linear_interpolate(Color("#ff3300"), pulse)
			mat.albedo_color = col
			mat.emission = col
			mat.emission_energy = 1.6 + pulse * 1.6
		elif active_ticks > 0:
			var col_ok := Color("#00f5d4")
			mat.albedo_color = col_ok
			mat.emission = col_ok
			mat.emission_energy = 2.2
		else:
			var col_idle := Color("#d96b1f")
			mat.albedo_color = col_idle
			mat.emission = col_idle
			mat.emission_energy = 0.95


func _trigger_void_death(player: Node) -> void:
	var sm = get_node_or_null("/root/SessionManager")
	if sm != null and bool(sm.get("is_respawning")):
		return
	var kill_floor: Node = _items.get("KillFloor", null)
	var ts = get_node_or_null("/root/SessionManager/TeleportSystem")
	if ts == null and is_inside_tree():
		ts = get_tree().get_root().find_node("TeleportSystem", true, false)
	if kill_floor != null and is_instance_valid(kill_floor) and kill_floor.has_method("_on_zone_entered") and ts != null:
		kill_floor._on_zone_entered(player)
	elif ts != null and ts.has_method("_on_player_killed"):
		ts._on_player_killed()
	elif player is Spatial:
		var fallback_tf := Transform(Basis.IDENTITY, Vector3(0, 0.6, -2))
		if "initial_transform" in player:
			fallback_tf = player.initial_transform
		if player.has_method("teleport_to"):
			player.teleport_to(fallback_tf)
		else:
			(player as Spatial).global_transform = fallback_tf
		if "velocity" in player:
			player.velocity = Vector3.ZERO


func get_snapshot() -> Dictionary:
	var pending: Array = []
	for entry in _pending:
		var target: Node = entry[1]
		if not is_instance_valid(target):
			continue
		var target_name: String = "@level" if target == self else str(target.name)
		if target != self and get_item(target_name) != target:
			continue
		pending.append([int(entry[0]), target_name, str(entry[2]),
			(entry[3] as Array).duplicate(true), int(entry[4]), str(entry[5])])
	return {
		"pending": pending,
		"station_resets": _station_resets,
		"elapsed_ticks": _elapsed_ticks,
		"order_completed": _order_completed,
	}


func restore_snapshot(data: Dictionary) -> void:
	# Reemplazar, nunca fusionar: snapshots antiguos tampoco conservan eventos futuros.
	_pending.clear()
	for entry in data.get("pending", []):
		if not (entry is Array) or entry.size() != 6 or not (entry[3] is Array):
			continue
		var target_name: String = str(entry[1])
		var target: Node = self if target_name == "@level" else get_item(target_name)
		if not is_instance_valid(target) or not target.has_method(str(entry[2])):
			continue
		_pending.append([int(entry[0]), target, str(entry[2]),
			(entry[3] as Array).duplicate(true), int(entry[4]), str(entry[5])])
	_subtitle_queue.clear()
	_subtitle_hold_ticks = 0
	_last_countdown_sec = -1
	_void_kill_cooldown_ticks = 0
	for conduit in _conduits:
		conduit["active_ticks"] = 0
	_station_resets = int(data.get("station_resets", _station_resets))
	_elapsed_ticks = int(data.get("elapsed_ticks", _elapsed_ticks))
	_order_completed = bool(data.get("order_completed", _order_completed))


static func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
