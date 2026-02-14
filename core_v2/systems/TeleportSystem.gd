extends Node
class_name TeleportSystem

# Coordina el teletransporte del jugador y la cámara.
# Debe ser conectado al PlayerControllerV2 y escuchar input.

var player_controller = null
var camera_controller = null
var initial_spawn_transform = null # Cached absolute initial spawn transform for the scene

func _ready():
	# Si player_controller no está asignado o ha sido liberado, buscarlo ahora
	if not is_instance_valid(player_controller):
		var pilot = get_tree().get_root().find_node("Pilot", true, false)
		player_controller = pilot
		# Cache the scene's original player spawn transform (only once)
		if player_controller and initial_spawn_transform == null:
			initial_spawn_transform = player_controller.global_transform
			# If no checkpoint 'last' exists for this scene, persist this initial spawn as the 'last' checkpoint
			var persistence_manager = get_node_or_null("/root/PersistenceManager")
			if persistence_manager and persistence_manager.has_method("get_checkpoint_resource"):
				var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
				var checkpoint_res = persistence_manager.get_checkpoint_resource(scene_path)
				if checkpoint_res and not ("last" in checkpoint_res.slots):
					var cp = {
						"transform": initial_spawn_transform,
						"yaw": player_controller.get("yaw") if player_controller and "yaw" in player_controller else 0.0,
						"pitch": player_controller.get("pitch") if player_controller and "pitch" in player_controller else 0.0
					}
					checkpoint_res.slots["last"] = cp
					checkpoint_res.property_list_changed_notify()
					if persistence_manager.has_method("save_checkpoint_resource"):
						persistence_manager.save_checkpoint_resource(scene_path)
		
	if not camera_controller and player_controller:
		var cam_rig = player_controller.get_node_or_null("CameraRig")
		camera_controller = cam_rig

func teleport_to(transform: Transform):
	if player_controller:
		print("[TeleportSystem] Llamando player_controller.teleport_to")
		player_controller.teleport_to(transform)
	else:
		print("[TeleportSystem] player_controller es null, no se puede teletransportar")
	if camera_controller and camera_controller != player_controller:
		camera_controller.global_transform = transform


# Atajos de teclado: trackback (Backspace) y reset

func _input(event):
	if _any_control_has_focus(get_tree().root):
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_BACKSPACE:
		if _any_line_edit_has_focus(get_tree().root):
			return
	if _is_ui_focus_active() or _is_terminal_ui_active():
		return

	# Atajos de input actions
	if event.is_action_pressed("trackback") and _can_handle_shortcut_key(event):
		print("[TeleportSystem] Atajo 'trackback' presionado: respawn en último checkpoint (como morir)")
		_on_player_killed()
		get_tree().set_input_as_handled()
		return
	elif event.is_action_pressed("reset") and _can_handle_shortcut_key(event):
		print("[TeleportSystem] Atajo 'reset' presionado: respawn en spawn point o 0,0,0")
		_respawn_at_spawn_or_zero()
		get_tree().set_input_as_handled()
		return

	# Teclas directas [1-9] y SHIFT+[1-9] para slots
	if event is InputEventKey and not event.echo:
		var key_num = -1
		# Godot keycodes: KEY_1 = 49 ... KEY_9 = 57
		if event.scancode >= KEY_1 and event.scancode <= KEY_9:
			key_num = event.scancode - KEY_0 # 1..9
		if key_num >= 1 and key_num <= 9:
			var is_save_shortcut = event.control or event.command
			var has_other_modifiers = event.shift or event.alt or event.meta
			if has_other_modifiers and not is_save_shortcut:
				return

			var persistence_manager = get_node_or_null("/root/PersistenceManager")
			var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
			if persistence_manager and persistence_manager.has_method("get_checkpoint_resource"):
				var checkpoint_res = persistence_manager.get_checkpoint_resource(scene_path)
				if is_save_shortcut:
					# CTRL/CMD+[1-9]: Guardar posición y ángulo en slot
					if not is_instance_valid(player_controller):
						var pilot = get_tree().get_root().find_node("Pilot", true, false)
						if is_instance_valid(pilot):
							player_controller = pilot
					if checkpoint_res:
						if not is_instance_valid(player_controller):
							return
						var checkpoint_data = {
							"transform": player_controller.global_transform,
							"yaw": player_controller.get("yaw") if "yaw" in player_controller else 0.0,
							"pitch": player_controller.get("pitch") if "pitch" in player_controller else 0.0
						}
						checkpoint_res.slots[str(key_num)] = checkpoint_data
						checkpoint_res.property_list_changed_notify()
						print("[TeleportSystem] Guardado slot ", key_num, ": ", checkpoint_data)
						if persistence_manager.has_method("save_checkpoint_resource"):
							persistence_manager.save_checkpoint_resource(scene_path)
							print("[TeleportSystem] Checkpoint persistido en disco (slot ", key_num, ")")
						get_tree().set_input_as_handled()
				elif not has_other_modifiers:
					# [1-9]: Teletransportar a slot
					if checkpoint_res and str(key_num) in checkpoint_res.slots:
						var slot = checkpoint_res.slots[str(key_num)]
						var t = slot.get("transform", null) if typeof(slot) == TYPE_DICTIONARY else slot
						var yaw = slot.get("yaw", null) if typeof(slot) == TYPE_DICTIONARY else null
						var pitch = slot.get("pitch", null) if typeof(slot) == TYPE_DICTIONARY else null
						print("[TeleportSystem] Teleport a slot ", key_num, ": ", t)
						teleport_to(t)
						if yaw != null and "yaw" in player_controller:
							player_controller.yaw = yaw
							if "yaw_deg" in player_controller:
								player_controller.yaw_deg = rad2deg(yaw)
						if pitch != null and "pitch" in player_controller:
							player_controller.pitch = pitch
							if "pitch_deg" in player_controller:
								player_controller.pitch_deg = rad2deg(pitch)
						get_tree().set_input_as_handled()

