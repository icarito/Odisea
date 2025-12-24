# tools/run_replay.gd
# Headless runner to start playback of a replay file (first arg or latest)
var args = OS.get_cmdline_args()
var replay_path = ""
if args.size() > 0:
	replay_path = args[0]
else:
	# Find latest replay in res://replays/
	var dir = Directory.new()
	if dir.open("res://replays/") == OK:
		dir.list_dir_begin(true, true)
		var files = []
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				files.append(fname)
			fname = dir.get_next()
		files.sort()
		if files.size() > 0:
			replay_path = "res://replays/" + files[files.size() - 1]

print("run_replay: selected replay=", replay_path)

# Wait one idle frame for autoloads
yield(get_tree(), "idle_frame")
if has_node("/root/ReplayManager"):
	var rm = get_node("/root/ReplayManager")
	if replay_path != "":
		rm.start_playback(replay_path, true)
	else:
		print("No replay file provided or found.")
else:
	print("ReplayManager not found in autoloads.")

# Run until playback stops
while true:
	yield(get_tree(), "idle_frame")
	# simple exit condition: when ReplayManager mode != PLAYBACK
	if has_node("/root/ReplayManager"):
		var rm2 = get_node("/root/ReplayManager")
		if rm2.mode != null and rm2.mode != rm2.ReplayMode.PLAYBACK:
			print("Playback finished or mode changed to ", rm2.mode)
			break

print("Runner exiting.")
get_tree().quit()
