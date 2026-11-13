extends GdUnitTestSuite

const HOLO_NPC_SCENE = preload("res://core_v2/actors/ProgrammerHoloNPC.tscn")
const ProgrammerHoloNPC = preload("res://core_v2/actors/ProgrammerHoloNPC.gd")
const MachineLevelScript = preload("res://core_v2/props/machines/MachineLevel.gd")

const HOLO_SHADER_PATH = "res://core_v2/visual/ProgrammerHoloShader.shader"
const HOLO_MATERIAL_PATH = "res://core_v2/visual/ProgrammerHoloMaterial.tres"


class SignalSpy extends Node:
	var arrived_positions: Array = []
	var script_finished_count: int = 0
	var speech_finished_count: int = 0

	func on_arrived(pos: Vector3) -> void:
		arrived_positions.append(pos)

	func on_script_finished() -> void:
		script_finished_count += 1

	func on_speech_finished() -> void:
		speech_finished_count += 1


func test_holo_npc_starts_hidden_without_active_camera_or_collider() -> void:
	var root := Spatial.new()
	add_child(root)
	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)

	assert_bool(npc.visible).is_false()
	assert_bool(npc.is_speaking()).is_false()
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.HIDDEN)
	var cam := npc.find_node("Camera", true, false) as Camera
	assert_object(cam).is_not_null()
	assert_bool(cam.current).is_false()
	assert_object(npc.find_node("HoloCameraRig", true, false)).is_not_null()
	assert_object(npc.find_node("AudioListener", true, false)).is_null()
	assert_object(npc.find_node("CollisionShape", true, false)).is_null()

	root.queue_free()


func test_holo_npc_appears_moves_automatically_and_disappears() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	viewer.transform.origin = Vector3(2.0, 1.0, 3.0)
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)

	npc.appear_and_speak(2.0, viewer)
	assert_bool(npc.visible).is_true()
	assert_bool(npc.is_speaking()).is_true()
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.APPEAR_SPEAK)

	var initial_pos: Vector3 = npc.global_transform.origin
	# Debe aparecer delante del viewer (-Z del viewer por defecto).
	assert_bool(initial_pos.z < viewer.global_transform.origin.z).is_true()

	# Avanzar fade_in (0.4s) + parte de la duración activa: debe seguir visible y moverse automáticamente.
	for _i in range(45):
		npc._physics_process(1.0 / 60.0)
	assert_bool(npc.visible).is_true()
	assert_bool(npc.is_speaking()).is_true()
	var moved_pos: Vector3 = npc.global_transform.origin
	assert_bool(moved_pos.distance_to(initial_pos) > 0.05).is_true()

	# Avanzar hasta completar los 2.0s + fade_out (0.45s).
	for _i in range(150):
		npc._physics_process(1.0 / 60.0)
	assert_bool(npc.visible).is_false()
	assert_bool(npc.is_speaking()).is_false()

	root.queue_free()


func test_summon_reuses_instance_and_machine_level_say_triggers_it() -> void:
	var root := Spatial.new()
	add_child(root)
	var player := Spatial.new()
	player.add_to_group("player")
	player.transform.origin = Vector3(0.0, 0.0, 0.0)
	root.add_child(player)

	var level := Spatial.new()
	level.set_script(MachineLevelScript)
	root.add_child(level)

	level.say("ODISEA: Prueba de holograma.", 3.0)
	var npcs := get_tree().get_nodes_in_group(ProgrammerHoloNPC.GROUP_NAME)
	assert_int(npcs.size()).is_equal(1)
	assert_bool(npcs[0].visible).is_true()
	assert_bool(npcs[0].is_speaking()).is_true()

	# Segunda llamada reutiliza la misma instancia.
	ProgrammerHoloNPC.summon(get_tree(), 4.0)
	npcs = get_tree().get_nodes_in_group(ProgrammerHoloNPC.GROUP_NAME)
	assert_int(npcs.size()).is_equal(1)

	npcs[0].queue_free()
	root.queue_free()


