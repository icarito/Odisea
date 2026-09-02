extends SceneTree

# Arregla el winding invertido de las superficies horneadas que se compensaron con CULL_FRONT.
#
# EL BUG: varias superficies de los .mesh horneados quedaron con los triangulos al reves.
# Se veian bien porque el material las tapaba con params_cull_mode = CULL_FRONT, pero GLES3
# considera esos fragmentos back-facing y les DA VUELTA LA NORMAL, asi que N·L queda negativo
# y la superficie no recibe NINGUNA luz dinamica. El lightmap se seguia viendo (es un lookup
# por UV2, no depende de la normal), asi que el piso parecia iluminado y en realidad estaba
# mostrando solo el horneado: la linterna del jugador no lo tocaba nunca.
#
# Medido en Dome_Intro con camara y luz fijas (delta = brillo con luz ON menos luz OFF sobre
# el piso): 0.0010 como estaba, 0.6520 con el winding corregido. Un plano vanilla en el mismo
# punto daba 1.96, o sea que antes recibia ~0.
#
# EL ARREGLO: dar vuelta el orden de los indices (a, b, c -> a, c, b) y devolver el material
# a CULL_BACK. Las posiciones, normales y UV2 no se tocan, asi que el .lmbake existente sigue
# siendo valido y no hay que re-hornear.
#
# Idempotente: solo toca superficies que hoy estan en CULL_FRONT.
#
#   godot3-bin --no-window -s tools/fix_baked_mesh_winding.gd
#
# ponytail: reescribe el .mesh en el lugar. Si el pipeline de horneado vuelve a generar el
# winding invertido, esto se corre de nuevo despues del bake en vez de parchear a mano.

const OBJETIVOS := [
	"res://core_v2/levels/interiors/DomeTerraceFloor_baked.mesh",
	"res://core_v2/levels/interiors/DomeTerrace_baked.mesh",
]


func _init() -> void:
	for ruta in OBJETIVOS:
		_arreglar(ruta)
	quit()


func _arreglar(ruta: String) -> void:
	var original = ResourceLoader.load(ruta, "", true)
	if not (original is ArrayMesh):
		print("[fix] %s: no es ArrayMesh, se saltea" % ruta)
		return

	var salida := ArrayMesh.new()
	salida.lightmap_size_hint = original.lightmap_size_hint
	var corregidas := 0

	for s in range(original.get_surface_count()):
		var arrays: Array = original.surface_get_arrays(s)
		var material = original.surface_get_material(s)
		var invertir := material is SpatialMaterial \
			and int(material.params_cull_mode) == SpatialMaterial.CULL_FRONT

		if invertir:
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.size() < 3:
				# Sin indices habria que reordenar TODOS los atributos por terna; ninguna de
				# las superficies objetivo esta asi, y adivinar en silencio seria peor.
				push_error("[fix] %s surf %d no tiene indices; se deja como esta" % [ruta.get_file(), s])
			else:
				arrays[Mesh.ARRAY_INDEX] = _invertir_indices(indices)
				material = material.duplicate()
				material.params_cull_mode = SpatialMaterial.CULL_BACK
				corregidas += 1

		salida.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		salida.surface_set_material(s, material)
		salida.surface_set_name(s, original.surface_get_name(s))

	if corregidas == 0:
		print("[fix] %s: nada que corregir (ya esta en CULL_BACK)" % ruta.get_file())
		return

	var err := ResourceSaver.save(ruta, salida)
	print("[fix] %s: %d superficie(s) corregida(s), err=%d" % [ruta.get_file(), corregidas, err])


# a, b, c -> a, c, b. Sin indices (mesh no indexado) se invierte por terna de vertices,
# que es el mismo criterio.
func _invertir_indices(indices) -> PoolIntArray:
	var fuente: PoolIntArray = indices if indices != null else PoolIntArray()
	var invertido := PoolIntArray()
	var triangulos := int(fuente.size() / 3)
	for t in range(triangulos):
		invertido.append(fuente[t * 3 + 0])
		invertido.append(fuente[t * 3 + 2])
		invertido.append(fuente[t * 3 + 1])
	return invertido
