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
#
# Emitida por say(): avisa que Odisea está hablando (texto, duración en segundos).
# La consume _show_subtitle_now() para invocar ProgrammerHoloNPC.summon() (NPC-holograma).
signal said(text, duration)

const MachinePart = preload("res://core_v2/props/machines/MachinePart.gd")
const MachineHinge = preload("res://core_v2/props/machines/MachineHinge.gd")
const TriggerScript = preload("res://core_v2/props/machines/MachineTrigger.gd")
const ProgrammerHoloNPC = preload("res://core_v2/actors/ProgrammerHoloNPC.gd")
const LedgeV2 = preload("res://core_v2/components/LedgeV2.gd")
const SignagePanelScene = preload("res://core_v2/props/signage/SignagePanel.tscn")
const TubeBuilder = preload("res://core_v2/systems/pipe/TubeBuilder.gd")
const DiamondPlateTex = preload("res://materials/diamondplate.png")
const DiamondPlateSpec = preload("res://materials/diamondplate_spec.png")
const IndFloorTex = preload("res://textures/kenney_prototype_textures/dark/texture_08.png")
const HazardMat = preload("res://materials/diamondPlateAluminum/seam_hazard_stripes.tres")

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
var _ringhub_return_state: Dictionary = {}


func _ready() -> void:
	var scene_manager: Node = get_node_or_null("/root/SceneManager")
	if scene_manager != null:
		_ringhub_return_state = scene_manager._transition_params.get("ringhub_return_state", {}).duplicate(true)
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
				if str(item.get("name", "")) == "BayShell":
					return _build_fallback_bay_shell()
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
			if str(item.get("name", "")) == "BayShell":
				_enhance_bay_shell_materials(inst)
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
	var is_emissive := bool(item.get("emissive", false))
	var has_custom_color := item.has("color")
	mat.albedo_color = Color(str(item.get("color", "#4a525d")))
	mat.roughness = 0.62 if not is_emissive else 0.45
	mat.metallic = 0.45 if not is_emissive else 0.15
	if not is_emissive:
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 6.0
		if has_custom_color:
			mat.albedo_texture = DiamondPlateTex
			mat.metallic_texture = DiamondPlateSpec
			mat.normal_enabled = true
			mat.normal_texture = DiamondPlateTex
			mat.normal_scale = 0.55
			mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
		else:
			mat.albedo_texture = IndFloorTex
			mat.normal_enabled = true
			mat.normal_texture = DiamondPlateTex
			mat.normal_scale = 0.35
			mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	if is_emissive:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy = float(item.get("emission_energy", 0.85))
	mesh.material_override = mat
	body.add_child(mesh)
	# Si es una plataforma caminable ancha (no tira emisiva), agregar moldura perimetral y franja de peligro en bordes Z.
	if not is_emissive and size.x >= 5.5 and size.z >= 2.0 and size.y >= 0.8:
		var trim_mat := SpatialMaterial.new()
		trim_mat.albedo_color = Color(0.18, 0.2, 0.23)
		trim_mat.metallic = 0.82
		trim_mat.roughness = 0.35
		for sx in [-1.0, 1.0]:
			var side_beam := MeshInstance.new()
			var sc := CubeMesh.new()
			sc.size = Vector3(0.14, 0.22, size.z + 0.04)
			side_beam.mesh = sc
			side_beam.material_override = trim_mat
			side_beam.translation = Vector3(sx * (size.x * 0.5 + 0.04), size.y * 0.5 - 0.11, 0)
			body.add_child(side_beam)
		for sz in [-1.0, 1.0]:
			var lip := MeshInstance.new()
			var lc := CubeMesh.new()
			lc.size = Vector3(size.x, 0.04, 0.14)
			lip.mesh = lc
			lip.material_override = HazardMat
			lip.translation = Vector3(0, size.y * 0.5 - 0.015, sz * (size.z * 0.5 - 0.07))
			body.add_child(lip)
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
	if item.has("color"):
		# Un cartel puede declarar "color" para sobrescribir el preset (p. ej. un
		# color custom de contraste). Se respeta el resto de campos del layout.
		sign_node.set("custom_color", Color(str(item["color"])))
		sign_node.set("color_preset", "custom")
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
	if from_node.has_node("CableAnchor"):
		var anchor := from_node.get_node("CableAnchor") as Spatial
		if anchor != null:
			p_a = from_node.transform.xform(anchor.transform.origin)
	var p_b: Vector3 = to_node.transform.origin
	var dist := p_a.distance_to(p_b)
	if dist < 0.25 or dist > 35.0:
		return
	var horiz_dist := Vector2(p_b.x - p_a.x, p_b.z - p_a.z).length()
	var sag_depth := clamp(horiz_dist * 0.18 + dist * 0.06, 0.35, 2.2)
	var curve := Curve3D.new()
	var samples := 16
	var cosh_1 := 0.5 * (exp(1.2) + exp(-1.2))
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var u := (t - 0.5) * 2.0
		var cosh_u := 0.5 * (exp(1.2 * u) + exp(-1.2 * u))
		var sag_profile := (cosh_1 - cosh_u) / max(0.0001, cosh_1 - 1.0)
		var pt := p_a.linear_interpolate(p_b, t)
		pt.y -= sag_depth * sag_profile
		curve.add_point(pt)
	var mesh_inst := MeshInstance.new()
	mesh_inst.name = "Conduit_%s_%s" % [from_name, to_node.name]
	var tube_mesh: ArrayMesh = TubeBuilder.generate_tube_mesh(curve, 0.032, 8, true, 1.0, 0.0)
	if tube_mesh != null:
		mesh_inst.mesh = tube_mesh
	else:
		var fallback := CubeMesh.new()
		fallback.size = Vector3(0.045, 0.045, dist)
		mesh_inst.mesh = fallback
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color("#d96b1f")
	mat.metallic = 0.35
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color("#d96b1f")
	mat.emission_energy = 1.15
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var socket_mat := SpatialMaterial.new()
	socket_mat.albedo_color = Color(0.16, 0.18, 0.21)
	socket_mat.metallic = 0.85
	socket_mat.roughness = 0.32
	for endpoint in [p_a, p_b]:
		var sock := MeshInstance.new()
		var sc := SphereMesh.new()
		sc.radius = 0.065
		sc.height = 0.13
		sc.radial_segments = 10
		sc.rings = 5
		sock.mesh = sc
		sock.material_override = socket_mat
		sock.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		sock.translation = endpoint
		mesh_inst.add_child(sock)
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
	emit_signal("said", text, effective_duration)
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
	if is_inside_tree():
		ProgrammerHoloNPC.summon(get_tree(), duration)
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
	if not model.objective_ids().has("order_0001"):
		model.add_objective("order_0001", "Orden 0001: Restablecer flujo en Bahía 3", model.OBJ_ACTIVE)
	elif model.objective_state("order_0001") != model.OBJ_DONE:
		model.set_objective_state("order_0001", model.OBJ_ACTIVE)
	if suit_screen.has_method("notify_state_changed"):
		suit_screen.notify_state_changed()


