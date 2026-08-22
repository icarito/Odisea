# File operations helper for Godot 3.x
# Used by tokenizer and other core files

extends Object

func file_exists(file_path: String) -> bool:
	var file = File.new()
	return file.file_exists(file_path)

func open_read(file_path: String):
	var file = File.new()
	var err = file.open(file_path, File.READ)
	if err != OK:
		return null
	return file

func open_append(file_path: String):
	var file = File.new()
	var err = file.open(file_path, File.READ_WRITE)
	if err != OK:
		err = file.open(file_path, File.WRITE)
		if err != OK:
			return null
	file.seek_end()
	return file

func close_file(file):
	if file != null:
		file.close()

func write_line(file, text: String):
	if file != null:
		file.store_string(text + "\n")

func parse_json(content: String) -> Dictionary:
	return parse_json_text(content)

func parse_json_text(text: String) -> Dictionary:
	var parse_result = JSON.parse(text)
	if parse_result.error != OK:
		return {}
	if parse_result.result is Dictionary:
		return parse_result.result
	return {}

func stringify_json(data: Dictionary) -> String:
	return to_json(data)

func timestamp_utc() -> String:
	var d = OS.get_datetime(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		d.year, d.month, d.day, d.hour, d.minute, d.second
	]