func _is_ui_focus_active() -> bool:
	var root = get_tree().root
	if root == null:
		return false
	return _viewport_has_ui_focus(root)

func _viewport_has_ui_focus(vp: Viewport) -> bool:
	if vp == null:
		return false
	for child in vp.get_children():
		if child is Control and _control_tree_has_focus(child):
			return true
		if child is Viewport and _viewport_has_ui_focus(child):
			return true
	return false

func _control_tree_has_focus(node: Control) -> bool:
	if node == null:
		return false
	if node.visible and node.has_focus():
		return true
	for child in node.get_children():
		if child is Control and _control_tree_has_focus(child):
			return true
	return false

func _is_terminal_ui_active() -> bool:
	var root = get_tree().current_scene
	if root == null:
		return false
	return _node_tree_has_terminal_ui_active(root)

func _node_tree_has_terminal_ui_active(node: Node) -> bool:
	if node == null:
		return false
	if node.has_method("is_ui_interactive"):
		if bool(node.call("is_ui_interactive")):
			return true
	for child in node.get_children():
		if _node_tree_has_terminal_ui_active(child):
			return true
	return false

func _can_handle_shortcut_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return true
	var key = event as InputEventKey
	if key.echo:
		return false
	if key.control or key.command or key.alt or key.meta:
		return false
	return true

func _any_line_edit_has_focus(node: Node) -> bool:
	if node == null:
		return false
	if node is LineEdit and (node as LineEdit).has_focus():
		return true
	for child in node.get_children():
		if _any_line_edit_has_focus(child):
			return true
	return false

func _any_control_has_focus(node: Node) -> bool:
	if node == null:
		return false
	if node is Control and (node as Control).has_focus():
		return true
	for child in node.get_children():
		if _any_control_has_focus(child):
			return true
	return false