func complete_work_order() -> void:
	if _order_completed:
		return
	var valve: Node = get_item("MasterFlowValve")
	if not is_instance_valid(valve) or not bool(valve.get("is_active")):
		var subtitles: Node = get_node_or_null("/root/SubtitlesOverlayManager")
		if subtitles != null and subtitles.has_method("show_hint"):
			subtitles.show_hint("Abra la Válvula Maestra para restablecer el flujo y cerrar la Orden 0001.", Color(1.0, 0.78, 0.25), 4.0)
		return
	_order_completed = true
	var elapsed_sec := int(round(get_elapsed_seconds()))
	var resets := get_station_resets()
	var suit_screen := _get_suit_screen()
	if suit_screen != null and suit_screen.has_method("ensure_model"):
		var model = suit_screen.ensure_model()
		if model != null:
			if not model.objective_ids().has("order_0001"):
				model.add_objective("order_0001", "Orden 0001: Restablecer flujo en Bahía 3", model.OBJ_DONE)
			else:
				model.complete_objective("order_0001")
			if not model.objective_ids().has("return_hub"):
				model.add_objective("return_hub", "Fin de la demo: puede retornar al anillo de criogenia", model.OBJ_ACTIVE)
			if suit_screen.has_method("notify_state_changed"):
				suit_screen.notify_state_changed()
	say("ODISEA: Supresión térmica activada. Caudal restablecido en Bahía 3. Orden de Trabajo 0001 cerrada.", 8.0)
	var line_ghost := "[INTERFERENCIA — FANTASMA DIGITAL]: ...lo lograste, Elías. Sabía que recordarías cómo... [SEÑAL ESTABILIZADA]"
	var line_eval := "ODISEA: Corrección de registro. Tiempo presupuestado: 240 s. Tiempo real: %d s. Rearmes: %d. Amonestación 0001 archivada." % [elapsed_sec, resets]
	_suppress_bay_fire()
	_on_link_fired(self, "say", [line_ghost, 7.5], int(round(6.5 * Engine.iterations_per_second)))
	_on_link_fired(self, "say", [line_eval, 8.5], int(round(13.5 * Engine.iterations_per_second)))


