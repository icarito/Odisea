extends SceneTree

# verify_scaffold_sectors.gd — Comprueba que los sectores horneados de cada grupo
# de andamios suman exactamente la geometria de la malla combinada. Un sector
# perdido pasa desapercibido a simple vista (queda un hueco en una sola rebanada
# angular), asi que conviene verificarlo con numeros.
#
# Run: godot3-bin --no-window -s tools/verify_scaffold_sectors.gd

const DIR := "res://core_v2/levels/interiors/"
const GROUPS := ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
const SECTOR_COUNT := 8

func _init() -> void:
	var failed := false
	for group_name in GROUPS:
		var combined: ArrayMesh = load(DIR + "DomeIntro_%s_baked.mesh" % group_name)
		if combined == null:
			printerr("VERIFY:%s missing combined mesh" % group_name)
			failed = true
			continue
		var total: int = _vertex_count(combined)
		var sector_total := 0
		var present := []
		for i in range(SECTOR_COUNT):
			var path: String = DIR + "DomeIntro_%s_sector_%02d.mesh" % [group_name, i]
			var file := File.new()
			if not file.file_exists(path):
				continue
			var sector: ArrayMesh = load(path)
			if sector == null:
				printerr("VERIFY:%s sector %02d failed to load" % [group_name, i])
				failed = true
				continue
			present.append(i)
			sector_total += _vertex_count(sector)
		var ok: bool = sector_total == total
		if not ok:
			failed = true
		print("VERIFY:%s combined=%d sectors=%d (%s) sector_verts=%d %s" % [
			group_name, total, present.size(), str(present), sector_total,
			"OK" if ok else "MISMATCH"])
	quit(1 if failed else 0)

# Solo triangulos con area: el reparto en sectores descarta los degenerados a
# proposito (los polos de cada SphereMesh de las juntas aportan 24 por esfera), y
# contarlos daria una diferencia fija que no significa geometria perdida.
func _vertex_count(mesh: ArrayMesh) -> int:
	var count := 0
	for i in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(i)
		var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var indexed: bool = indices is PoolIntArray and (indices as PoolIntArray).size() > 0
		var total: int = (indices as PoolIntArray).size() if indexed else vertices.size()
		for triangle in range(total / 3):
			var a: Vector3 = vertices[(indices as PoolIntArray)[triangle * 3] if indexed else triangle * 3]
			var b: Vector3 = vertices[(indices as PoolIntArray)[triangle * 3 + 1] if indexed else triangle * 3 + 1]
			var c: Vector3 = vertices[(indices as PoolIntArray)[triangle * 3 + 2] if indexed else triangle * 3 + 2]
			if (b - a).cross(c - a).length_squared() > 0.00000001:
				count += 3
	return count
