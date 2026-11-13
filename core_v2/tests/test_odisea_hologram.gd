extends GdUnitTestSuite

# OdiseaHologramV2: NPC-holograma de Odisea. Cubre construcción del visual,
# fade-in/fade-out determinista por ticks, hook observer contra MachineLevel
# (señal "said") y el movimiento v2: seguimiento suave del jugador, orientación
# hacia él y selección de animación por velocidad horizontal (Idle/Walk).
#
# Nota: los yields de espera van SIEMPRE inline en el cuerpo del test; GdUnit no
# suspende la corrutina si el yield ocurre dentro de una función helper.

const HoloScene = preload("res://core_v2/actors/OdiseaHologramV2.tscn")
const MachineLevel = preload("res://core_v2/props/machines/MachineLevel.gd")


func _new_dummy_player(pos: Vector3) -> KinematicBody:
	var pl := KinematicBody.new()
	pl.name = "DummyPlayer"
	pl.add_to_group("player")
	pl.global_transform = Transform(Basis.IDENTITY, pos)
	get_tree().root.add_child(pl)
	return pl


func test_show_builds_visual_and_fades_in() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	assert_object(holo._visual).is_null()
	holo.show_holo(2.0)
	for _i in range(2):
		yield(get_tree(), "physics_frame")
	assert_object(holo._visual).is_not_null()
	assert_bool(holo._visual.visible).is_true()
	for _i in range(10):
		yield(get_tree(), "physics_frame")
	assert_bool(holo._alpha > 0.0).is_true()
	assert_bool(holo._alpha < 1.0).is_true()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_show_reaches_full_alpha_during_hold() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	holo.show_holo(4.0)
	for _i in range(40):
		yield(get_tree(), "physics_frame")
	assert_float(holo._alpha).is_equal(1.0)
	assert_bool(holo._visual.visible).is_true()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_hologram_hides_after_duration() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	holo.show_holo(0.5) # hold 30 ticks + fade-out ~30 ticks a 60 Hz
	for _i in range(2):
		yield(get_tree(), "physics_frame")
	assert_bool(holo._active).is_true()
	for _i in range(90):
		yield(get_tree(), "physics_frame")
	assert_bool(holo._active).is_false()
	assert_float(holo._alpha).is_equal(0.0)
	assert_bool(holo._visual.visible).is_false()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_hide_immediately_fades_out() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	holo.show_holo(10.0)
	for _i in range(5):
		yield(get_tree(), "physics_frame")
	holo.hide_holo()
	for _i in range(40): # fade-out 0.5s = ~30 ticks
		yield(get_tree(), "physics_frame")
	assert_float(holo._alpha).is_equal(0.0)
	assert_bool(holo._visual.visible).is_false()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_connects_to_machine_level_said() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	var level = MachineLevel.new()
	level.name = "HoloLevel"
	get_tree().root.add_child(level)
	level.build({"items": []})
	for _i in range(2):
		yield(get_tree(), "physics_frame")
	holo._scan_and_connect(get_tree().root)
	assert_bool(holo._levels.has(level.get_instance_id())).is_true()
	level.emit_signal("said", "ODISEA: prueba holograma", 2.0)
	for _i in range(3):
		yield(get_tree(), "physics_frame")
	assert_bool(holo._active).is_true()
	assert_object(holo._visual).is_not_null()
	holo.hide_holo()
	level.queue_free()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_does_not_break_without_player() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	holo.show_holo(0.5)
	for _i in range(30):
		yield(get_tree(), "physics_frame")
	assert_bool(holo._visual.visible).is_true()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_follows_player_and_orients_toward_it() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	var pl = _new_dummy_player(Vector3(0, 0, 0))
	holo.show_holo(10.0)
	for _i in range(120):
		yield(get_tree(), "physics_frame")
	var before_distance: float = holo._visual.global_transform.origin.distance_to(Vector3(4, 1, 0))
	pl.global_transform = Transform(Basis.IDENTITY, Vector3(4, 1, 0))
	for _i in range(120):
		yield(get_tree(), "physics_frame")
	var after: Vector3 = holo._visual.global_transform.origin
	var after_distance: float = after.distance_to(Vector3(4, 1, 0))
	assert_bool(after_distance < before_distance).is_true()
	assert_bool(after.y > 0.8).is_true() # sigue la Y del jugador (~1) + anchor_height
	var fwd: Vector3 = -holo._visual.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var to_player: Vector3 = Vector3(4, 0, 0) - after
	to_player.y = 0.0
	to_player = to_player.normalized()
	assert_bool(fwd.dot(to_player) > 0.9).is_true()
	pl.queue_free()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_animation_idle_when_player_static() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	var pl = _new_dummy_player(Vector3(0, 0, 0))
	holo.show_holo(10.0)
	for _i in range(240): # deja terminar Levitate Entrance y asentarse
		yield(get_tree(), "physics_frame")
	var anim: String = holo._anim_player.current_animation if holo._anim_player != null else ""
	assert_bool(anim == "Idle_Loop" or anim == "Swim_Idle_Loop").is_true()
	pl.queue_free()
	holo.queue_free()
	yield(get_tree(), "idle_frame")


func test_animation_walk_when_player_moves() -> void:
	var holo = HoloScene.instance()
	get_tree().root.add_child(holo)
	var pl = _new_dummy_player(Vector3(0, 0, 0))
	holo.show_holo(10.0)
	for _i in range(240):
		yield(get_tree(), "physics_frame")
	for i in range(40):
		pl.global_transform.origin = Vector3(float(i) * 0.5, 0.5, 0.0)
		yield(get_tree(), "physics_frame")
	var anim: String = holo._anim_player.current_animation if holo._anim_player != null else ""
	assert_bool(anim == "Walk_Loop").is_true()
	pl.queue_free()
	holo.queue_free()
	yield(get_tree(), "idle_frame")