func is_work_order_completed() -> bool:
	return _order_completed


func return_to_ring_hub() -> void:
	if not is_inside_tree():
		return
	var target_scene := "res://core_v2/levels/RingHub_Level.tscn"
	var scene_mgr = get_node_or_null("/root/SceneManager")
	if scene_mgr != null and scene_mgr.has_method("goto_scene"):
		scene_mgr.goto_scene(target_scene, {
			"preserve_player_state": false,
			"wait_for_fade_out": true,
			"ringhub_return_state": _ringhub_return_state.duplicate(true),
			"state_data": {"player_snapshot": _ringhub_return_state.get("player_snapshot", {})}
		})
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


func _enhance_bay_shell_materials(root: Node) -> void:
	var upgraded := {}
	var stack := [root]
	while not stack.empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance:
			var mi := current as MeshInstance
			if mi.mesh != null:
				var surf_count := mi.mesh.get_surface_count()
				for s in range(surf_count):
					var base_mat: Material = mi.get_surface_material(s)
					if base_mat == null:
						base_mat = mi.mesh.surface_get_material(s)
					if base_mat is SpatialMaterial:
						var sm := base_mat as SpatialMaterial
						if sm.emission_enabled:
							continue
						if not upgraded.has(sm):
							var dup := sm.duplicate() as SpatialMaterial
							dup.uv1_triplanar = true
							dup.uv1_triplanar_sharpness = 4.0
							dup.albedo_texture = IndFloorTex
							dup.metallic_texture = DiamondPlateSpec
							dup.normal_enabled = true
							dup.normal_texture = DiamondPlateTex
							dup.normal_scale = 0.42
							dup.uv1_scale = Vector3(0.16, 0.16, 0.16)
							upgraded[sm] = dup
						mi.set_surface_material(s, upgraded[sm])
		for child in current.get_children():
			stack.push_back(child)


func _calc_transform(item: Dictionary) -> Transform:
	var rot := _vec(item.get("rot", [0, 0, 0]))
	return Transform(
		Basis(Vector3(deg2rad(rot.x), deg2rad(rot.y), deg2rad(rot.z))),
		_vec(item.get("pos", [0, 0, 0])))


# Escala pedida de un cartel en formato layout. _calc_transform arma solo rotacion y
# posicion, asi que el "scale" del item debe re-aplicarse DESPUES de asignar la transform:
# asignar node.transform lo pisa y el cartel quedaba en (1,1,1) pese a pedir p. ej. 1.6.
static func _sign_scale(item: Dictionary) -> Vector3:
	if not item.has("scale"):
		return Vector3.ONE
	var s = item["scale"]
	if s is Array and s.size() == 3:
		return _vec(s)
	var f := float(s)
	return Vector3(f, f, 1.0)


func _place(node: Spatial, item: Dictionary) -> void:
	node.transform = _calc_transform(item)
	if str(item.get("type", "")) == "sign":
		node.scale = _sign_scale(item)


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
		if station_id <= 0 or target_nodes.has(entry[1]) or (((entry[1] is Object and entry[1] == self) or (entry[1] is String and entry[1] == "@odisea")) and target_nodes.has(source)):
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
				_place(node as Spatial, item)
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


func _resolve_odisea_npc() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	for node in tree.get_nodes_in_group("programmer_holo_npc"):
		if is_instance_valid(node):
			return node
	return ProgrammerHoloNPC.summon(tree, 8.0)


func _call_odisea(method: String, args: Array) -> void:
	var npc := _resolve_odisea_npc()
	if not is_instance_valid(npc):
		return
	if npc.has_method(method):
		var converted := []
		for a in args:
			if a is Array and a.size() == 3 and (typeof(a[0]) == TYPE_REAL or typeof(a[0]) == TYPE_INT):
				converted.append(_vec(a))
			else:
				converted.append(a)
		npc.callv(method, converted)


