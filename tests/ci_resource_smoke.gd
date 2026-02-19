extends SceneTree

const CRITICAL_RESOURCES := [
	"res://core_v2/ui/retro/RetroOS.tres",
	"res://core_v2/components/PushableBoxV2.tscn",
	"res://core_v2/components/SlidingObjectV2.tscn",
	# Fails early when the GLB import pipeline is still incomplete.
	"res://core_v2/actors/Pilot_v2.tscn",
]

func _init() -> void:
	var failed := []
	for path in CRITICAL_RESOURCES:
		var res = load(path)
		if res == null:
			failed.append(path)
			printerr("[CI_SMOKE] Failed to load: ", path)
		else:
			print("[CI_SMOKE] OK: ", path)

	if failed.size() > 0:
		printerr("[CI_SMOKE] Missing resources count: ", failed.size())
		quit(1)
		return

	print("[CI_SMOKE] Critical resources loaded successfully.")
	quit(0)
