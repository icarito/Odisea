extends Object
const _VERBOSE_TRACE = false

# File discovery for Godot 3.x (Directory, plus_file)

const MAX_DEPTH = 50  # Prevent infinite recursion

var _pattern_cache: Dictionary = {}

func find_files(root_path: String, include_patterns: Array, exclude_patterns: Array) -> Array:
	var files: Array = []
	root_path = _sanitize_path(root_path)
	if _VERBOSE_TRACE: print("[FileDiscovery] Starting file discovery in: %s" % root_path)
	if _VERBOSE_TRACE: print("[FileDiscovery] Include patterns: %s" % str(include_patterns))
	if _VERBOSE_TRACE: print("[FileDiscovery] Exclude patterns: %s" % str(exclude_patterns))
	
	var dir = Directory.new()
	if dir.open(root_path) != OK:
		if _VERBOSE_TRACE: print("[FileDiscovery] ERROR: Failed to open root path: %s" % root_path)
		return files
	
	_find_files_recursive(root_path, root_path, include_patterns, exclude_patterns, files, 0)
	if _VERBOSE_TRACE: print("[FileDiscovery] File discovery complete, found %d files" % files.size())
	return files

func _sanitize_path(path: String) -> String:
	if path.length() == 0:
		return "."
	var sanitized = path.replace("\\", "/")
	while sanitized.find("../") >= 0:
		sanitized = sanitized.replace("../", "")
	if not sanitized.begins_with("res://"):
		while sanitized.begins_with("/"):
			sanitized = sanitized.substr(1, sanitized.length() - 1)
	return sanitized

func _find_files_recursive(root_path: String, current_path: String, include_patterns: Array, exclude_patterns: Array, files: Array, depth: int):
	if depth > MAX_DEPTH:
		if _VERBOSE_TRACE: print("[FileDiscovery] WARNING: Max depth reached at: %s" % current_path)
		return
	
	# Skip common large directories early
	var dir_name = current_path.get_file()
	if dir_name.begins_with(".") and dir_name != ".":
		return
	if dir_name == "node_modules" or dir_name == ".git" or dir_name == ".godot":
		return
	
	# Log progress every 10 directories
	if depth <= 2 and files.size() % 10 == 0 and files.size() > 0:
		if _VERBOSE_TRACE: print("[FileDiscovery] Progress: Found %d files so far, scanning: %s" % [files.size(), current_path])
	
	var dir = Directory.new()
	if dir.open(current_path) != OK:
		return
	
	var list_result = dir.list_dir_begin(true, false)  # Skip navigational and hidden
	if list_result != OK:
		return
	
	var file_name = dir.get_next()
	var file_count = 0
	
	while file_name != "":
		file_count += 1
		if file_count > 1000:  # Safety limit per directory
			if _VERBOSE_TRACE: print("[FileDiscovery] WARNING: Too many files in directory: %s (stopping at 1000)" % current_path)
			break
		
		if file_name.find("..") >= 0 or file_name.find("/") >= 0 or file_name.find("\\") >= 0:
			file_name = dir.get_next()
			continue
		
		var full_path: String = current_path.plus_file(file_name)
		full_path = _sanitize_path(full_path)
		
		var is_dir = dir.current_is_dir()
		
		if is_dir:
			# Skip if this directory should be excluded
			var relative_path = _make_relative(root_path, full_path)
			if not _is_excluded(relative_path, exclude_patterns):
				_find_files_recursive(root_path, full_path, include_patterns, exclude_patterns, files, depth + 1)
		else:
			if file_name.ends_with(".gd"):
				var relative_path = _make_relative(root_path, full_path)
				if _matches_patterns(relative_path, include_patterns, exclude_patterns):
					files.append(full_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _is_excluded(dir_path: String, exclude_patterns: Array) -> bool:
	# Trailing slash lets directory paths match "prefix/**" style patterns
	for pattern in exclude_patterns:
		if _match_pattern(dir_path, pattern) or _match_pattern(dir_path + "/", pattern):
			return true
	return false

func _make_relative(root_path: String, full_path: String) -> String:
	if full_path.begins_with(root_path):
		var relative = full_path.substr(root_path.length(), full_path.length() - root_path.length())
		if relative.begins_with("/") or relative.begins_with("\\"):
			relative = relative.substr(1, relative.length() - 1)
		return "res://" + relative.replace("\\", "/")
	return full_path

func _matches_patterns(file_path: String, include_patterns: Array, exclude_patterns: Array) -> bool:
	if include_patterns.size() == 0:
		return false
	var matches_include = false
	for pattern in include_patterns:
		if _match_pattern(file_path, pattern):
			matches_include = true
			break
	if not matches_include:
		return false
	for pattern in exclude_patterns:
		if _match_pattern(file_path, pattern):
			return false
	return true

func _match_pattern(file_path: String, pattern: String) -> bool:
	if pattern == "":
		return false
	var normalized_path = file_path.replace("\\", "/")
	var normalized_pattern = pattern.replace("\\", "/")
	if normalized_pattern == normalized_path:
		return true

	# Bare file names (e.g. "player.gd") match by base name anywhere in the tree
	if normalized_pattern.find("/") < 0 and normalized_pattern.ends_with(".gd") and normalized_pattern.find("*") < 0:
		return normalized_path.ends_with("/" + normalized_pattern) or normalized_path == normalized_pattern

	var regex = _get_pattern_regex(normalized_pattern)
	if regex == null:
		return false
	return regex.search(normalized_path) != null

func _get_pattern_regex(pattern: String):
	if _pattern_cache.has(pattern):
		return _pattern_cache[pattern]
	var regex = RegEx.new()
	if regex.compile(_glob_to_regex(pattern)) != OK:
		_pattern_cache[pattern] = null
		return null
	_pattern_cache[pattern] = regex
	return regex

func _glob_to_regex(pattern: String) -> String:
	var special = ".^$+(){}[]|\\"
	var out = "^"
	var i = 0
	while i < pattern.length():
		var c = pattern[i]
		if c == "*":
			if i + 1 < pattern.length() and pattern[i + 1] == "*":
				# "**/" spans zero or more directories, bare "**" spans anything
				if i + 2 < pattern.length() and pattern[i + 2] == "/":
					out += "(?:.*/)?"
					i += 3
					continue
				out += ".*"
				i += 2
				continue
			out += "[^/]*"
		elif c == "?":
			out += "[^/]"
		elif special.find(c) >= 0:
			out += "\\" + c
		else:
			out += c
		i += 1
	return out + "$"


