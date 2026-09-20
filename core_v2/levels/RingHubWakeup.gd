extends Spatial
class_name RingHubWakeup

export(NodePath) var pilot_path := NodePath("Pilot")
export(NodePath) var criopod_path := NodePath("Criopod_Vert")
export(NodePath) var slots_path := NodePath("Hub/Criopods")
export(Vector3) var pilot_inside_offset := Vector3(0.000200272, 0.735, -0.123402)
# El pod funcional toma la misma pose que el item decorativo del slot. El mesh del Criopod_Vert ya
# tiene su origen en la base, asi que no hace falta compensar en Y (un offset positivo lo dejaba
# flotando). Ajustar solo si queda unos cm arriba/abajo.
export(float) var pod_base_offset := 0.0
# FD-307: la holoterminal de la capsula se abre sola al arrancar y la cinematica de
# despertar espera a que el jugador la cierre.
export(bool) var open_pod_terminal_on_start := true
export(String) var pod_screen_id := "ship:cryopod:elias"

var _base_blocked_ranges: Array = []
var _selected_slot := -1
var _selected_item_transform := Transform()
var _has_selected_item_transform := false
var _gated_oys_script := ""

func _ready() -> void:
	add_to_group("replay_sync")
	var session = get_node_or_null("/root/SessionManager")
	if session != null and session.has_method("register_oys_actor"):
		session.register_oys_actor("RingHub", self)
		if session.has_signal("oys_registry_reset") and not session.is_connected("oys_registry_reset", self, "_on_oys_registry_reset"):
			session.connect("oys_registry_reset", self, "_on_oys_registry_reset")
	if open_pod_terminal_on_start:
		_gate_wakeup_sequence()
		call_deferred("_open_pod_terminal")
	var hatch := get_node_or_null("Criopod_Vert/RotatingObjectV2")
	if hatch != null:
		hatch.set_meta("platform_tracking_excluded", true)
	var terminal := get_node_or_null("Criopod_Vert/RotatingObjectV2/CryoPodTerminal")
	if terminal != null:
		terminal.set_meta("platform_tracking_excluded", true)
	var slots := _get_slots()
	if slots == null:
		return
	_base_blocked_ranges = slots.blocked_angle_ranges_deg.duplicate(true)
	if _selected_slot < 0:
		_selected_slot = _pick_slot(slots)
	_apply_wakeup_slot()

func _on_oys_registry_reset() -> void:
	var session = get_node_or_null("/root/SessionManager")
	if session != null and session.has_method("register_oys_actor"):
		session.register_oys_actor("RingHub", self)

# La zona conserva el script OYS hasta que termine la pantalla inicial. Vaciar la cadena al
# soltarlo hace que esta ruta sea de una sola vez, independiente del boton de la escotilla.
func _gate_wakeup_sequence() -> void:
	var zone := get_node_or_null("Criopod_Vert/CinematicSequence")
	if zone == null:
		return
	_gated_oys_script = String(zone.script_file)
	zone.script_file = ""

func _open_pod_terminal() -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and not suit_os.has_screen(pod_screen_id):
		yield(get_tree(), "idle_frame")
		suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null or not suit_os.has_screen(pod_screen_id):
		_release_wakeup_sequence()
		return
	if not suit_os.is_connected("screen_closed", self, "_on_pod_screen_closed"):
		suit_os.connect("screen_closed", self, "_on_pod_screen_closed")
	if not suit_os.open_hud_mode(false, pod_screen_id):
		_release_wakeup_sequence()

# Punto de entrada del OYS (CALL RingHub "close_pod_terminal"): cerrar la holoterminal
# es lo que suelta la cinematica de despertar.
func close_pod_terminal() -> void:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.is_hud_mode_active():
		suit_os.close_hud_mode()
	_release_wakeup_sequence()

# La escotilla ya no es interactuable suelta (la opera el terminal), asi que la
# cinematica de despertar la abre por la misma accion que el boton de la pantalla.
func open_pod_hatch() -> void:
	if _pod_hatch_is_open():
		return
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(pod_screen_id):
		var result: Dictionary = suit_os.perform_action(pod_screen_id, "toggle_hatch")
		if bool(result.get("ok", false)):
			return
	var hatch = get_node_or_null("Criopod_Vert/RotatingObjectV2")
	if hatch != null and hatch.has_method("set_active"):
		hatch.set_active(true)

func _on_pod_screen_closed(id: String) -> void:
	if id != pod_screen_id:
		return
	_release_wakeup_sequence()

func _pod_hatch_is_open() -> bool:
	var hatch = get_node_or_null("Criopod_Vert/RotatingObjectV2")
	return is_instance_valid(hatch) and "is_active" in hatch and bool(hatch.is_active)