func test_follow_mode_tracks_viewer_and_selects_locomotion_anim() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	viewer.transform.origin = Vector3(0.0, 0.0, 0.0)
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)

	npc.start_follow(viewer)
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.FOLLOW)
	assert_bool(npc.visible).is_true()

	# Mover al jugador lejos para forzar seguimiento.
	viewer.transform.origin = Vector3(0.0, 0.0, -12.0)
	npc._physics_process(1.0 / 60.0)
	var anim_while_moving: String = npc.get_current_animation()
	assert_bool(anim_while_moving in ["Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop"]).is_true()

	for _i in range(180):
		npc._physics_process(1.0 / 60.0)

	# Debe haber alcanzado la zona cómoda detrás/al lado del viewer y volver a idle.
	var dist_to_viewer: float = npc.global_transform.origin.distance_to(viewer.global_transform.origin)
	assert_bool(dist_to_viewer < 4.0).is_true()
	assert_bool(npc.get_current_animation() in ["Idle_Loop", "Swim_Idle_Loop"]).is_true()

	root.queue_free()


func test_move_to_reaches_target_and_emits_arrived() -> void:
	var root := Spatial.new()
	add_child(root)
	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)

	var spy := SignalSpy.new()
	root.add_child(spy)
	npc.connect("arrived", spy, "on_arrived")

	var target := Vector3(4.0, 0.0, 0.0)
	npc.move_to(target, 4.0)
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.MOVE_TO)

	npc._physics_process(1.0 / 60.0)
	assert_str(npc.get_current_animation()).is_equal("Jog_Fwd_Loop")

	for _i in range(100):
		npc._physics_process(1.0 / 60.0)

	assert_int(spy.arrived_positions.size()).is_equal(1)
	assert_bool(npc.global_transform.origin.distance_to(target) < 0.7).is_true()
	assert_bool(npc.get_current_animation() in ["Idle_Loop", "Swim_Idle_Loop"]).is_true()

	root.queue_free()


func test_orbit_guide_waits_when_player_far_and_resumes_when_close() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	viewer.transform.origin = Vector3(0.0, 0.0, 0.0)
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)
	npc.start_follow(viewer)
	npc.guide_wait_distance = 5.0
	npc.guide_resume_distance = 3.5

	var spy := SignalSpy.new()
	root.add_child(spy)
	npc.connect("arrived", spy, "on_arrived")

	var goal := Vector3(0.0, 0.0, -9.0)
	npc.guide_to(goal, 4.0)
	assert_int(npc.get_behavior_mode()).is_equal(ProgrammerHoloNPC.BehaviorMode.ORBIT_GUIDE)

	# Avanzar hasta que se aleje > guide_wait_distance y deba esperar.
	for _i in range(150):
		npc._physics_process(1.0 / 60.0)

	assert_int(spy.arrived_positions.size()).is_equal(0)
	var paused_z: float = npc.global_transform.origin.z
	assert_bool(paused_z > -8.0).is_true()
	assert_bool(npc.get_current_animation() in ["Idle_Loop", "Swim_Idle_Loop"]).is_true()

	# Acercar al jugador a su posición: debe reanudar la marcha y llegar al objetivo.
	viewer.transform.origin = Vector3(0.0, 0.0, paused_z)
	for _i in range(180):
		npc._physics_process(1.0 / 60.0)

	assert_int(spy.arrived_positions.size()).is_equal(1)
	assert_bool(npc.global_transform.origin.distance_to(goal) < 0.7).is_true()

	root.queue_free()


func test_play_animation_and_return_to_idle_on_finish() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)
	npc.start_follow(viewer)
	for _i in range(120):
		npc._physics_process(1.0 / 60.0)

	var ok: bool = npc.play_animation("Victory", 0.15)
	assert_bool(ok).is_true()
	assert_str(npc.get_current_animation()).is_equal("Victory")

	npc._on_animation_finished("Victory")
	assert_bool(npc.get_current_animation() in ["Idle_Loop", "Swim_Idle_Loop"]).is_true()

	root.queue_free()


