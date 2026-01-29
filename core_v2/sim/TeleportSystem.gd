extends Node
class_name TeleportSystem

# Coordina el teletransporte del jugador y la cámara.
# Debe ser conectado al PlayerControllerV2 y escuchar input.

var player_controller = null
var camera_controller = null

func _enter_tree():
	print("[TeleportSystem] _enter_tree. self=", self, " path=", get_path())
	# (Conexión de señales player_killed y checkpoint_reached eliminada: ahora la realiza cada zona)

func _ready():
	print("[TeleportSystem] _ready. self=", self, " path=", get_path())
	print("[TeleportSystem] player_controller (en _ready)=", player_controller)

	# Si player_controller no está asignado, buscarlo ahora
	if not player_controller:
		var pilot = get_tree().get_root().find_node("Pilot", true, false)
		print("[TeleportSystem] Buscando Pilot en _ready:", pilot, " path=", pilot.get_path() if pilot else "null")
		player_controller = pilot
	if not camera_controller and player_controller:
		var cam_rig = player_controller.get_node_or_null("CameraRig")
		print("[TeleportSystem] Buscando CameraRig en _ready:", cam_rig, " path=", cam_rig.get_path() if cam_rig else "null")
		camera_controller = cam_rig

func teleport_to(transform: Transform):
	print("[TeleportSystem] teleport_to llamado:", transform)
	print("[TeleportSystem] player_controller:", player_controller)
	if player_controller:
		print("[TeleportSystem] Llamando player_controller.teleport_to")
		player_controller.teleport_to(transform)
	else:
		print("[TeleportSystem] player_controller es null, no se puede teletransportar")
	if camera_controller and camera_controller != player_controller:
		print("[TeleportSystem] Llamando camera_controller.set_transform")
		camera_controller.global_transform = transform


# Atajos de teclado: trackback (Backspace) y reset
func _input(event):
	if event.is_action_pressed("trackback"):
		print("[TeleportSystem] Atajo 'trackback' presionado: respawn en último checkpoint (como morir)")
		_on_player_killed()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed("reset"):
		print("[TeleportSystem] Atajo 'reset' presionado: respawn en spawn point o 0,0,0")
		_respawn_at_spawn_or_zero()
		get_tree().set_input_as_handled()

# Respawn forzado en el spawn point o 0,0,0
func _respawn_at_spawn_or_zero():
	var target_transform = null
	var target_yaw = null
	var target_pitch = null
	# Buscar SpawnPointV2
	var spawn = get_tree().current_scene.find_node("SpawnPointV2", true, false) if get_tree().current_scene else null
	if spawn:
		target_transform = spawn.global_transform
		print("[TeleportSystem] Reset usando SpawnPointV2.")
	else:
		target_transform = Transform()
		print("[TeleportSystem] Reset usando Transform.ZERO.")
	# Reinstanciar Pilot
	if player_controller and player_controller.is_inside_tree():
		var parent = player_controller.get_parent()
		player_controller.queue_free()
		yield(get_tree(), "idle_frame")
		var pilot_scene = preload("res://core_v2/actors/Pilot_v2.tscn")
		var new_pilot = pilot_scene.instance()
		new_pilot.global_transform = target_transform
		if target_yaw != null:
			new_pilot.yaw = target_yaw
			new_pilot.yaw_deg = rad2deg(target_yaw)
		if target_pitch != null:
			new_pilot.pitch = target_pitch
			new_pilot.pitch_deg = rad2deg(target_pitch)
		parent.add_child(new_pilot)
		player_controller = new_pilot
		var cam_rig = new_pilot.get_node_or_null("CameraRig")
		if cam_rig:
			camera_controller = cam_rig
		print("[TeleportSystem] Nuevo Pilot instanciado por reset.")
	else:
		print("[TeleportSystem] No se pudo reinstanciar Pilot (reset)")

func _on_player_killed():
	print("[TeleportSystem] _on_player_killed ejecutado! (señal recibida)")
	print("[TeleportSystem] self:", self, " path=", get_path())
	print("[TeleportSystem] player_controller:", player_controller, " path=", player_controller.get_path() if player_controller else "null")

	# 1. Intentar cargar el último checkpoint guardado (PersistenceManager)
	var pm = get_node_or_null("/root/PersistenceManager")
	print("[TeleportSystem] Buscando PersistenceManager en /root/PersistenceManager:", pm)
	var checkpoint_res = null
	var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
	if pm and pm.has_method("get_checkpoint_resource"):
		checkpoint_res = pm.get_checkpoint_resource(scene_path)
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
	# 4. Si no hay nada, usar Transform en 0,0,0
	if not target_transform:
		target_transform = Transform()
		print("[TeleportSystem] Respawn usando Transform.ZERO.")

	print("[TeleportSystem] Reinstanciando Pilot en:", target_transform)
	# Eliminar el Pilot actual
	if player_controller and player_controller.is_inside_tree():
		var parent = player_controller.get_parent()
		player_controller.queue_free()
		yield(get_tree(), "idle_frame")
		# Instanciar nuevo Pilot
		var pilot_scene = preload("res://core_v2/actors/Pilot_v2.tscn")
		var new_pilot = pilot_scene.instance()
		new_pilot.global_transform = target_transform
		if target_yaw != null:
			new_pilot.yaw = target_yaw
			new_pilot.yaw_deg = rad2deg(target_yaw)
		if target_pitch != null:
			new_pilot.pitch = target_pitch
			new_pilot.pitch_deg = rad2deg(target_pitch)
		parent.add_child(new_pilot)
		# Actualizar referencias
		player_controller = new_pilot
		# Actualizar camera_controller si existe
		var cam_rig = new_pilot.get_node_or_null("CameraRig")
		if cam_rig:
			camera_controller = cam_rig
		print("[TeleportSystem] Nuevo Pilot instanciado y referenciado.")
	else:
		print("[TeleportSystem] No se pudo reinstanciar Pilot (no estaba en árbol)")

func _on_checkpoint_reached(transform):
	print("[TeleportSystem] Señal recibida: checkpoint_reached, transform=", transform)
	# Guardar el checkpoint en el slot 'last' y persistirlo, incluyendo rotación
	var pm = get_node_or_null("/root/PersistenceManager")
	var scene_path = get_tree().current_scene.filename if get_tree().current_scene else ""
	if pm and pm.has_method("get_checkpoint_resource"):
		var checkpoint_res = pm.get_checkpoint_resource(scene_path)
		if checkpoint_res:
			var checkpoint_data = {
				"transform": transform,
				"yaw": player_controller.yaw if player_controller else 0.0,
				"pitch": player_controller.pitch if player_controller else 0.0
			}
			checkpoint_res.slots["last"] = checkpoint_data
			checkpoint_res.property_list_changed_notify() # Forzar a Godot a marcar el recurso como modificado
			print("[TeleportSystem] Checkpoint guardado en slot 'last' (con rotación).", checkpoint_data)
			if pm.has_method("save_checkpoint_resource"):
				pm.save_checkpoint_resource(scene_path)
				print("[TeleportSystem] Checkpoint persistido en disco.")
