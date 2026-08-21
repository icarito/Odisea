extends SceneTree

# Verifies hand-authored Dome_Intro content that must survive pipe bakes. This script
# only instances the scene; it never opens the editor nor saves any resource.
const DOME_SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const TERMINAL_UI_PATH := "SuspendedCryoDiagnostics/Carriage/HangingDisplay/Viewport/TerminalUI"
const DIAGNOSTICS_PATH := "SuspendedCryoDiagnostics/Carriage/HangingDisplay/Viewport/CryoDiagnosticsUI"
const BAKED_LIGHTMAP_PATH := "BakedLightmap"

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
	print("[verify_dome_intro_contract] TerminalUI, diagnostics and BakedLightmap present")
	quit(0)

func _fail(message: String) -> void:
	push_error("[verify_dome_intro_contract] " + message)
	quit(1)