func _release_wakeup_sequence() -> void:
	if _gated_oys_script.empty():
		return
	var zone := get_node_or_null("Criopod_Vert/CinematicSequence")
	if zone == null:
		return
	zone.script_file = _gated_oys_script
	_gated_oys_script = ""
	zone.call_deferred("trigger_from_script")

func _get_slots() -> RadialScatter:
	return get_node_or_null(slots_path) as RadialScatter

func _pick_slot(slots: RadialScatter) -> int:
	var valid_slots := []
	for slot in range(slots.item_count):
		var data := _slot_data(slots, slot)
		if not slots._is_angle_blocked(data.angle_deg):
			valid_slots.append(slot)
	if valid_slots.empty():
		return -1
	var rng := RandomNumberGenerator.new()
	var session = get_node_or_null("/root/SessionManager")
	rng.seed = int(session.run_seed) if session and "run_seed" in session else 0
	return int(valid_slots[int(rng.randi() % valid_slots.size())])

func _apply_wakeup_slot() -> void:
	var slots := _get_slots()
	var pod := get_node_or_null(criopod_path) as Spatial
	var pilot := get_node_or_null(pilot_path) as Spatial
	if slots == null or pod == null or pilot == null or _selected_slot < 0:
		return
	if _base_blocked_ranges.empty():
		_base_blocked_ranges = slots.blocked_angle_ranges_deg.duplicate(true)
	var data := _slot_data(slots, _selected_slot)
	# Do not build a parallax pod under the functional wake-up pod.
	slots.blocked_angle_ranges_deg.clear()
	slots.blocked_angle_ranges_deg.append_array(_base_blocked_ranges.duplicate(true))
	slots.blocked_angle_ranges_deg.append(Vector2(data.angle_deg - 0.01, data.angle_deg + 0.01))
	var item := slots.get_node_or_null("Item_%d" % _selected_slot) as Spatial
	if item != null:
		# Conservar la escala horneada del slot: normalizar la basis dejaba el pod de Elias
		# mas pequeno que el criopod decorativo que ocupa ese mismo lugar.
		_selected_item_transform = item.global_transform
		_has_selected_item_transform = true
		item.free()
		pod.global_transform = Transform(_selected_item_transform.basis,
			_selected_item_transform.origin + Vector3.UP * pod_base_offset)
	elif _has_selected_item_transform:
		pod.global_transform = Transform(_selected_item_transform.basis,
			_selected_item_transform.origin + Vector3.UP * pod_base_offset)
	else:
		pod.global_transform.origin = slots.to_global(data.position) + Vector3.UP * pod_base_offset
		if slots.inward:
			pod.look_at(slots.to_global(Vector3(0.0, data.height, 0.0)), Vector3.UP)
		slots._apply_rotation_offsets(pod, slots.rotation_x, slots.rotation_y, slots.rotation_z)
	var terminal := get_node_or_null("Criopod_Vert/RotatingObjectV2/CryoPodTerminal")
	var cinematic_setup := terminal.get_node_or_null("CinematicSetup") as Spatial if terminal != null else null
	if cinematic_setup != null and cinematic_setup.is_set_as_toplevel():
		cinematic_setup.global_transform = terminal.global_transform
	var pilot_transform := pod.global_transform
	pilot_transform.basis = pilot_transform.basis.orthonormalized().scaled(pilot.scale)
	pilot_transform.origin = pod.to_global(pilot_inside_offset)
	pilot.global_transform = pilot_transform
	if "velocity" in pilot:
		pilot.velocity = Vector3.ZERO

func _slot_data(slots: RadialScatter, slot: int) -> Dictionary:
	var progress := slots._get_progress(slot, slots.item_count)
	var angle := slots._get_angle(progress) + deg2rad(slots._get_item_angle_offset_deg(slot))
	var completed_turns := progress * slots.arc_angle_deg / 360.0
	var radius_turns := slots.radius_turn_offset + completed_turns
	var radius := slots._get_radius_at_turn(radius_turns)
	var height := slots.height_offset + slots.height_per_turn * completed_turns
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	var tangent := Vector3(-sin(angle), 0.0, cos(angle))
	var offset := slots.item_offset + slots.item_offset_step * float(slot)
	var position := radial * radius + radial * offset.x
	position += Vector3.UP * (height + offset.y) + tangent * offset.z
	return {"angle_deg": rad2deg(angle), "height": height, "position": position}

func get_snapshot() -> Dictionary:
	return {
		"selected_slot": _selected_slot,
		"gated_oys_script": _gated_oys_script,
	}

func restore_snapshot(data: Dictionary) -> void:
	_selected_slot = int(data.get("selected_slot", _selected_slot))
	_gated_oys_script = String(data.get("gated_oys_script", ""))
	_apply_wakeup_slot()