# Respawn forzado en el spawn point o 0,0,0
func _respawn_at_spawn_or_zero():
	# Activar flag de respawn para que los triggers no ejecuten scripts
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		session_mgr.is_respawning = true
	
	# Buscar player_controller si es null o inválido
	if not is_instance_valid(player_controller):
		var pilot = get_tree().get_root().find_node("Pilot", true, false)
		if is_instance_valid(pilot):
			player_controller = pilot
			print("[TeleportSystem] Player_controller encontrado y asignado en _respawn_at_spawn_or_zero:", player_controller)
		else:
			print("[TeleportSystem] No se pudo encontrar Pilot en el árbol en _respawn_at_spawn_or_zero")
	
	var target_transform = null
	var target_yaw = null
	var target_pitch = null
	# Usar el spawn inicial absoluto cached si existe, si no usar player_controller.initial_transform
	if initial_spawn_transform != null:
		target_transform = initial_spawn_transform
		print("[TeleportSystem] Reset usando cached initial_spawn_transform.")
	elif player_controller and "initial_transform" in player_controller:
		target_transform = player_controller.initial_transform
		print("[TeleportSystem] Reset usando posición inicial del player (player_controller.initial_transform).")
	else:
		target_transform = Transform()
		print("[TeleportSystem] Reset usando Transform.ZERO.")
	# Reinstanciar Pilot
	if player_controller and player_controller.is_inside_tree():
		var parent = player_controller.get_parent()
		var old_input_provider = player_controller.input_provider if "input_provider" in player_controller else null
		player_controller.queue_free()
		yield (get_tree(), "idle_frame")
		var pilot_scene = preload("res://core_v2/actors/Pilot_v2.tscn")
		var new_pilot = pilot_scene.instance()
		parent.add_child(new_pilot)
		yield (get_tree(), "idle_frame")
		if new_pilot.has_method("full_reset"):
			new_pilot.full_reset()
		new_pilot.global_transform = target_transform
		new_pilot.initial_transform = target_transform
		yield (get_tree(), "physics_frame")
		if new_pilot.has_method("set_external_velocity"):
			new_pilot.set_external_velocity(Vector3.ZERO)
		new_pilot.velocity = Vector3.ZERO
		if target_yaw != null:
			new_pilot.yaw = target_yaw
			new_pilot.yaw_deg = rad2deg(target_yaw)
		if target_pitch != null:
			new_pilot.pitch = target_pitch
			new_pilot.pitch_deg = rad2deg(target_pitch)
		# Refuerza input provider tras respawn
		if old_input_provider and is_instance_valid(old_input_provider):
			new_pilot.input_provider = old_input_provider
		if new_pilot.has_method("ensure_input_provider"):
			new_pilot.ensure_input_provider()
		player_controller = new_pilot
		# Ensure SessionManager knows about the new player instance (so recording/input overrides keep working)
		var sm = get_node_or_null("/root/SessionManager")
		if sm:
			if sm.has_method("_find_player"):
				sm._find_player()
			else:
				sm.player = new_pilot
			# If we are currently recording or replaying, mark the new pilot as externally-controlled
			if sm.is_recording or sm.is_replaying or sm.get("_is_waiting_for_respawn_validation"):
				new_pilot.is_replay_mode = true
			# Ensure the pilot has an input provider so external_input is consumed safely
			if new_pilot.has_method("ensure_input_provider"):
				new_pilot.ensure_input_provider()
			print("[TeleportSystem] SessionManager player refreshed: ", sm.player)
			# Debug: dump SessionManager recording state and current OYS override
			var cur_override = null
			if sm.has_method("get"):
				cur_override = sm.get("_oys_input_override")
			print("[TeleportSystem] SessionManager state: is_recording=", sm.is_recording, " is_replaying=", sm.is_replaying, " _oys_input_override=", cur_override)
			# If the session's OYS override exists but only contains no-op input (zeros),
			# clear it so subsequent OYS commands can post fresh inputs after respawn.
			if sm.has_method("get") and sm.get("_oys_input_override"):
				var od_check = sm.get("_oys_input_override")
				var only_noop = true
				if od_check.has("move_vec"):
					var mv = od_check.get("move_vec")
					if typeof(mv) == TYPE_ARRAY and (mv.size() >= 2) and (float(mv[0]) != 0.0 or float(mv[1]) != 0.0):
						only_noop = false
				if od_check.has("jump") and od_check.get("jump"):
					only_noop = false
				if od_check.has("interact") and od_check.get("interact"):
					only_noop = false
				if only_noop:
					sm.set("_oys_input_override", {})
					print("[TeleportSystem] Cleared noop OYS override after respawn")
					# Debug: confirm cleared
					print("[TeleportSystem] SessionManager _oys_input_override now=", sm.get("_oys_input_override"))
			# Let one physics frame run so the new pilot can process input and areas
			yield (get_tree(), "physics_frame")
		var cam_rig = new_pilot.get_node_or_null("CameraRig")
		if cam_rig:
			camera_controller = cam_rig
		print("[TeleportSystem] Nuevo Pilot instanciado por reset. enforced transform and reset state:", new_pilot.initial_transform)
		# Desactivar flag de respawn después de algunos frames para permitir que las zonas detecten al player
		call_deferred("_clear_respawn_flag")
	else:
		print("[TeleportSystem] No se pudo reinstanciar Pilot (reset)")
		_clear_respawn_flag()

