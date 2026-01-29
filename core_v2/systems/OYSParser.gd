# OYSParser.gd: OdysseyScript to Replay JSON
extends Reference

# Minimal parser for OYS (OdysseyScript) DSL
# Only supports a subset for demo: SET, FW, WAIT, JUMP, ASSERT, SECTION, END

func parse_file(path: String) -> Dictionary:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		printerr("OYSParser: Could not open file: ", path)
		return {}
	var lines = []
	while not file.eof_reached():
		lines.append(file.get_line().strip_edges())
	file.close()
	return _parse_lines(lines)

func _parse_lines(lines: Array) -> Dictionary:
	var replay = {
		"meta": {"source": "OYS", "generated": true},
		"input": [],
		"asserts": []
	}
	var frame = 0
	for line in lines:
		if line == "" or line.begins_with("//"): continue
		var tokens = line.split(" ", false)
		match tokens[0]:
			"SET":
				# Only support SET pos (x, y, z)
				if tokens.size() >= 3 and tokens[1] == "pos":
					var pos = tokens[2].strip_edges("() ").split(",")
					if pos.size() == 3:
						replay["meta"]["start_pos"] = [pos[0].to_float(), pos[1].to_float(), pos[2].to_float()]
				continue
			"FW":
				# Move forward for N seconds (assume 60fps)
				var dur = tokens[1].to_float()
				var frames = int(dur * 60)
				for i in range(frames):
					replay["input"].append({"frame": frame, "move": "FW"})
					frame += 1
				continue
			"WAIT":
				var dur = tokens[1].to_float()
				frame += int(dur * 60)
				continue
			"JUMP":
				var dur = 0.2
				if tokens.size() > 1:
					dur = tokens[1].to_float()
				var frames = int(dur * 60)
				for i in range(frames):
					replay["input"].append({"frame": frame, "jump": true})
					frame += 1
				continue
			"ASSERT":
				# Only support pos.z > N
				if tokens.size() >= 4 and tokens[1] == "pos.z" and tokens[2] == ">":
					replay["asserts"].append({"frame": frame, "pos.z_gt": tokens[3].to_float()})
				continue
			_:
				continue
	return replay
