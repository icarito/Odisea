extends SceneTree

# Repunta los .material de los props importados a texturas externas.
#
#   godot3-bin --path . --no-window -s tools/relink_prop_materials.gd
#
# Los .glb de Sketchfab traen las texturas embebidas, asi que el importador las mete
# DENTRO de cada .material (y de la .scn, y de cada .mesh que referencie ese material):
# la misma textura viaja varias veces y un solo prop se come decenas de MB del repo.
# Este script cambia cada slot de textura por el .png extraido a disco (ver
# tools/extract_glb_textures.py), sin tocar ningun otro parametro del material: lo que
# decidio el importador se conserva.
#
# El .import de cada .glb tiene materials/keep_on_reimport=true, asi que un reimport
# posterior respeta estos archivos en vez de volver a embeber.

const JOBS := [
	{"material": "res://assets/models/free_airlock_door/lambert2.material", "prefix": "res://assets/models/free_airlock_door/textures/lambert2"},
	{"material": "res://assets/models/free_airlock_door/lambert3.material", "prefix": "res://assets/models/free_airlock_door/textures/lambert3"},
	{"material": "res://assets/models/palanca_pedestal/Material_001.material", "prefix": "res://assets/models/palanca_pedestal/textures/Material_001"},
	{"material": "res://assets/models/industrial_lever/lver.material", "prefix": "res://assets/models/industrial_lever/textures/lver"}
]

# Slot del material -> sufijo del .png extraido.
const SLOTS := {
	"albedo_texture": "_albedo",
	"normal_texture": "_normal",
	"emission_texture": "_emission",
	"metallic_texture": "_orm",
	"roughness_texture": "_orm",
	"ao_texture": "_orm"
}

func _init():
	for job in JOBS:
		var path: String = job["material"]
		if not ResourceLoader.exists(path):
			printerr("[relink] no existe ", path)
			continue
		var before: int = _size(path)
		var mat: SpatialMaterial = load(path) as SpatialMaterial
		if mat == null:
			printerr("[relink] no es SpatialMaterial: ", path)
			continue

		var swapped := []
		for slot in SLOTS:
			var current: Texture = mat.get(slot)
			if current == null:
				continue
			# Las embebidas quedan como subrecurso ("...material::2"); si ya apunta a un
			# archivo propio no hay nada que hacer.
			if current.resource_path != "" and not ("::" in current.resource_path):
				continue
			var tex_path: String = job["prefix"] + SLOTS[slot] + ".png"
			if not ResourceLoader.exists(tex_path):
				printerr("[relink] falta la textura ", tex_path, " para ", slot)
				continue
			mat.set(slot, load(tex_path))
			swapped.append(slot)

		var err = ResourceSaver.save(path, mat)
		print("[t] %s  %.1f KB -> %.1f KB  slots=%s err=%d" % [path, before / 1024.0, _size(path) / 1024.0, str(swapped), err])
	quit()

func _size(path: String) -> int:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return 0
	var s := f.get_len()
	f.close()
	return s
