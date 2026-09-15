extends SceneTree

# Verifies hand-authored Dome_Intro content that must survive pipe bakes. This script
# only instances the scene; it never opens the editor nor saves any resource.
const DOME_SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const TERMINAL_UI_PATH := "SuspendedCryoDiagnostics/Carriage/HangingDisplay/Viewport/TerminalUI"
const DIAGNOSTICS_PATH := "SuspendedCryoDiagnostics/Carriage/HangingDisplay/Viewport/CryoDiagnosticsUI"
const BAKED_LIGHTMAP_PATH := "BakedLightmap"
const DIRECTIONAL_LIGHT_PATH := "DirectionalLight"
const TERRACE_FLOOR_PATH := "Terrace/TerraceFloor"
const DOME_SHELL_PATH := "Terrace/DomeShell"
const DOME_SHADER_PATH := "res://core_v2/levels/interiors/shaders/dome_wall_cylindrical.shader"

func _init() -> void:
	var scene: PackedScene = load(DOME_SCENE_PATH) as PackedScene
	if scene == null:
		_fail("could not load " + DOME_SCENE_PATH)
		return
	var dome: Node = scene.instance()
	for path in [TERMINAL_UI_PATH, DIAGNOSTICS_PATH]:
		if dome.get_node_or_null(path) == null:
			_fail("required node missing: " + path)
			return
	var baked_lightmap: BakedLightmap = dome.get_node_or_null(BAKED_LIGHTMAP_PATH) as BakedLightmap
	if baked_lightmap == null or baked_lightmap.light_data == null:
		_fail("BakedLightmap or its light_data is missing")
		return
	var directional: DirectionalLight = dome.get_node_or_null(DIRECTIONAL_LIGHT_PATH) as DirectionalLight
	# En Godot 3, la visibilidad no excluye una luz del BakedLightmap, pero su
	# bake mode Disabled sí. Queda oculta para runtime y Bake All para que tanto
	# el botón Bake como el script incluyan su iluminación y sombras estáticas.
	if directional == null or directional.light_bake_mode != Light.BAKE_ALL or not directional.shadow_enabled or directional.visible:
		_fail("DirectionalLight must be hidden at runtime and set to Bake All for static lightmaps")
		return
	var terrace_floor: MeshInstance = dome.get_node_or_null(TERRACE_FLOOR_PATH) as MeshInstance
	var dome_shell: MeshInstance = dome.get_node_or_null(DOME_SHELL_PATH) as MeshInstance
	if terrace_floor == null or dome_shell == null:
		_fail("Terrace floor or dome shell is missing")
		return
	# En Godot 3 el receptor debe ser único por instancia: BakedLightmapData puede
	# perder el vínculo en runtime cuando apunta a un ArrayMesh externo compartido.
	if terrace_floor.mesh == null or not terrace_floor.mesh.resource_local_to_scene:
		_fail("TerraceFloor mesh must be local to scene for baked lightmap runtime binding")
		return
	# Domo V2 (tools/dome_v2/scene_dome.py): la carcasa trae bores y franjas en
	# superficies aparte; basta con que alguna lleve el shader cilíndrico.
	var has_wall_shader := false
	for surface in range(dome_shell.mesh.get_surface_count()):
		var shell_material: Material = dome_shell.mesh.surface_get_material(surface)
		if shell_material is ShaderMaterial and (shell_material as ShaderMaterial).shader != null \
			and (shell_material as ShaderMaterial).shader.resource_path == DOME_SHADER_PATH:
			has_wall_shader = true
	if not has_wall_shader:
		_fail("Dome shell must preserve dome_wall_cylindrical.shader")
		return
	var missing_uv2: Array = []
	var baked_mesh_count: int = _collect_baked_mesh_uv2(dome, missing_uv2)
	if not missing_uv2.empty():
		_fail("baked meshes without UV2: " + PoolStringArray(missing_uv2).join(", "))
		return
	print("[verify_dome_intro_contract] PASS: UI, lightmap, DirectionalLight and %d baked meshes with UV2" % baked_mesh_count)
	quit(0)

func _collect_baked_mesh_uv2(node: Node, missing_uv2: Array) -> int:
	var baked_mesh_count: int = 0
	if node is MeshInstance and node.use_in_baked_light and node.mesh != null:
		baked_mesh_count += 1
		var has_uv2: bool = false
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			if arrays.size() > Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() > 0:
				has_uv2 = true
				break
		if not has_uv2:
			missing_uv2.append(node.name + " (" + node.mesh.resource_path + ")")
	for child in node.get_children():
		baked_mesh_count += _collect_baked_mesh_uv2(child, missing_uv2)
	return baked_mesh_count

func _fail(message: String) -> void:
	push_error("[verify_dome_intro_contract] " + message)
	quit(1)
