extends SceneTree

# bake_scaffold_low_variants.gd — HORNEA las variantes LOW de los andamios de
# RingHub (FD-316 tarea EE).
#
# El tier LOW venia OCULTANDO los trozos lejanos del andamio (culler de distancia
# del gate, 2d7b3d61) y el pop-in se notaba: el trozo entero desaparecia y dejaba
# un hueco. Este tool produce una variante LOW para cada sector horneado, del
# mismo prefijo y del mismo split angular que la de alta, para que el runtime
# cambie la MALLA a distancia (nunca la visibilidad).
#
# Que se quita: las superficies de BARANDA. En un SteelGratePlatform la baranda
# (RailTop/RailMid/RailPostA/B + los capuchones) es el detalle mas caro en
# vertices —~50-65% del sector— y el de menor silueta a distancia: tubos de 0.14 m
# que a partir de ~20 m miden menos de un pixel. El deck (rejilla) y el marco
# (patas, vigas, capuchones de esquina) se conservan: la pasarela no deja de
# leerse, solo pierde la baranda lejana. Es la reduccion parametrica de "menos
# segmentos de baranda" aplicada al producto ya horneado de la fuente
# (RingHub_ScaffoldSource.tscn), sin re-derivar geometria: se preservan UV2,
# normales y los MISMOS recursos de material compartidos, asi que la luz cocinada
# del lightmap no cambia.
#
# Como se identifica la baranda: su material es un SpatialMaterial con emision
# encendida (SteelGratePlatform._compact_material(is_rail=true)) y SIN alpha
# scissor (eso distingue la rejilla del deck, que tambien emite). El resto de
# superficies (rejilla, lados del deck, marco, franja de peligro) se copian tal
# cual, con su material de disco (resource_path intacto).
#
# Idempotente: siempre lee los sectores de alta y reescribe los _low_sector; hay
# que re-correrlo si se re-hornean los de alta (make bake-ringhub-hub).
#
# Run: tools/godot --path . --no-window -s tools/bake_scaffold_low_variants.gd

const DIR := "res://core_v2/levels/interiors/"
const PREFIX := "RingHub"
# Solo estos grupos entran a la variante LOW (los que el gate cambia a distancia).
const GROUPS := ["SpiralWalkways", "SpiralStairs"]
const SECTORS := 8

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	for group_name in GROUPS:
		for sector in range(SECTORS):
			var src_path: String = DIR + "%s_%s_sector_%02d.mesh" % [PREFIX, group_name, sector]
			if not ResourceLoader.exists(src_path):
				continue
			if not _bake_sector(group_name, sector, src_path):
				failures += 1
	if failures > 0:
		quit(1)
		return
	quit(0)

func _bake_sector(group_name: String, sector: int, src_path: String) -> bool:
	var out_path: String = DIR + "%s_%s_low_sector_%02d.mesh" % [PREFIX, group_name, sector]
	var high: ArrayMesh = load(src_path) as ArrayMesh
	if high == null:
		push_error("[bake_scaffold_low] no encuentro %s" % src_path)
		return false

	var low := ArrayMesh.new()
	low.lightmap_size_hint = high.lightmap_size_hint
	var kept := 0
	var dropped := 0
	for surface in range(high.get_surface_count()):
		var material: Material = high.surface_get_material(surface)
		if _is_rail_surface(material):
			dropped += 1
			continue
		# Copia la superficie tal cual (vertices, normales, UV1/UV2, tangentes e
		# indices) y le re-asigna el MISMO recurso de material de disco.
		low.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, high.surface_get_arrays(surface))
		low.surface_set_material(low.get_surface_count() - 1, material)
		kept += 1

	if kept == 0 or dropped == 0:
		# Sin barandas no hay variante que valga la pena (o el split de materiales
		# cambio): no se escribe nada para no romper la convencion del runtime.
		print("[bake_scaffold_low] %s: sin barandas detectadas, se omite" % src_path.get_file())
		return true
	if ResourceSaver.save(out_path, low) != OK:
		push_error("[bake_scaffold_low] no pude guardar %s" % out_path)
		return false

	print("[bake_scaffold_low] %s: %d superficies (%d barandas) / %d verts -> %d superficies / %d verts (%s)" % [
		src_path.get_file(), high.get_surface_count(), dropped, _vertex_count(high),
		low.get_surface_count(), _vertex_count(low), out_path.get_file()])
	return true

# Baranda: emision encendida y sin alpha scissor. La rejilla del deck tambien
# emite pero lleva alpha scissor (params_use_alpha_scissor), asi que queda afuera;
# el marco no emite.
func _is_rail_surface(material: Material) -> bool:
	if not (material is SpatialMaterial):
		return false
	var sm := material as SpatialMaterial
	return sm.emission_enabled and not sm.params_use_alpha_scissor

func _vertex_count(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays != null and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	return total