func _on_player_killed():
	print("[TeleportSystem] _on_player_killed ejecutado! (señal recibida)")
	print("[TeleportSystem] self:", self, " path=", get_path())
	var pc_path = player_controller.get_path() if is_instance_valid(player_controller) else "null"
	print("[TeleportSystem] player_controller:", player_controller, " path=", pc_path)
	
	# Activar flag de respawn para que los triggers no ejecuten scripts
	var session_mgr = get_node_or_null("/root/SessionManager")
	if session_mgr:
		session_mgr.is_respawning = true
	
	# Buscar player_controller si es null o inválido
	if not is_instance_valid(player_controller):
		var pilot = get_tree().get_root().find_node("Pilot", true, false)
		if is_instance_valid(pilot):
			player_controller = pilot
			print("[TeleportSystem] Player_controller encontrado y asignado:", player_controller)
		else:
			print("[TeleportSystem] No se pudo encontrar Pilot en el árbol")
	
	if is_instance_valid(player_controller):
		print("[TeleportSystem] player_controller.global_transform=", player_controller.global_transform)
		if "initial_transform" in player_controller:
			print("[TeleportSystem] player_controller.initial_transform=", player_controller.initial_transform)
		else:
			print("[TeleportSystem] player_controller.initial_transform=MISSING")
	else:
		printerr("[TeleportSystem] ERROR: player_controller is invalid/freed in _on_player_killed!")

	# 1. Intentar cargar el último checkpoint guardado (PersistenceManager)
	var persistence_manager = get_node_or_null("/root/PersistenceManager")
	print("[TeleportSystem] Buscando PersistenceManager en /root/PersistenceManager:", persistence_manager)
	var checkpoint_res = null
	var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
	if persistence_manager and persistence_manager.has_method("get_checkpoint_resource"):
		checkpoint_res = persistence_manager.get_checkpoint_resource(scene_path)
		print("[TeleportSystem] CheckpointResource para escena:", checkpoint_res)

	var target_transform = null
	var target_yaw = null
	var target_pitch = null
	# 2. Si hay checkpoint en slot 'last', usarlo
	if checkpoint_res and "last" in checkpoint_res.slots:
		var slot = checkpoint_res.slots["last"]
		if typeof(slot) == TYPE_DICTIONARY:
			target_transform = slot.get("transform", null)
			target_yaw = slot.get("yaw", null)
			target_pitch = slot.get("pitch", null)
		else:
			target_transform = slot
		print("[TeleportSystem] Respawn usando último checkpoint registrado.")
	# 3. Si hay SpawnPointV2 en la escena, usarlo
	if not target_transform:
		var spawn = get_tree().current_scene.find_node("SpawnPointV2", true, false) if get_tree().current_scene else null
		print("[TeleportSystem] Buscando SpawnPointV2:", spawn)
		if spawn:
			target_transform = spawn.global_transform
			print("[TeleportSystem] Respawn usando SpawnPointV2.")
	# 4. Si no hay nada, usar el spawn inicial absoluto cacheado o la posición inicial del player (fallback)
	if not target_transform:
		if initial_spawn_transform != null:
			target_transform = initial_spawn_transform
			target_yaw = 0
			target_pitch = 0
			print("[TeleportSystem] Respawn usando cached initial_spawn_transform.")
		elif is_instance_valid(player_controller) and "initial_transform" in player_controller:
			target_transform = player_controller.initial_transform
			target_yaw = 0 # Asumir yaw inicial 0, o si hay, pero por ahora 0
			target_pitch = 0
			print("[TeleportSystem] Respawn usando posición inicial del player.")
		elif player_controller:
			printerr("[TeleportSystem] ERROR: player_controller is not valid when accessing initial_transform!")
		else:
			target_transform = Transform()
			print("[TeleportSystem] Respawn usando Transform.ZERO.")

	print("[TeleportSystem] Reinstanciando Pilot en:", target_transform)
	# Eliminar el Pilot actual
	if is_instance_valid(player_controller) and player_controller.is_inside_tree():
		var parent = player_controller.get_parent()
		var old_input_provider = player_controller.input_provider if "input_provider" in player_controller else null
		player_controller.queue_free()
		yield (get_tree(), "idle_frame")
		# Instanciar nuevo Pilot
		var pilot_scene = preload("res://core_v2/actors/Pilot_v2.tscn")
		var new_pilot = pilot_scene.instance()
		# Add to scene first so _ready runs, then apply absolute transform
		parent.add_child(new_pilot)
		yield (get_tree(), "idle_frame")
		# Ensure camera is current if it exists
		var cam = new_pilot.get_node_or_null("CameraRig/Camera")
		if cam:
			cam.current = true
			print("[TeleportSystem] Camera set as current for new player")
		# Deep reset to avoid inheriting any previous state
		if new_pilot.has_method("full_reset"):
			new_pilot.full_reset()
		# Enforce absolute transform and zero velocities
		new_pilot.global_transform = target_transform
		new_pilot.initial_transform = target_transform
		# Allow physics to process so Areas will detect overlap and emit signals
		yield (get_tree(), "physics_frame")
		if new_pilot.has_method("set_external_velocity"):
			new_pilot.set_external_velocity(Vector3.ZERO)
		new_pilot.velocity = Vector3.ZERO
		if target_yaw != null:
			new_pilot.yaw = target_yaw
			new_pilot.yaw_deg = rad2deg(target_yaw)
		if target_pitch != null:
			new_pilot.pitch = target_pitch
			new_pilot.pitch_deg = rad2deg(target_pitch)
		# Actualizar referencias
		if old_input_provider and is_instance_valid(old_input_provider):
			new_pilot.input_provider = old_input_provider
		player_controller = new_pilot
		# Ensure SessionManager knows about the new player instance (so recording/input overrides keep working)
		var sm = get_node_or_null("/root/SessionManager")
		if sm:
					sm.player = new_pilot
					print("[TeleportSystem] SessionManager player refreshed: ", sm.player)
					# If the session's OYS override exists but only contains no-op input (zeros),
					# clear it so subsequent OYS commands can post fresh inputs after respawn.
					if sm.has_method("get") and sm.get("_oys_input_override"):
						var od_check2 = sm.get("_oys_input_override")
						var only_noop2 = true
						if od_check2.has("move_vec"):
							var mv2 = od_check2.get("move_vec")
							if typeof(mv2) == TYPE_ARRAY and (mv2.size() >= 2) and (float(mv2[0]) != 0.0 or float(mv2[1]) != 0.0):
								only_noop2 = false
						if od_check2.has("jump") and od_check2.get("jump"):
							only_noop2 = false
						if od_check2.has("interact") and od_check2.get("interact"):
							only_noop2 = false
						if only_noop2:
							sm.set("_oys_input_override", {})
							print("[TeleportSystem] Cleared noop OYS override after respawn")
					# If we are recording/replaying, mark the pilot as externally-controlled and ensure input provider
					if sm.is_recording or sm.is_replaying or sm.get("_is_waiting_for_respawn_validation"):
						new_pilot.is_replay_mode = true
						if new_pilot.has_method("ensure_input_provider"):
							new_pilot.ensure_input_provider()
					# If there is an active OYS input override that contains meaningful input,
					# apply it immediately to the new player. This avoids applying only-zero/no-op
					# overrides which can mask subsequent OYS inputs.
					if sm.has_method("get") and sm.get("_oys_input_override") and not sm.get("_oys_input_override").empty():
						var od = sm.get("_oys_input_override")
						var has_active = false
						if od.has("move_vec"):
							var mv = od.get("move_vec")
							if typeof(mv) == TYPE_ARRAY and (mv.size() >= 2) and (float(mv[0]) != 0.0 or float(mv[1]) != 0.0):
								has_active = true
						if od.has("jump") and od.get("jump"):
							has_active = true
						if od.has("interact") and od.get("interact"):
							has_active = true
						if has_active:
							var InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
							var idata = InputDataV2.new()
							idata.from_dict(od)
							sm.player.external_input = idata
							sm.player.external_input_provided = true
							print("[TeleportSystem] Applied existing OYS override to new player:", od)
							# Debug: show override retained in session
							print("[TeleportSystem] SessionManager _oys_input_override after apply=", sm.get("_oys_input_override"))
							# Give pilot a chance to consume the injected external input before OYS measures
							yield (get_tree(), "physics_frame")
		# Actualizar camera_controller si existe
		var cam_rig = new_pilot.get_node_or_null("CameraRig")
		if cam_rig:
			camera_controller = cam_rig
		print("[TeleportSystem] Nuevo Pilot instanciado y referenciado. enforced transform and reset state:", new_pilot.initial_transform)
		# Desactivar flag de respawn después de algunos frames para permitir que las zonas detecten al player
		call_deferred("_clear_respawn_flag")
	else:
		print("[TeleportSystem] No se pudo reinstanciar Pilot (no estaba en árbol)")
		_clear_respawn_flag()

