extends SceneTree

# Rebuild with:
# godot3-bin --no-window --audio-driver Dummy --path . \
#   -s res://tools/bake_dome_wall_sconces.gd

const DOME_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const MESH_PATH := "res://core_v2/props/scifi_lights/IndustrialWallLampLOD.mesh"
const OUTPUT_PATH := "res://core_v2/levels/interiors/DomeIntro_WallLightFixtures.tres"
const BATCH_PATH := "res://core_v2/levels/interiors/DomeIntro_WallLightFixtures_%02d.tres"
const GLOW_OUTPUT_PATH := "res://core_v2/levels/interiors/DomeIntro_WallLightBulbGlows.tres"
const GLOW_BATCH_PATH := "res://core_v2/levels/interiors/DomeIntro_WallLightBulbGlows_%02d.tres"
const FIXTURE_SCALE := 2.0
const WALL_OFFSET := 0.30
const SECTOR_COUNT := 8
const BULB_OFFSET := Vector3(0.0, 0.0, 0.11)
const GLOW_SCALE := 0.35

func _init() -> void:
	var packed: PackedScene = load(DOME_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load Dome_Intro")
		return
	var root: Node = packed.instance()
	var markers: MultiMeshInstance = root.get_node("WallLights/Markers") as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		root.free()
		_fail("WallLights/Markers has no baked MultiMesh")
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = load(MESH_PATH) as Mesh
	multimesh.instance_count = markers.multimesh.instance_count
	for index in range(multimesh.instance_count):
		multimesh.set_instance_transform(index, _fixture_transform(markers, index))
	var result: int = ResourceSaver.save(OUTPUT_PATH, multimesh)
	var glows: MultiMesh = markers.multimesh.duplicate(true) as MultiMesh
	for index in range(glows.instance_count):
		var glow_transform: Transform = glows.get_instance_transform(index)
		glow_transform.origin = multimesh.get_instance_transform(index).xform(BULB_OFFSET)
		glow_transform.basis = glow_transform.basis.scaled(Vector3.ONE * GLOW_SCALE)
		glows.set_instance_transform(index, glow_transform)
	result = ResourceSaver.save(GLOW_OUTPUT_PATH, glows)
	if result != OK:
		root.free()
		_fail("Could not save bulb glow MultiMesh")
		return
	for batch_index in range(SECTOR_COUNT):
		var glow_count: int = int(ceil(float(glows.instance_count - batch_index) / float(SECTOR_COUNT)))
		var glow_batch := MultiMesh.new()
		glow_batch.transform_format = MultiMesh.TRANSFORM_3D
		glow_batch.color_format = glows.color_format
		glow_batch.mesh = glows.mesh
		glow_batch.instance_count = glow_count
		for local_index in range(glow_count):
			var source_index: int = batch_index + local_index * SECTOR_COUNT
			glow_batch.set_instance_transform(local_index, glows.get_instance_transform(source_index))
			glow_batch.set_instance_color(local_index, glows.get_instance_color(source_index))
		result = ResourceSaver.save(GLOW_BATCH_PATH % batch_index, glow_batch)
		if result != OK:
			root.free()
			_fail("Could not save glow batch %d" % batch_index)
			return
	for batch_index in range(SECTOR_COUNT):
		var count: int = int(ceil(float(multimesh.instance_count - batch_index) / float(SECTOR_COUNT)))
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = multimesh.mesh
		batch.instance_count = count
		for local_index in range(count):
			batch.set_instance_transform(local_index, multimesh.get_instance_transform(batch_index + local_index * SECTOR_COUNT))
		result = ResourceSaver.save(BATCH_PATH % batch_index, batch)
		if result != OK:
			root.free()
			_fail("Could not save fixture batch %d" % batch_index)
			return
	root.free()
	if result != OK:
		_fail("ResourceSaver failed with code %d" % result)
		return
	print("Baked %d wall sconces to %s" % [multimesh.instance_count, OUTPUT_PATH])
	quit()

func _fixture_transform(markers: MultiMeshInstance, index: int) -> Transform:
	var marker_transform: Transform = markers.multimesh.get_instance_transform(index)
	var marker: Vector3 = markers.transform.xform(marker_transform.origin)
	var outward: Vector3 = marker.normalized()
	var inward: Vector3 = -outward
	var right: Vector3 = Vector3.UP.cross(inward).normalized()
	var up: Vector3 = inward.cross(right).normalized()
	var basis := Basis(right, up, inward).scaled(Vector3.ONE * FIXTURE_SCALE)
	return Transform(basis, marker + outward * WALL_OFFSET)

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
