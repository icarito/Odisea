extends Spatial

# Harness de evidencia visual (960x540) para la locomoción RL del ProgrammerHoloNPC.
# NO es un test de CI: requiere framebuffer, así que se corre manualmente con el
# binario editor en una sesión con display:
#
#   "$(sh tools/godot_bin.sh)" --path . res://core_v2/tests/HoloRLLab.tscn --no-window
#
# Salida: test_output/holo_rl/holo_rl_*.png (960x540). Captura dos fases:
#   1_rl_on  -> use_rl_policy = true, la política conduce el guiado.
#   2_rl_off -> use_rl_policy = false, fallback hand-authored (guide_to).
# Cada fase captura el inicio y el final del recorrido.

const HOLO_NPC_SCENE := preload("res://core_v2/actors/ProgrammerHoloNPC.tscn")
const OUT_DIR := "res://test_output/holo_rl/"
const CAPTURE_SIZE := Vector2(960.0, 540.0)
const NPC_START := Vector3(0.0, 0.0, -9.0)
const GUIDE_TARGET := Vector3(0.0, 0.0, 8.0)


func _ready() -> void:
	# Sólo corre como escena principal del harness visual; si otra escena/test lo
	# instancia como hijo, no toca el viewport ni quita el árbol.
	if get_tree().current_scene != self:
		return
	get_viewport().set_size_override(true, CAPTURE_SIZE)
	OS.window_size = CAPTURE_SIZE
	_build_stage()
	call_deferred("_run")


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_color = Color(0.35, 0.4, 0.5)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var dir := DirectionalLight.new()
	dir.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	dir.light_energy = 1.1
	add_child(dir)

	var ground := MeshInstance.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(48.0, 48.0)
	ground.mesh = plane
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.07, 0.09, 0.12)
	ground.material_override = mat
	add_child(ground)

	# Grilla de referencia para leer el desplazamiento.
	var gmat := SpatialMaterial.new()
	gmat.albedo_color = Color(0.16, 0.34, 0.42)
	gmat.flags_unshaded = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var half := 12
	for i in range(-half, half + 1):
		var f := float(i)
		st.add_vertex(Vector3(f, 0.01, -half))
		st.add_vertex(Vector3(f, 0.01, half))
		st.add_vertex(Vector3(-half, 0.01, f))
		st.add_vertex(Vector3(half, 0.01, f))
	var grid := MeshInstance.new()
	grid.mesh = st.commit()
	grid.material_override = gmat
	add_child(grid)

	# Marcador del objetivo (cubo emisivo).
	var marker := MeshInstance.new()
	marker.name = "TargetMarker"
	var box := CubeMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	marker.mesh = box
	var mmat := SpatialMaterial.new()
	mmat.albedo_color = Color(1.0, 0.55, 0.15)
	mmat.emission_enabled = true
	mmat.emission = Color(1.0, 0.5, 0.1)
	marker.material_override = mmat
	marker.translate(GUIDE_TARGET + Vector3(0.0, 0.5, 0.0))
	add_child(marker)

	var cam := Camera.new()
	cam.name = "HarnessCamera"
	cam.fov = 62.0
	add_child(cam)
	cam.transform.origin = Vector3(16.0, 8.0, 0.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true


func _run() -> void:
	yield(_wait_frames(20), "completed")
	# Asegurar que el framebuffer ya renderizó frames completos antes de la 1ª captura.
	for _i in range(8):
		yield(VisualServer, "frame_post_draw")
	yield(_run_phase(true, "1_rl_on"), "completed")
	yield(_wait_frames(20), "completed")
	yield(_run_phase(false, "2_rl_off"), "completed")
	print("[HoloRLLab] capturas en ", OUT_DIR)
	get_tree().quit()


func _run_phase(rl_on: bool, tag: String) -> void:
	for n in get_tree().get_nodes_in_group("programmer_holo_npc"):
		n.queue_free()
	yield(get_tree(), "idle_frame")

	var npc = HOLO_NPC_SCENE.instance()
	add_child(npc)
	npc.global_transform.origin = NPC_START
	# En el harness no hay jugador: se desactiva el "wait for player" de la guía.
	npc.guide_wait_distance = 1000.0
	npc.guide_resume_distance = 999.0
	if rl_on:
		npc.use_rl_policy = true
		npc.start_rl_guide(GUIDE_TARGET, 5.0)
	else:
		npc.use_rl_policy = false
		npc.guide_to(GUIDE_TARGET, 4.0)

	yield(_wait_frames(30), "completed")
	_report(npc, tag + "_a_inicio")
	yield(_capture(tag + "_a_inicio"), "completed")
	yield(_wait_frames(150), "completed")
	_report(npc, tag + "_b_final")
	yield(_capture(tag + "_b_final"), "completed")


func _report(npc, phase: String) -> void:
	var pos: Vector3 = npc.global_transform.origin
	print("[HoloRLLab] %s pos=(%.2f, %.2f, %.2f) mode=%d rl_active=%s last_action=%d dist_target=%.2f" % [
		phase, pos.x, pos.y, pos.z, npc.get_behavior_mode(), str(npc.is_rl_active()),
		npc.get_last_rl_action(), pos.distance_to(GUIDE_TARGET)])


func _wait_frames(count: int) -> void:
	for _i in range(count):
		yield(get_tree(), "physics_frame")


func _capture(label: String) -> void:
	yield(VisualServer, "frame_post_draw")
	var img := get_viewport().get_texture().get_data()
	img.flip_y()
	var dir := Directory.new()
	if not dir.dir_exists(OUT_DIR):
		dir.make_dir_recursive(OUT_DIR)
	var path := OUT_DIR + "holo_rl_" + label + ".png"
	var err := img.save_png(path)
	print("[HoloRLLab] screenshot ", path, " err=", err)
