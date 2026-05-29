extends GdUnitTestSuite

const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
const REQUIRED_HTML5_RESOURCES := [
	"res://models/Pilot/Climb_Loop.anim",
	"res://models/Pilot/Rokoko_Source_Climb.anim",
	"res://models/Pilot/SMPLH_Animation002.anim",
	"res://core_v2/props/HoloTerminalV2.tscn",
	"res://core_v2/props/WallTerminal.tscn",
	"res://core_v2/props/TableTerminal.tscn",
	"res://core_v2/things/HoloTerminalV2.gd",
	"res://core_v2/things/TerminalUI.tscn",
	"res://core_v2/ui/retro/DebugOverlay.tscn",
	"res://core_v2/ui/retro/OYSShell.tscn",
	"res://core_v2/ui/retro/OYS_Console.gd",
]

func test_html5_export_preset_includes_terminal_and_pilot_dependencies() -> void:
	var file := File.new()
	assert_int(file.open(EXPORT_PRESETS_PATH, File.READ)).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	var html5_start := text.find("\n[preset.3]\n")
	assert_int(html5_start).is_greater(-1)
	var html5_options := text.find("\n[preset.3.options]\n")
	assert_int(html5_options).is_greater(html5_start)

	var preset_text := text.substr(html5_start, html5_options - html5_start)
	for resource_path in REQUIRED_HTML5_RESOURCES:
		assert_bool(preset_text.find(resource_path) != -1).is_true()