func test_run_script_executes_steps_and_emits_signals() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)
	npc.start_follow(viewer)

	var spy := SignalSpy.new()
	root.add_child(spy)
	npc.connect("arrived", spy, "on_arrived")
	npc.connect("speech_finished", spy, "on_speech_finished")
	npc.connect("script_finished", spy, "on_script_finished")

	npc.run_script([
		{"action": "move_to", "pos": [2.0, 0.0, 0.0], "speed": 6.0, "timeout": 4.0},
		{"action": "anim", "name": "Victory", "duration": 0.3},
		{"action": "camera_focus", "duration": 0.4, "offset": [0.0, 1.4, 2.0]},
		{"action": "say", "text": "ODISEA: Secuencia completada.", "duration": 0.4},
		{"action": "wait", "sec": 0.2},
		{"action": "disappear", "immediate": true}
	])

	for _i in range(200):
		npc._physics_process(1.0 / 60.0)

	assert_int(spy.arrived_positions.size()).is_equal(1)
	assert_int(spy.speech_finished_count).is_equal(1)
	assert_int(spy.script_finished_count).is_equal(1)
	assert_bool(npc.visible).is_false()
	assert_int(npc.get_camera_request_id()).is_equal(-1)

	root.queue_free()


func test_focus_camera_and_release_camera_manages_cinematic_request() -> void:
	var root := Spatial.new()
	add_child(root)
	var viewer := Spatial.new()
	root.add_child(viewer)

	var npc := HOLO_NPC_SCENE.instance()
	root.add_child(npc)
	npc.start_follow(viewer)

	var cm := get_node_or_null("/root/CinematicManager")
	npc.focus_camera(1.0, Vector3(0.0, 1.5, 2.5))
	var req_id: int = npc.get_camera_request_id()
	if cm != null:
		assert_int(req_id).is_greater(0)
		assert_bool(cm._active_requests.has(req_id)).is_true()

	# Avanzar 1.1s: debe auto-liberar la cámara.
	for _i in range(70):
		npc._physics_process(1.0 / 60.0)
	assert_int(npc.get_camera_request_id()).is_equal(-1)
	if cm != null:
		assert_bool(cm._active_requests.has(req_id)).is_false()

	# Probar liberación manual via disappear().
	npc.focus_camera(5.0, Vector3(0.0, 1.5, 2.5))
	var req_id_2: int = npc.get_camera_request_id()
	if cm != null:
		assert_int(req_id_2).is_greater(0)
	npc.disappear(true)
	assert_int(npc.get_camera_request_id()).is_equal(-1)
	if cm != null:
		assert_bool(cm._active_requests.has(req_id_2)).is_false()

	root.queue_free()


# Contrato mobile (AGENTS.md §11.9): con framebuffer_allocation.Android=3
# (USAGE_3D_NO_EFFECTS) no hay screen/depth texture disponible. Un shader de gameplay
# que la lea puede fallar en silencio (log limpio, mesh invisible) en GLES3 movil. Este
# test es la guardia de regresion del fix: el shader del holograma no debe depender de
# SCREEN_TEXTURE ni DEPTH_TEXTURE.
func test_holo_shader_has_no_screen_or_depth_texture_dependency() -> void:
	var src := _read_text(HOLO_SHADER_PATH)
	assert_str(src).is_not_equal("")
	assert_int(src.find("SCREEN_TEXTURE")).is_equal(-1)
	assert_int(src.find("SCREEN_UV")).is_equal(-1)
	assert_int(src.find("DEPTH_TEXTURE")).is_equal(-1)


# El reemplazo del screen mix conserva el uniform background_mix para no dejar
# huerfano el parametro ya serializado en ProgrammerHoloMaterial.tres.
func test_holo_shader_keeps_background_mix_uniform_and_material_sets_it() -> void:
	var shader_src := _read_text(HOLO_SHADER_PATH)
	assert_int(shader_src.find("background_mix")).is_not_equal(-1)

	var material := load(HOLO_MATERIAL_PATH) as ShaderMaterial
	assert_object(material).is_not_null()
	assert_object(material.shader).is_not_null()


func _read_text(path: String) -> String:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
