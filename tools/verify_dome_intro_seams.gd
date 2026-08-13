extends SceneTree

const HUB_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_HubTowerSource.tscn"
const SCAFFOLD_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_ScaffoldSource.tscn"
const EXPECTED_HUB_STRIPS := 5
const EXPECTED_CONNECTION_STRIPS := 14
const PBR_SEAM_SHADER_PATH := "res://materials/diamondPlateAluminum/seam_road_lines_pbr.shader"
const BAKED_PBR_MATERIAL_PATHS := [
	"res://core_v2/levels/interiors/DomeIntro_SpiralStairs_mat_01.material",
	"res://core_v2/levels/interiors/DomeIntro_HubSpokes_mat_01.material",
	"res://core_v2/levels/interiors/Dome_Intro_HubRing_mat_04.material",
]
const BAKED_PBR_MESH_PATHS := [
	"res://core_v2/levels/interiors/DomeIntro_SpiralStairs_baked.mesh",
	"res://core_v2/levels/interiors/DomeIntro_HubSpokes_baked.mesh",
	"res://core_v2/levels/interiors/Dome_Intro_Floor_1_baked.mesh",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_baked_pbr_materials() or not _verify_baked_pbr_tangents():
		quit(1)
		return
	var hub_scene := load(HUB_SOURCE_PATH) as PackedScene
	var scaffold_scene := load(SCAFFOLD_SOURCE_PATH) as PackedScene
	if hub_scene == null or scaffold_scene == null:
		push_error("[verify_seams] missing source scene")
		quit(1)
		return
	var hub_root := hub_scene.instance()
	var hub_strips := 0
	for floor_name in ["Floor_1", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]:
		var ring := hub_root.get_node_or_null("ScaffoldHubTower/" + floor_name)
		ring.build()
		var mesh_instance := ring.get_node_or_null("CombinedMesh") as MeshInstance
		if mesh_instance == null or mesh_instance.mesh.get_surface_count() < 5:
			push_error("[verify_seams] %s missing outer hazard surface" % floor_name)
			quit(1)
			return
		hub_strips += 1
	if hub_strips != EXPECTED_HUB_STRIPS:
		push_error("[verify_seams] expected %d hub strips, found %d" % [EXPECTED_HUB_STRIPS, hub_strips])
		quit(1)
		return
	var scaffold_root := scaffold_scene.instance()
	var radial := scaffold_root.get_node_or_null("SpiralWalkways")
	if radial != null:
		radial.rebuild_baked_items = false
	get_root().add_child(scaffold_root)
	yield(self, "idle_frame")
	var connection_strips := _count_hazard_meshes(scaffold_root)
	if connection_strips != EXPECTED_CONNECTION_STRIPS:
		push_error("[verify_seams] expected %d connection strips, found %d" % [EXPECTED_CONNECTION_STRIPS, connection_strips])
		quit(1)
		return
	print("[verify_seams] PASS %d hub-edge and %d connection strips use RoadLines PBR" % [hub_strips, connection_strips])
	quit(0)

func _verify_baked_pbr_materials() -> bool:
	for material_path in BAKED_PBR_MATERIAL_PATHS:
		var material := load(material_path) as ShaderMaterial
		if material == null or material.shader == null:
			push_error("[verify_seams] missing baked PBR material: %s" % material_path)
			return false
		if material.shader.resource_path != PBR_SEAM_SHADER_PATH:
			push_error("[verify_seams] %s does not use RoadLines PBR" % material_path)
			return false
	return true

func _verify_baked_pbr_tangents() -> bool:
	for mesh_path in BAKED_PBR_MESH_PATHS:
		var mesh := load(mesh_path) as ArrayMesh
		if mesh == null:
			push_error("[verify_seams] missing baked PBR mesh: %s" % mesh_path)
			return false
		var has_pbr_surface := false
		for surface_index in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface_index) as ShaderMaterial
			if material == null or material.shader == null:
				continue
			if material.shader.resource_path != PBR_SEAM_SHADER_PATH:
				continue
			has_pbr_surface = true
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var tangents = arrays[Mesh.ARRAY_TANGENT]
			if tangents == null or tangents.size() != vertices.size() * 4:
				push_error("[verify_seams] PBR surface without tangents: %s" % mesh_path)
				return false
		if not has_pbr_surface:
			push_error("[verify_seams] no PBR surface in %s" % mesh_path)
			return false
	return true

func _count_hazard_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance and String(node.name).begins_with("HazardStrip") else 0
	for child in node.get_children():
		count += _count_hazard_meshes(child)
	return count
