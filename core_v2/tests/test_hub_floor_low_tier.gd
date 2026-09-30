extends GdUnitTestSuite

# FD-316 (tarea Z): variantes LOW de los pisos del hub de RingHub.
#
# En el Anbernic cada piso son 3 MeshInstance horneados (los tercios angulares) x 5
# superficies = 15 draws; 5 pisos = 75 de los 108 draws por frame del censo 406a5d9e.
# En tier LOW ScaffoldHubRing cambia la malla de cada tercio por la variante de una
# sola superficie (bake_hub_floor_low.gd, merge de materiales con vertex colors) en una
# COPIA del recurso: los .mesh de alta que referencia la escena quedan intactos y fuera
# del tier LOW no cambia nada. Los UV2 horneados se conservan, asi que el lightmap
# nativo por nodo del nivel sigue muestreandose igual.

const RingScript = preload("res://core_v2/props/scaffold/ScaffoldHubRing.gd")
const LOW_PATHS := [
	"res://core_v2/levels/interiors/RingHub_Floor_1_low_0.mesh",
	"res://core_v2/levels/interiors/RingHub_Floor_1_low_1.mesh",
	"res://core_v2/levels/interiors/RingHub_Floor_1_low_2.mesh",
]
const HIGH_PATHS := [
	"res://core_v2/levels/interiors/RingHub_Floor_1_third_0.mesh",
	"res://core_v2/levels/interiors/RingHub_Floor_1_third_1.mesh",
	"res://core_v2/levels/interiors/RingHub_Floor_1_third_2.mesh",
]
const LEVEL_SCENE := "res://core_v2/levels/RingHub_Level.tscn"


func _gate():
	return get_node("/root/GLES3VendorGate")


# Arma un ScaffoldHubRing minimo con los tres tercios horneados como hijos, igual que
# la escena: _ready ve child_count != 0 y no reconstruye, asi que solo corre el swap.
func _make_ring(node_name: String, low_meshes: Array) -> Spatial:
	var ring := Spatial.new()
	ring.name = node_name
	ring.set_script(RingScript)
	ring.auto_build = false
	ring.low_tier_meshes = low_meshes
	for index in range(HIGH_PATHS.size()):
		var mesh_instance := MeshInstance.new()
		mesh_instance.name = "CombinedMesh" if index == 0 else "CombinedMesh_Third_%d" % index
		mesh_instance.mesh = load(HIGH_PATHS[index])
		ring.add_child(mesh_instance)
	return auto_free(ring)


func _chunk_meshes(ring: Spatial) -> Array:
	var meshes := []
	for child in ring.get_children():
		if child is MeshInstance and String(child.name).begins_with("CombinedMesh"):
			meshes.append((child as MeshInstance).mesh)
	return meshes


func _low_meshes() -> Array:
	var meshes := []
	for path in LOW_PATHS:
		meshes.append(load(path))
	return meshes


func test_low_tier_floors_use_single_surface_meshes() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	gate.force_gate = true

	var ring := _make_ring("RingFloorLowTier", _low_meshes())
	add_child(ring)

	var meshes := _chunk_meshes(ring)
	assert_int(meshes.size()).is_equal(3)
	for index in range(meshes.size()):
		var mesh: Mesh = meshes[index]
		assert_object(mesh).is_not_null()
		# Una sola superficie por tercio: 3 draws por piso en vez de 15.
		assert_int(mesh.get_surface_count()).is_less_equal(2)
		# Es una copia en runtime, no el recurso compartido.
		assert_str(String(mesh.resource_path)).is_equal("")

	# El .mesh de alta en disco no se toca.
	for path in HIGH_PATHS:
		var high: Mesh = load(path)
		assert_object(high).is_not_null()
		assert_int(high.get_surface_count()).is_equal(5)
		assert_str(String(high.resource_path)).is_equal(path)

	gate.force_gate = previous_force


func test_normal_tier_keeps_high_floor_meshes() -> void:
	var gate = _gate()
	if gate.is_low_tier():
		return # runner forzado a LOW: la asercion de desktop no aplica
	var previous_force: bool = gate.force_gate
	gate.force_gate = false

	var ring := _make_ring("RingFloorNormalTier", _low_meshes())
	add_child(ring)

	var meshes := _chunk_meshes(ring)
	assert_int(meshes.size()).is_equal(3)
	for index in range(meshes.size()):
		var mesh: Mesh = meshes[index]
		assert_int(mesh.get_surface_count()).is_equal(5)
		assert_str(String(mesh.resource_path)).is_equal(HIGH_PATHS[index])

	gate.force_gate = previous_force


# Un anillo sin low_tier_meshes (Dome_Base/Dome_Intro) es no-op en tier LOW.
func test_low_tier_without_variants_is_noop() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	gate.force_gate = true

	var ring := _make_ring("RingFloorNoVariants", [])
	add_child(ring)

	var meshes := _chunk_meshes(ring)
	assert_int(meshes.size()).is_equal(3)
	for index in range(meshes.size()):
		assert_str(String((meshes[index] as Mesh).resource_path)).is_equal(HIGH_PATHS[index])

	gate.force_gate = previous_force


# El nivel real asigna las variantes a los cinco pisos y en LOW quedan 3 superficies
# por piso (una por tercio) en lugar de 15.
func test_level_assigns_low_variants_to_all_floors() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	gate.force_gate = true

	var level = auto_free((load(LEVEL_SCENE) as PackedScene).instance())
	add_child(level)

	for floor_name in ["RingFloor", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]:
		var floor_node: Spatial = level.get_node("Hub/" + floor_name)
		assert_int(floor_node.low_tier_meshes.size()).is_equal(3)
		var surfaces := 0
		for mesh in _chunk_meshes(floor_node):
			surfaces += (mesh as Mesh).get_surface_count()
		assert_int(surfaces).is_equal(3)

	gate.force_gate = previous_force
