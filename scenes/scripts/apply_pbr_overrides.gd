## Aplica overrides PBR con normales a las tablas (piso) y barriles al cargar la escena.
## Mantiene el albedo/ajustes existentes cuando es posible y solo añade normal map y filtrado.

extends Node

const FLOOR_PATH := NodePath("Platform/MeshInstance3D")
const BARRELS_PATH := NodePath("barrels2/barrels")

const PLANKS_ALBEDO := "res://assets/planks.png"
const PLANKS_NORMAL := "res://assets/planks_normal.png"
const BARREL_ALBEDO := "res://scenes/Textures/barrel.png"
const BARREL_NORMAL := "res://scenes/Textures/barrel_normal.png"

@export var floor_normal_scale: float = -0.91
@export var barrel_normal_scale: float = 1.0

func _ready() -> void:
	# Script reubicado en scenes/scripts/system/ para organización.
	_apply_floor_override()
	_apply_barrels_override()

func _apply_floor_override() -> void:
	# Buscar el mesh del piso desde el nodo raíz padre
	var root = get_parent()
	if not root:
		push_warning("No se encontró nodo padre para buscar el piso")
		return
	
	var mi: MeshInstance3D = null
	var platform = root.get_node_or_null("Platform")
	if platform:
		mi = platform.get_node_or_null("MeshInstance3D")
	
	if mi == null:
		push_warning("No se encontró el Mesh del piso (buscado en Platform/MeshInstance3D)")
		return
		
	var ntex := load(PLANKS_NORMAL) as Texture2D
	if ntex == null:
		push_warning("No se encontró normal del piso: %s" % PLANKS_NORMAL)
		return
	var albedo := load(PLANKS_ALBEDO) as Texture2D
	_apply_normal_override(mi, ntex, floor_normal_scale, albedo)

func _apply_barrels_override() -> void:
	# Buscar barriles desde el nodo raíz padre
	var root = get_parent()
	if not root:
		push_warning("No se encontró nodo padre para buscar barriles")
		return
		
	var barrels_node = root.get_node_or_null("barrels2")
	if barrels_node:
		barrels_node = barrels_node.get_node_or_null("barrels")
	
	if barrels_node == null:
		push_warning("No se encontró el nodo de barriles (buscado en barrels2/barrels)")
		return
		
	var ntex := load(BARREL_NORMAL) as Texture2D
	if ntex == null:
		push_warning("No se encontró normal del barril: %s" % BARREL_NORMAL)
		return
	var applied := 0
	for mi in _find_all_mesh_instances(barrels_node):
		if mi.mesh == null:
			continue
		var sc: int = mi.mesh.get_surface_count()
		for i in sc:
			var s_mat: Material = mi.mesh.surface_get_material(i)
			if not (s_mat is StandardMaterial3D):
				continue
			var mat := (s_mat as StandardMaterial3D).duplicate()
			# Detectar material de madera por la textura de albedo
			var albedo_tex: Texture2D = mat.albedo_texture
			var is_barrel_wood := false
			if albedo_tex:
				var rp := String(albedo_tex.resource_path)
				is_barrel_wood = rp.findn("barrel") != -1
			# Aplicar normal solo a la madera; al metal no le imponemos normal si no existe
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if is_barrel_wood:
				mat.normal_enabled = true
				mat.normal_texture = ntex
				mat.normal_scale = barrel_normal_scale
			mi.set_surface_override_material(i, mat)
			applied += 1
	if applied == 0:
		push_warning("No se pudieron aplicar materiales por-superficie a los barriles (¿materiales no StandardMaterial3D?)")

func _apply_normal_override(mi: MeshInstance3D, normal_tex: Texture2D, normal_scale: float, fallback_albedo: Texture2D) -> void:
	var base_mat: Material = mi.material_override
	if base_mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
		base_mat = mi.mesh.surface_get_material(0)
	var mat: StandardMaterial3D
	if base_mat is StandardMaterial3D:
		mat = (base_mat as StandardMaterial3D).duplicate()
	else:
		mat = StandardMaterial3D.new()
		if fallback_albedo:
			mat.albedo_texture = fallback_albedo
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = normal_scale
	# Filtrado con mipmaps y anisotrópico (Godot 4)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat

func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	# Búsqueda en anchura para encontrar el primer MeshInstance3D hijo
	var queue: Array = [root]
	while queue.size() > 0:
		var n: Node = queue.pop_front()
		if n is MeshInstance3D:
			return n as MeshInstance3D
		for c in n.get_children():
			queue.append(c)
	return null

func _find_all_mesh_instances(root: Node) -> Array:
	var found: Array = []
	var queue: Array = [root]
	while queue.size() > 0:
		var n: Node = queue.pop_front()
		if n is MeshInstance3D:
			found.append(n)
		for c in n.get_children():
			queue.append(c)
	return found