func _suppress_bay_fire() -> void:
	var systems := []
	var by_name := get_item("BayFireSystem")
	if is_instance_valid(by_name):
		systems.append(by_name)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("fire_system"):
			if is_instance_valid(node) and not systems.has(node):
				systems.append(node)
	for fs in systems:
		if fs.has_method("set_active"):
			fs.call("set_active", false)
		elif fs.has_method("stop"):
			fs.call("stop")
		if "start_height" in fs and "fire_height" in fs:
			fs.set("fire_height", fs.get("start_height"))
			if fs.has_signal("fire_height_changed"):
				fs.emit_signal("fire_height_changed", fs.get("fire_height"))
		if fs.has_signal("fire_visuals_reset"):
			fs.emit_signal("fire_visuals_reset")


func _ensure_fire_safe_for_respawn(respawn_y: float) -> void:
	var systems := []
	var by_name := get_item("BayFireSystem")
	if is_instance_valid(by_name):
		systems.append(by_name)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("fire_system"):
			if is_instance_valid(node) and not systems.has(node):
				systems.append(node)
	for fs in systems:
		if fs.has_method("ensure_safe_for_respawn"):
			fs.call("ensure_safe_for_respawn", respawn_y)


func _connect_link(link: Dictionary) -> void:
	var from_name := str(link.get("from", ""))
	var from := get_item(from_name)
	var to_name := str(link.get("to", ""))
	var sig := str(link.get("signal", "activated"))
	var method := str(link.get("method", "set_active"))
	var args: Array = link.get("args", [])
	var delay_ticks := int(round(float(link.get("delay", 0.0)) * Engine.iterations_per_second))
	if to_name == "@odisea":
		if from == null or not from.has_signal(sig):
			push_error("MachineLevel: link invalido " + str(link))
			return
		var okey := from_name + ":" + sig
		if not _signal_links.has(okey):
			_signal_links[okey] = []
			from.connect(sig, self, "_on_signal_emitted", [okey])
		_signal_links[okey].append(["@odisea", method, args, delay_ticks, from_name])
		return
	var to: Node = self if to_name == "@level" else get_item(to_name)
	if from == null or to == null or not from.has_signal(sig) or not to.has_method(method):
		push_error("MachineLevel: link invalido " + str(link))
		return
	# Las senales de los interactuables no llevan argumentos: se liga el valor aca.
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


func _on_link_fired(to, method: String, args: Array, delay_ticks: int, from_name: String = "") -> void:
	if delay_ticks <= 0:
		if to is String and to == "@odisea":
			_call_odisea(method, args)
		elif to is Node and is_instance_valid(to):
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
			if parent_node != null and parent_node == get_tree().current_scene and parent_node.is_a_parent_of(player) and player is Spatial:
				var py: float = (player as Spatial).global_transform.origin.y
				if py < -13.5 and _void_kill_cooldown_ticks <= 0:
					_void_kill_cooldown_ticks = 240
					_trigger_void_death(player)
	var min_mechanical_ticks := -1
	var i := _pending.size() - 1
	while i >= 0:
		var entry: Array = _pending[i]
		entry[0] -= 1
		var is_narrative: bool = (entry[1] is Object and entry[1] == self) or (entry[1] is String and entry[1] == "@odisea")
		if not is_narrative and entry[0] > 0:
			if min_mechanical_ticks < 0 or int(entry[0]) < min_mechanical_ticks:
				min_mechanical_ticks = int(entry[0])
		if entry[0] <= 0:
			var target = entry[1]
			_pending.remove(i)
			if target is String and target == "@odisea":
				_call_odisea(str(entry[2]), entry[3])
			elif target is Node and is_instance_valid(target):
				target.callv(entry[2], entry[3])
				_mark_conduit_fired(target)
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
				subtitles.show_hint("⏱ SIGUIENTE ETAPA MECÁNICA EN %d s..." % sec_left, Color(1.0, 0.78, 0.25), 0.95)
	else:
		_last_countdown_sec = -1
	for c in _conduits:
		var mat: SpatialMaterial = c.get("mat", null)
		if mat == null:
			continue
		var to_node: Node = c.get("to", null)
		var is_counting := false
		for entry in _pending:
			if entry[1] is Object and entry[1] == to_node:
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
	var respawn_y := 0.6
	if player is Spatial and "initial_transform" in player:
		respawn_y = float(player.initial_transform.origin.y)
	var cm = get_node_or_null("/root/CheckpointManager")
	if cm != null and cm.has_method("get_active_checkpoint_position"):
		var cp_pos = cm.call("get_active_checkpoint_position")
		if cp_pos is Vector3:
			respawn_y = cp_pos.y
	_ensure_fire_safe_for_respawn(respawn_y)
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
		var target = entry[1]
		var target_name := ""
		if target is String and target == "@odisea":
			target_name = "@odisea"
		elif target is Node and is_instance_valid(target):
			target_name = "@level" if target == self else str(target.name)
			if target != self and get_item(target_name) != target:
				continue
		else:
			continue
		pending.append([int(entry[0]), target_name, str(entry[2]),
			(entry[3] as Array).duplicate(true), int(entry[4]), str(entry[5])])
	return {
		"pending": pending,
		"ringhub_return_state": _ringhub_return_state.duplicate(true),
		"station_resets": _station_resets,
		"elapsed_ticks": _elapsed_ticks,
		"order_completed": _order_completed,
	}