func _on_checkpoint_reached(transform):
	print("[TeleportSystem] Señal recibida: checkpoint_reached, transform=", transform)
	# Guardar el checkpoint en el slot 'last' y persistirlo, incluyendo rotación
	var persistence_manager = get_node_or_null("/root/PersistenceManager")
	var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
	if persistence_manager and persistence_manager.has_method("get_checkpoint_resource"):
		var checkpoint_res = persistence_manager.get_checkpoint_resource(scene_path)
		if checkpoint_res:
			var checkpoint_data = {
				"transform": transform,
				"yaw": player_controller.get("yaw") if "yaw" in player_controller else 0.0,
				"pitch": player_controller.get("pitch") if "pitch" in player_controller else 0.0
			}
			checkpoint_res.slots["last"] = checkpoint_data
			checkpoint_res.property_list_changed_notify() # Forzar a Godot a marcar el recurso como modificado
			print("[TeleportSystem] Checkpoint guardado en slot 'last' (con rotación).", checkpoint_data)
			if persistence_manager.has_method("save_checkpoint_resource"):
				persistence_manager.save_checkpoint_resource(scene_path)
				print("[TeleportSystem] Checkpoint persistido en disco.")
	
func force_initial_spawn(tf: Transform, yaw: float = 0.0, pitch: float = 0.0):
	"""Manually overrides the initial spawn point for the current scene."""
	initial_spawn_transform = tf
	print("[TeleportSystem] force_initial_spawn: initial_spawn_transform updated to %s" % tf.origin)
	
	var persistence_manager = get_node_or_null("/root/PersistenceManager")
	var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
	if persistence_manager and persistence_manager.has_method("get_checkpoint_resource"):
		var checkpoint_res = persistence_manager.get_checkpoint_resource(scene_path)
		if checkpoint_res:
			var checkpoint_data = {
				"transform": tf,
				"yaw": yaw,
				"pitch": pitch
			}
			checkpoint_res.slots["last"] = checkpoint_data
			checkpoint_res.property_list_changed_notify()
			print("[TeleportSystem] Checkpoint 'last' updated via force_initial_spawn.")
			if persistence_manager.has_method("save_checkpoint_resource"):
				persistence_manager.save_checkpoint_resource(scene_path)

func _clear_respawn_flag():
	# Esperar algunos frames antes de limpiar el flag para asegurar que las zonas
	# hayan procesado la entrada del player
	yield (get_tree(), "physics_frame")
	yield (get_tree(), "physics_frame")
	var sm = get_node_or_null("/root/SessionManager")
	if sm:
		sm.is_respawning = false
		print("[TeleportSystem] Flag is_respawning desactivado")
