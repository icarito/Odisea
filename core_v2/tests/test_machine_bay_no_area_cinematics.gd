extends GdUnitTestSuite

# Guardia (FD-321, revisado 2026-11-14): la Bahía de Máquinas NO tiene cinemáticas
# por área.
#
# El pedido de diseño corrigió el alcance: las cámaras cinemáticas son SOLO para las
# *transiciones* entre zonas (las implementa el sistema de transiciones), nunca para
# "áreas" dentro del nivel. Este test evita que se reintroduzcan `CameraZone`/
# `CinematicRig` disparando cinemáticas al caminar por MachineBay.
#
# Antes existían `Cinematics/ArrivalGate`, `Cinematics/ArrivalRevealRig`,
# `Cinematics/BridgeFireGate` y `Cinematics/BridgeFireRevealRig`; se eliminaron de
# `MachineBay.tscn` junto con los `ext_resource` de `CameraZone.gd` y
# `CinematicRig.tscn`.

const BayScene := preload("res://core_v2/levels/machines/MachineBay.tscn")
const CameraZoneScript := preload("res://core_v2/components/CameraZone.gd")

const BAY_SCENE_PATH := "res://core_v2/levels/machines/MachineBay.tscn"


# ---------------------------------------------------------------------------
# Guardia de fuente: el .tscn no debe referenciar zonas/rigs cinemáticos.
# ---------------------------------------------------------------------------

func _scene_source() -> String:
	var f := File.new()
	assert_int(f.open(BAY_SCENE_PATH, File.READ)).is_equal(OK)
	var src := f.get_as_text()
	f.close()
	return src


func test_bay_scene_source_has_no_area_cinematics() -> void:
	var src := _scene_source()
	assert_int(src.find("CameraZone")).is_equal(-1)
	assert_int(src.find("CinematicRig")).is_equal(-1)
	assert_int(src.find("\"Cinematics\"")).is_equal(-1)


func test_bay_scene_source_keeps_labyrinth_and_streamer() -> void:
	# El retiro de cinemáticas no debe haber tocado el contenido procedural.
	var src := _scene_source()
	assert_bool(src.find("LabyrinthSection") != -1).is_true()
	assert_bool(src.find("MachineBayLabyrinthStreamer") != -1).is_true()


# ---------------------------------------------------------------------------
# Guardia de instancia: al construir el nivel no aparece ninguna CameraZone.
# ---------------------------------------------------------------------------

func _collect_camera_zones(root: Node, sink: Array) -> void:
	var stack := [root]
	while not stack.empty():
		var current: Node = stack.pop_back()
		if current.get_script() == CameraZoneScript or current.is_in_group("CameraZoneV2"):
			sink.append(current)
		for child in current.get_children():
			stack.push_back(child)


func test_instantiated_bay_exposes_no_camera_zones() -> void:
	var bay = auto_free(BayScene.instance())
	add_child(bay)
	yield(get_tree(), "idle_frame")
	assert_object(bay.get_node_or_null("Cinematics")).is_null()
	var zones: Array = []
	_collect_camera_zones(bay, zones)
	assert_int(zones.size()).is_equal(0)