func restore_snapshot(data: Dictionary) -> void:
	_ringhub_return_state = data.get("ringhub_return_state", _ringhub_return_state).duplicate(true)
	# Reemplazar, nunca fusionar: snapshots antiguos tampoco conservan eventos futuros.
	_pending.clear()
	for entry in data.get("pending", []):
		if not (entry is Array) or entry.size() != 6 or not (entry[3] is Array):
			continue
		var target_name: String = str(entry[1])
		if target_name == "@odisea":
			_pending.append([int(entry[0]), "@odisea", str(entry[2]),
				(entry[3] as Array).duplicate(true), int(entry[4]), str(entry[5])])
			continue
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


func _build_fallback_bay_shell() -> Spatial:
	# Cascaron monumental procedural cuando build/machine_bay/bay_shell.glb no existe en disco.
	var shell := Spatial.new()
	shell.name = "BayShellFallback"
	var wall_mat := SpatialMaterial.new()
	wall_mat.albedo_color = Color("#1d232b")
	wall_mat.roughness = 0.85
	wall_mat.metallic = 0.35
	var rib_mat := SpatialMaterial.new()
	rib_mat.albedo_color = Color("#2d3642")
	rib_mat.roughness = 0.72
	rib_mat.metallic = 0.55
	var strip_mat := SpatialMaterial.new()
	strip_mat.albedo_color = Color(0.22, 0.86, 1.0, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.22, 0.86, 1.0, 1.0)
	strip_mat.emission_energy = 1.6

	var specs := [
		["WallLeft", Vector3(-22.4, 8.0, 71.0), Vector3(0.8, 68.0, 168.0), wall_mat],
		["WallRight", Vector3(22.4, 8.0, 71.0), Vector3(0.8, 68.0, 168.0), wall_mat],
		["WallEntry", Vector3(0.0, 8.0, -12.4), Vector3(45.6, 68.0, 0.8), wall_mat],
		["WallBack", Vector3(0.0, 8.0, 154.4), Vector3(45.6, 68.0, 0.8), wall_mat],
		["Roof", Vector3(0.0, 41.5, 71.0), Vector3(45.6, 1.0, 168.0), wall_mat],
		["StripLeft", Vector3(-21.8, 37.5, 71.0), Vector3(0.16, 0.28, 162.0), strip_mat],
		["StripRight", Vector3(21.8, 37.5, 71.0), Vector3(0.16, 0.28, 162.0), strip_mat],
	]
	for spec in specs:
		_add_shell_box(shell, str(spec[0]), spec[1], spec[2], spec[3])

	var z_pos: float = -4.0
	var idx: int = 0
	while z_pos <= 148.0:
		_add_shell_box(shell, "RibL_%d" % idx, Vector3(-21.4, 15.0, z_pos), Vector3(1.2, 54.0, 0.9), rib_mat)
		_add_shell_box(shell, "RibR_%d" % idx, Vector3(21.4, 15.0, z_pos), Vector3(1.2, 54.0, 0.9), rib_mat)
		_add_shell_box(shell, "RibTop_%d" % idx, Vector3(0.0, 40.2, z_pos), Vector3(44.0, 1.2, 0.9), rib_mat)
		z_pos += 14.0
		idx += 1
	return shell


func _add_shell_box(parent: Spatial, box_name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance.new()
	mi.name = box_name
	var cube := CubeMesh.new()
	cube.size = size
	mi.mesh = cube
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.transform.origin = pos
	parent.add_child(mi)
