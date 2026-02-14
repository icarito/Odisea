extends Node
class_name OYS_Console

signal log_added(entry)
signal logs_cleared
signal cvar_changed(name, value)
signal command_executed(command, success, message)
signal run_oys_requested(path)
signal core_command_requested(command)

const FLAG_ARCHIVE := 1
const FLAG_CHEAT := 2

const MAX_HISTORY := 50
const MAX_LOG_LINES := 5000
const MAX_ALIAS_DEPTH := 8
const MAX_PIPE_STAGES := 3

const VFS_MOUNTS := ["/root", "/bin", "/scripts", "/proc"]
const ERR_NOT_FOUND := "ERR_NOT_FOUND"
const ERR_PERMISSION := "ERR_PERMISSION"
const ERR_IO := "ERR_IO"

const CHANNEL_COLORS := {
	"SYS": "#FFFFFF",
	"CORE": "#33FF33",
	"WARN": "#FFFF00",
	"ERR": "#FF3333",
	"AI": "#FF33FF"
}

var allow_cheats := false
var read_only := false

var _commands := {}
var _cvars := {}
var _aliases := {}
var _binds := {}
var _history := []
var _logs := []
var _filter_tag := ""
var _queue := []
var _cfg_path := "user://oys_shell.cfg"
var _active_interpreters := []
var _vfs_cwd := "/root"

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	_register_builtin_commands()
	_register_builtin_cvars()
	discover_commands()
	_load_cfg()
	add_log("SYS", "OYS-Shell initialized. Type 'help' for commands.")

func _process(_delta: float) -> void:
	var budget = 8
	while budget > 0 and _queue.size() > 0:
		var line = _queue.pop_front()
		_execute_line(line, 0)
		budget -= 1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_name = OS.get_scancode_string(event.scancode).to_upper()
		if _binds.has(key_name):
			enqueue_command(_binds[key_name])

func enqueue_command(line: String) -> void:
	var clean = _sanitize_input(line)
	if clean == "":
		return
	_queue.append(clean)
	_push_history(clean)

func add_log(tag: String, message: String) -> void:
	var t = tag.to_upper()
	if not CHANNEL_COLORS.has(t):
		t = "SYS"
	var entry = {
		"tag": t,
		"text": message,
		"color": CHANNEL_COLORS[t]
	}
	_logs.append(entry)
	while _logs.size() > MAX_LOG_LINES:
		_logs.pop_front()
	emit_signal("log_added", entry)

func clear_logs() -> void:
	_logs.clear()
	emit_signal("logs_cleared")

func get_logs() -> Array:
	if _filter_tag == "":
		return _logs.duplicate(true)
	var filtered := []
	for entry in _logs:
		if entry.get("tag", "") == _filter_tag:
			filtered.append(entry)
	return filtered

func get_history() -> Array:
	return _history.duplicate()

func get_filter_tag() -> String:
	return _filter_tag

func set_filter_tag(tag: String) -> void:
	_filter_tag = tag.to_upper().strip_edges()

func register_command(name: String, target: Object, method: String, description: String = "", usage: String = "", flags: int = 0) -> void:
	var cmd = name.to_lower().strip_edges()
	if cmd == "":
		return
	_commands[cmd] = {
		"target": target,
		"method": method,
		"description": description,
		"usage": usage,
		"flags": flags
	}

func register_cvar(name: String, var_type: int, default_value, description: String = "", min_value = null, max_value = null, flags: int = 0, callback_target: Object = null, callback_method: String = "") -> void:
	var key = name.to_lower().strip_edges()
	var value = _convert_to_type(default_value, var_type)
	_cvars[key] = {
		"type": var_type,
		"value": value,
		"default": value,
		"description": description,
		"min": min_value,
		"max": max_value,
		"flags": flags,
		"callback_target": callback_target,
		"callback_method": callback_method
	}

func set_cvar(name: String, raw_value) -> bool:
	var key = name.to_lower().strip_edges()
	if not _cvars.has(key):
		add_log("ERR", "Unknown cvar: %s" % key)
		return false
	var info = _cvars[key]
	var converted = _convert_to_type(raw_value, info.type)
	if converted == null:
		add_log("ERR", "Invalid value for cvar %s" % key)
		return false
	if info.type in [TYPE_INT, TYPE_REAL]:
		if info.min != null:
			converted = max(converted, info.min)
		if info.max != null:
			converted = min(converted, info.max)
	info.value = converted
	_cvars[key] = info
	_apply_cvar_callback(key, info)
	if int(info.flags) & FLAG_ARCHIVE:
		_save_cfg()
	emit_signal("cvar_changed", key, converted)
	return true

func get_cvar(name: String):
	var key = name.to_lower().strip_edges()
	if not _cvars.has(key):
		return null
	return _cvars[key].value

func get_autocomplete_candidates(input_text: String) -> Array:
	var text = input_text.strip_edges()
	var tokens = _tokenize(text)
	var ends_with_space = text.ends_with(" ")
	if tokens.empty():
		return _sorted_unique(_commands.keys() + _cvars.keys() + _aliases.keys())

	var current = ""
	if ends_with_space:
		current = ""
	else:
		current = String(tokens.pop_back())

	if tokens.empty():
		return _filter_prefix(_sorted_unique(_commands.keys() + _cvars.keys() + _aliases.keys()), current.to_lower())

	var cmd = String(tokens[0]).to_lower()
	if cmd == "set" or cmd == "get":
		if tokens.size() <= 1:
			return _filter_prefix(_cvars.keys(), current.to_lower())
		if cmd == "set" and tokens.size() >= 2:
			var cvar_name = String(tokens[1]).to_lower()
			if _cvars.has(cvar_name):
				return _suggest_cvar_values(cvar_name, current)

	if cmd == "filter":
		return _filter_prefix(["SYS", "CORE", "WARN", "ERR", "AI", "off"], current.to_upper())

	if cmd == "run":
		return _filter_prefix(_find_oys_scripts(), current)

	if cmd == "exec":
		return _filter_prefix(_find_cfg_files(), current)

	# If nothing specific matches and token looks like a node path, suggest scene nodes.
	if current.begins_with("/") or current.find("/") != -1:
		return _filter_prefix(_collect_scene_node_paths(), current)

	return []

func discover_commands() -> void:
	var root = get_tree().current_scene
	if not root:
		return
	_discover_in_node(root)

func _discover_in_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for method_info in node.get_method_list():
		var method_name = String(method_info.name)
		if method_name.begins_with("console_cmd_"):
			var cmd = method_name.replace("console_cmd_", "")
			if not _commands.has(cmd):
				register_command(cmd, node, method_name, "Auto-discovered command", "%s ..." % cmd)
	for child in node.get_children():
		_discover_in_node(child)

func _execute_line(line: String, alias_depth: int) -> void:
	if alias_depth > MAX_ALIAS_DEPTH:
		add_log("ERR", "Alias recursion limit reached.")
		return

	if line.find("|") != -1:
		var pipe_result = _execute_pipeline(line)
		var pipe_ok = bool(pipe_result.get("ok", false))
		var pipe_msg = str(pipe_result.get("message", "ok"))
		if not pipe_ok:
			add_log("ERR", pipe_msg)
		emit_signal("command_executed", line, pipe_ok, pipe_msg)
		return

	var tokens = _tokenize(line)
	if tokens.empty():
		return

	var cmd = String(tokens[0]).to_lower()
	var argv = tokens.slice(1, tokens.size())

	if _aliases.has(cmd):
		var expanded = String(_aliases[cmd])
		if argv.size() > 0:
			expanded += " " + _join_tokens(argv)
		_execute_line(expanded, alias_depth + 1)
		return

	if read_only and cmd in ["set", "exec", "bind", "alias", "run", "cp", "rm", "mv"]:
		add_log("WARN", "Console is in read-only mode.")
		emit_signal("command_executed", line, false, "read-only")
		return

	# Cvar shorthand: gravity 20
	if _cvars.has(cmd) and argv.size() > 0:
		if set_cvar(cmd, argv[0]):
			add_log("CORE", "%s = %s" % [cmd, str(get_cvar(cmd))])
			emit_signal("command_executed", line, true, "ok")
		return
	elif _cvars.has(cmd) and argv.empty():
		add_log("CORE", "%s = %s" % [cmd, str(get_cvar(cmd))])
		emit_signal("command_executed", line, true, "ok")
		return

	if not _commands.has(cmd):
		add_log("ERR", "Unknown command: %s" % cmd)
		emit_signal("core_command_requested", line)
		emit_signal("command_executed", line, false, "unknown")
		return

	var meta = _commands[cmd]
	if int(meta.flags) & FLAG_CHEAT and not allow_cheats:
		add_log("WARN", "Command '%s' is cheat-locked." % cmd)
		emit_signal("command_executed", line, false, "cheat-locked")
		return

	var ok = true
	var msg = "ok"
	if not is_instance_valid(meta.target) or not meta.target.has_method(meta.method):
		ok = false
		msg = "invalid target"
		add_log("ERR", "Command target missing: %s" % cmd)
	else:
		var result = meta.target.call(meta.method, argv, line)
		if result is Dictionary:
			ok = result.get("ok", true)
			msg = str(result.get("message", "ok"))
	if not ok:
		add_log("ERR", msg)
	emit_signal("command_executed", line, ok, msg)

func _register_builtin_commands() -> void:
	register_command("help", self, "_cmd_help", "Muestra ayuda.", "help [comando]")
	register_command("clear", self, "_cmd_clear", "Limpia salida.", "clear")
	register_command("history", self, "_cmd_history", "Muestra historial.", "history")
	register_command("echo", self, "_cmd_echo", "Imprime texto.", "echo <mensaje>")
	register_command("pwd", self, "_cmd_pwd", "Muestra directorio actual VFS.", "pwd")
	register_command("ls", self, "_cmd_ls", "Lista entradas VFS.", "ls [ruta|glob]")
	register_command("cd", self, "_cmd_cd", "Cambia directorio VFS.", "cd [ruta]")
	register_command("cat", self, "_cmd_cat", "Muestra script o propiedades de nodo.", "cat <ruta>")
	register_command("cp", self, "_cmd_cp", "Clona un nodo.", "cp <origen> [destino]")
	register_command("rm", self, "_cmd_rm", "Elimina un nodo.", "rm <ruta>")
	register_command("mv", self, "_cmd_mv", "Reasigna nodo a nuevo padre.", "mv <origen> <nuevo_padre>")
	register_command("cvars", self, "_cmd_cvars", "Lista cvars.", "cvars")
	register_command("set", self, "_cmd_set", "Asigna cvar.", "set <cvar> <valor>")
	register_command("get", self, "_cmd_get", "Lee cvar.", "get <cvar>")
	register_command("exec", self, "_cmd_exec", "Ejecuta .cfg.", "exec <script.cfg>")
	register_command("bind", self, "_cmd_bind", "Asocia tecla/comando.", "bind <tecla> <comando>")
	register_command("alias", self, "_cmd_alias", "Crea alias.", "alias <nombre> <comando>")
	register_command("filter", self, "_cmd_filter", "Filtra por canal.", "filter <AI|SYS|CORE|WARN|ERR|off>")
	register_command("run", self, "_cmd_run", "Ejecuta script OYS.", "run <archivo.oys>")

func _register_builtin_cvars() -> void:
	register_cvar("allow_cheats", TYPE_BOOL, false, "Habilita comandos cheat.", null, null, FLAG_ARCHIVE, self, "_on_allow_cheats_changed")
	register_cvar("console_read_only", TYPE_BOOL, false, "Modo solo lectura.", null, null, FLAG_ARCHIVE, self, "_on_read_only_changed")
	register_cvar("sv_gravity", TYPE_REAL, -14.0, "Gravedad del salto.", -50.0, -1.0, FLAG_ARCHIVE, self, "_on_sv_gravity_changed")

func _on_allow_cheats_changed(value) -> void:
	allow_cheats = bool(value)

func _on_read_only_changed(value) -> void:
	read_only = bool(value)

func _on_sv_gravity_changed(value) -> void:
	var player = _find_player_controller()
	if player and player.has_node("Logic/Jump"):
		var jump = player.get_node("Logic/Jump")
		if jump:
			jump.gravity = float(value)
			add_log("CORE", "Applied sv_gravity to player jump: %s" % str(value))

func _cmd_help(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		var keys = _commands.keys()
		keys.sort()
		add_log("SYS", "Commands: %s" % ", ".join(keys))
		return {"ok": true}
	var cmd = String(argv[0]).to_lower()
	if _commands.has(cmd):
		var meta = _commands[cmd]
		add_log("SYS", "%s - %s" % [cmd, meta.description])
		if meta.usage != "":
			add_log("SYS", "Usage: %s" % meta.usage)
		return {"ok": true}
	add_log("WARN", "No help for command: %s" % cmd)
	return {"ok": false, "message": "No help available"}

func _cmd_clear(_argv: Array, _raw: String) -> Dictionary:
	clear_logs()
	return {"ok": true}

func _cmd_history(_argv: Array, _raw: String) -> Dictionary:
	var start = max(0, _history.size() - MAX_HISTORY)
	for i in range(start, _history.size()):
		add_log("SYS", "%d: %s" % [i + 1, _history[i]])
	return {"ok": true}

func _cmd_pwd(_argv: Array, _raw: String) -> Dictionary:
	add_log("SYS", _vfs_cwd)
	return {"ok": true}

func _cmd_ls(argv: Array, _raw: String) -> Dictionary:
	var query = "." if argv.empty() else String(argv[0])
	var result = _vfs_ls(query)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", ERR_IO))}
	for line in result.get("lines", []):
		add_log("SYS", line)
	return {"ok": true}

func _cmd_cd(argv: Array, _raw: String) -> Dictionary:
	var target = "/root" if argv.empty() else String(argv[0])
	var resolved = _vfs_resolve(target)
	if not _vfs_is_dir(resolved):
		return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, target]}
	_vfs_cwd = resolved
	add_log("SYS", "cwd: %s" % _vfs_cwd)
	return {"ok": true}

func _cmd_cat(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		return {"ok": false, "message": "Usage: cat <ruta>"}
	var result = _vfs_cat(String(argv[0]))
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", ERR_IO))}
	for line in result.get("lines", []):
		add_log("SYS", line)
	return {"ok": true}

func _cmd_cp(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		return {"ok": false, "message": "Usage: cp <origen> [destino]"}
	var src = _vfs_resolve(String(argv[0]))
	var src_node = _vfs_node_from_root(src)
	if src_node == null:
		return {"ok": false, "message": "%s: source" % ERR_NOT_FOUND}
	if src == "/root":
		return {"ok": false, "message": "%s: cannot clone root" % ERR_PERMISSION}

	var parent_node = src_node.get_parent()
	var name_hint = src_node.name
	if argv.size() > 1:
		var dst = _vfs_resolve(String(argv[1]))
		var dst_node = _vfs_node_from_root(dst)
		if dst_node != null:
			parent_node = dst_node
		else:
			var split = _vfs_split_parent_child(dst)
			parent_node = _vfs_node_from_root(split.parent)
			if parent_node == null:
				return {"ok": false, "message": "%s: destination" % ERR_NOT_FOUND}
			if split.child != "":
				name_hint = split.child
	if parent_node == null:
		return {"ok": false, "message": "%s: parent missing" % ERR_NOT_FOUND}

	var clone = src_node.duplicate()
	clone.name = _vfs_unique_child_name(parent_node, name_hint)
	parent_node.add_child(clone)
	add_log("CORE", "Cloned %s -> %s/%s" % [src, _vfs_path_from_node(parent_node), clone.name])
	return {"ok": true}

func _cmd_rm(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		return {"ok": false, "message": "Usage: rm <ruta>"}
	var path = _vfs_resolve(String(argv[0]))
	if path == "/root":
		return {"ok": false, "message": "%s: root is protected" % ERR_PERMISSION}
	var node = _vfs_node_from_root(path)
	if node == null:
		return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}
	if _vfs_is_protected_node(node):
		return {"ok": false, "message": "%s: protected node" % ERR_PERMISSION}
	node.queue_free()
	add_log("CORE", "Removed %s" % path)
	return {"ok": true}

func _cmd_mv(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 2:
		return {"ok": false, "message": "Usage: mv <origen> <nuevo_padre>"}
	var src = _vfs_resolve(String(argv[0]))
	var dst_parent = _vfs_resolve(String(argv[1]))
	var src_node = _vfs_node_from_root(src)
	var parent_node = _vfs_node_from_root(dst_parent)
	if src_node == null or parent_node == null:
		return {"ok": false, "message": "%s: source or destination" % ERR_NOT_FOUND}
	if src == "/root" or _vfs_is_protected_node(src_node):
		return {"ok": false, "message": "%s: protected node" % ERR_PERMISSION}
	if src_node == parent_node:
		return {"ok": false, "message": "mv: source equals destination"}
	if src_node.get_parent() != null:
		src_node.get_parent().remove_child(src_node)
	parent_node.add_child(src_node)
	add_log("CORE", "Moved %s -> %s" % [src, _vfs_path_from_node(parent_node)])
	return {"ok": true}

func _cmd_echo(argv: Array, _raw: String) -> Dictionary:
	var redirect_idx = _raw.find(">")
	if redirect_idx != -1:
		var left = _raw.substr(0, redirect_idx).strip_edges()
		var right = _raw.substr(redirect_idx + 1, _raw.length()).strip_edges()
		if right == "":
			return {"ok": false, "message": "echo redirect requires target path"}
		var value = ""
		if left.length() >= 4:
			value = left.substr(4, left.length()).strip_edges()
		if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
			value = value.substr(1, value.length() - 2)
		var set_result = _vfs_set_property(right, value)
		return {"ok": bool(set_result.get("ok", false)), "message": str(set_result.get("message", ERR_IO))}
	if argv.empty():
		return {"ok": false, "message": "echo requires a message"}
	add_log("SYS", _join_tokens(argv))
	return {"ok": true}

func _cmd_cvars(_argv: Array, _raw: String) -> Dictionary:
	var keys = _cvars.keys()
	keys.sort()
	for key in keys:
		var info = _cvars[key]
		add_log("CORE", "%s = %s" % [key, str(info.value)])
	return {"ok": true}

func _cmd_set(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 2:
		return {"ok": false, "message": "Usage: set <cvar> <value>"}
	var ok = set_cvar(String(argv[0]), argv[1])
	if ok:
		add_log("CORE", "%s = %s" % [argv[0], str(get_cvar(argv[0]))])
	return {"ok": ok, "message": "set failed" if not ok else "ok"}

func _cmd_get(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 1:
		return {"ok": false, "message": "Usage: get <cvar>"}
	var key = String(argv[0]).to_lower()
	if not _cvars.has(key):
		return {"ok": false, "message": "Unknown cvar"}
	add_log("CORE", "%s = %s" % [key, str(get_cvar(key))])
	return {"ok": true}

func _cmd_exec(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 1:
		return {"ok": false, "message": "Usage: exec <script.cfg>"}
	var path = String(argv[0])
	if not path.ends_with(".cfg"):
		path += ".cfg"
	var file = File.new()
	if not file.file_exists(path):
		if file.file_exists("res://" + path):
			path = "res://" + path
		elif file.file_exists("user://" + path):
			path = "user://" + path
		else:
			return {"ok": false, "message": "cfg not found: %s" % path}
	if file.open(path, File.READ) != OK:
		return {"ok": false, "message": "Cannot open cfg"}
	var lines = []
	while not file.eof_reached():
		var ln = file.get_line().strip_edges()
		if ln != "" and not ln.begins_with("#"):
			lines.append(ln)
	file.close()
	for cmd in lines:
		_queue.append(cmd)
	add_log("CORE", "Queued %d commands from %s" % [lines.size(), path])
	return {"ok": true}

func _cmd_bind(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 2:
		return {"ok": false, "message": "Usage: bind <key> <command>"}
	var key_name = String(argv[0]).to_upper()
	var command = _join_tokens(argv.slice(1, argv.size()))
	_binds[key_name] = command
	_save_cfg()
	add_log("SYS", "Bound %s -> %s" % [key_name, command])
	return {"ok": true}

func _cmd_alias(argv: Array, _raw: String) -> Dictionary:
	if argv.size() < 2:
		return {"ok": false, "message": "Usage: alias <name> <command>"}
	var name = String(argv[0]).to_lower()
	var command = _join_tokens(argv.slice(1, argv.size()))
	_aliases[name] = command
	_save_cfg()
	add_log("SYS", "Alias %s -> %s" % [name, command])
	return {"ok": true}

func _cmd_filter(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		if _filter_tag == "":
			add_log("SYS", "Filter disabled")
		else:
			add_log("SYS", "Current filter: %s" % _filter_tag)
		return {"ok": true}
	var requested = String(argv[0]).to_upper()
	if requested == "OFF":
		_filter_tag = ""
		add_log("SYS", "Filter disabled")
		return {"ok": true}
	if not CHANNEL_COLORS.has(requested):
		return {"ok": false, "message": "Unknown filter tag"}
	_filter_tag = requested
	add_log("SYS", "Filter set to %s" % _filter_tag)
	return {"ok": true}

func _cmd_run(argv: Array, _raw: String) -> Dictionary:
	if argv.empty():
		return {"ok": false, "message": "Usage: run <archivo.oys>"}
	var requested = String(argv[0])
	var path = _resolve_oys_path(requested)
	if path == "":
		return {"ok": false, "message": "OYS script not found: %s" % requested}

	var file = File.new()
	if file.open(path, File.READ) != OK:
		return {"ok": false, "message": "Cannot open OYS script: %s" % path}
	var content = file.get_as_text()
	file.close()

	var interpreter_script = load("res://core_v2/systems/OYS_Interpreter.gd")
	if interpreter_script == null:
		return {"ok": false, "message": "OYS_Interpreter not available"}
	var host = get_tree().current_scene if get_tree().current_scene else get_tree().root
	var interpreter = interpreter_script.new(host)
	interpreter.parse(content)
	_active_interpreters.append(interpreter)
	var run_state = interpreter.run()
	if run_state is GDScriptFunctionState:
		run_state.connect("completed", self, "_on_oys_run_completed", [path, interpreter], CONNECT_ONESHOT)
	else:
		_on_oys_run_completed(null, path, interpreter)

	emit_signal("run_oys_requested", path)
	add_log("CORE", "Running OYS script: %s" % path)
	return {"ok": true}

func _push_history(line: String) -> void:
	if line == "":
		return
	_history.append(line)
	while _history.size() > MAX_HISTORY:
		_history.pop_front()

func _sanitize_input(line: String) -> String:
	var clean = line.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	return clean.strip_edges()

func _tokenize(line: String) -> Array:
	var tokens := []
	var current := ""
	var in_quotes := false
	for i in range(line.length()):
		var ch = line[i]
		if ch == '"':
			in_quotes = not in_quotes
			continue
		if ch == ' ' and not in_quotes:
			if current != "":
				tokens.append(current)
				current = ""
		else:
			current += ch
	if current != "":
		tokens.append(current)
	return tokens

func _join_tokens(tokens: Array) -> String:
	var out := ""
	for i in range(tokens.size()):
		if i > 0:
			out += " "
		out += str(tokens[i])
	return out

func _convert_to_type(value, var_type: int):
	match var_type:
		TYPE_INT:
			return int(value)
		TYPE_REAL:
			return float(value)
		TYPE_BOOL:
			var text = str(value).to_lower()
			return text in ["1", "true", "yes", "on"]
		TYPE_STRING:
			return str(value)
		_:
			return value

func _apply_cvar_callback(name: String, info: Dictionary) -> void:
	if info.callback_target and info.callback_method != "" and is_instance_valid(info.callback_target):
		if info.callback_target.has_method(info.callback_method):
			info.callback_target.call(info.callback_method, info.value)

func _save_cfg() -> void:
	var file = File.new()
	if file.open(_cfg_path, File.WRITE) != OK:
		return
	for key in _cvars.keys():
		var info = _cvars[key]
		if int(info.flags) & FLAG_ARCHIVE:
			file.store_line("set %s %s" % [key, str(info.value)])
	for name in _aliases.keys():
		file.store_line("alias %s %s" % [name, _aliases[name]])
	for key_name in _binds.keys():
		file.store_line("bind %s %s" % [key_name, _binds[key_name]])
	file.close()

func _load_cfg() -> void:
	var file = File.new()
	if not file.file_exists(_cfg_path):
		return
	if file.open(_cfg_path, File.READ) != OK:
		return
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		_execute_line(line, 0)
	file.close()

func _find_player_controller() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _suggest_cvar_values(cvar_name: String, prefix: String) -> Array:
	var info = _cvars.get(cvar_name, null)
	if info == null:
		return []
	if info.type == TYPE_BOOL:
		return _filter_prefix(["true", "false", "1", "0"], prefix.to_lower())
	if info.type == TYPE_INT or info.type == TYPE_REAL:
		var suggestions := [str(info.value)]
		if info.min != null:
			suggestions.append(str(info.min))
		if info.max != null:
			suggestions.append(str(info.max))
		return _filter_prefix(_sorted_unique(suggestions), prefix)
	return []

func _filter_prefix(values: Array, prefix: String) -> Array:
	var out := []
	for value in values:
		var s = str(value)
		if prefix == "" or s.to_lower().begins_with(prefix.to_lower()):
			out.append(s)
	out.sort()
	return out

func _sorted_unique(values: Array) -> Array:
	var seen := {}
	var out := []
	for value in values:
		var s = str(value)
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	out.sort()
	return out

func _collect_scene_node_paths() -> Array:
	var scene = get_tree().current_scene
	if not scene:
		return []
	var paths := []
	_collect_paths_rec(scene, paths)
	return paths

func _collect_paths_rec(node: Node, paths: Array) -> void:
	paths.append(str(node.get_path()))
	for child in node.get_children():
		_collect_paths_rec(child, paths)

func _find_oys_scripts() -> Array:
	var dirs = ["res://core_v2/tests", "res://core_v2/scripts"]
	var files := []
	for base in dirs:
		var d = Directory.new()
		if d.open(base) != OK:
			continue
		d.list_dir_begin(true, true)
		while true:
			var name = d.get_next()
			if name == "":
				break
			if name.ends_with(".oys"):
				files.append(base + "/" + name)
		d.list_dir_end()
	return _sorted_unique(files)

func _find_cfg_files() -> Array:
	var dirs = ["res://", "res://core_v2", "user://"]
	var files := []
	for base in dirs:
		var d = Directory.new()
		if d.open(base) != OK:
			continue
		d.list_dir_begin(true, true)
		while true:
			var name = d.get_next()
			if name == "":
				break
			if name.ends_with(".cfg"):
				files.append(base + "/" + name)
		d.list_dir_end()
	return _sorted_unique(files)

func _resolve_oys_path(raw_path: String) -> String:
	var path = raw_path
	if not path.ends_with(".oys"):
		path += ".oys"
	var candidates = [
		path,
		"res://" + path,
		"res://core_v2/tests/" + path,
		"res://core_v2/scripts/" + path,
		"user://" + path
	]
	var file = File.new()
	for candidate in candidates:
		if file.file_exists(candidate):
			return candidate
	return ""

func _execute_pipeline(raw_line: String) -> Dictionary:
	var parts = raw_line.split("|")
	if parts.size() < 2:
		return {"ok": false, "message": "invalid pipeline"}
	if parts.size() > MAX_PIPE_STAGES:
		return {"ok": false, "message": "pipeline too deep"}

	var lines: Array = []
	for i in range(parts.size()):
		var stage = String(parts[i]).strip_edges()
		if stage == "":
			return {"ok": false, "message": "empty pipeline stage"}
		if i == 0:
			var first = _pipeline_stage_to_lines(stage)
			if not bool(first.get("ok", false)):
				return first
			lines = first.get("lines", [])
		else:
			var filtered = _pipeline_apply_filter(stage, lines)
			if not bool(filtered.get("ok", false)):
				return filtered
			lines = filtered.get("lines", [])

	for ln in lines:
		add_log("SYS", str(ln))
	return {"ok": true, "message": "ok"}

func _pipeline_stage_to_lines(stage: String) -> Dictionary:
	var tokens = _tokenize(stage)
	if tokens.empty():
		return {"ok": false, "message": "empty command"}
	var cmd = String(tokens[0]).to_lower()
	var argv = tokens.slice(1, tokens.size())
	if cmd == "ls":
		return _vfs_ls("." if argv.empty() else String(argv[0]))
	if cmd == "cat":
		if argv.empty():
			return {"ok": false, "message": "cat requires target"}
		return _vfs_cat(String(argv[0]))
	if cmd == "history":
		var start = max(0, _history.size() - MAX_HISTORY)
		var lines := []
		for i in range(start, _history.size()):
			lines.append("%d: %s" % [i + 1, _history[i]])
		return {"ok": true, "lines": lines}
	return {"ok": false, "message": "unsupported pipeline source: %s" % cmd}

func _pipeline_apply_filter(stage: String, input_lines: Array) -> Dictionary:
	var tokens = _tokenize(stage)
	if tokens.empty():
		return {"ok": false, "message": "empty filter stage"}
	if String(tokens[0]).to_lower() != "grep":
		return {"ok": false, "message": "only grep allowed in pipe filters"}
	var invert := false
	var pattern := ""
	if tokens.size() >= 3 and String(tokens[1]) == "-v":
		invert = true
		pattern = String(tokens[2])
	elif tokens.size() >= 2:
		pattern = String(tokens[1])
	else:
		return {"ok": false, "message": "grep requires pattern"}

	var out := []
	for ln in input_lines:
		var s = str(ln)
		var hit = s.findn(pattern) != -1
		if (hit and not invert) or (invert and not hit):
			out.append(s)
	return {"ok": true, "lines": out}

func _vfs_resolve(raw_path: String) -> String:
	var p = raw_path.strip_edges()
	if p == "" or p == ".":
		return _vfs_cwd
	if p.begins_with("/"):
		return _vfs_normalize_abs(p)
	return _vfs_normalize_abs(_vfs_cwd + "/" + p)

func _vfs_normalize_abs(path: String) -> String:
	var parts = path.split("/", false)
	var stack := []
	for part in parts:
		var seg = String(part).strip_edges()
		if seg == "" or seg == ".":
			continue
		if seg == "..":
			if not stack.empty():
				stack.pop_back()
		else:
			stack.append(seg)
	return "/" + "/".join(stack)

func _vfs_split_parent_child(path: String) -> Dictionary:
	var p = _vfs_normalize_abs(path)
	if p == "/":
		return {"parent": "/", "child": ""}
	var idx = p.rfind("/")
	if idx <= 0:
		return {"parent": "/", "child": p.replace("/", "")}
	return {"parent": p.substr(0, idx), "child": p.substr(idx + 1, p.length())}

func _vfs_is_dir(path: String) -> bool:
	if path == "/" or path in VFS_MOUNTS:
		return true
	if path.begins_with("/root"):
		return _vfs_node_from_root(path) != null
	if path.begins_with("/scripts"):
		var r = _vfs_script_resolve(path)
		return bool(r.get("ok", false) and r.get("is_dir", false))
	if path == "/bin" or path.begins_with("/bin/"):
		return true
	if path == "/proc" or path.begins_with("/proc/"):
		return true
	return false

func _vfs_ls(query_path: String) -> Dictionary:
	var resolved = _vfs_resolve(query_path)
	var glob = ""
	var path = resolved
	if resolved.find("*") != -1:
		var split = _vfs_split_parent_child(resolved)
		path = split.parent
		glob = split.child

	var lines := []
	if path == "/":
		lines = ["/root/", "/bin/", "/scripts/", "/proc/"]
	elif path == "/bin":
		var keys = _commands.keys()
		keys.sort()
		for k in keys:
			lines.append(str(k))
	elif path == "/proc":
		lines = ["fps", "memory_static", "object_count"]
	elif path.begins_with("/proc/"):
		return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}
	elif path.begins_with("/root"):
		var node = _vfs_node_from_root(path)
		if node == null:
			return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}
		for child in node.get_children():
			lines.append("%s/" % child.name)
	elif path.begins_with("/scripts"):
		var scripts = _find_oys_scripts()
		for s in scripts:
			var rel = s.replace("res://", "")
			lines.append(rel.get_file())
	else:
		return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}

	if glob != "":
		lines = _vfs_glob_filter(lines, glob)
	lines.sort()
	return {"ok": true, "lines": lines}

func _vfs_glob_filter(lines: Array, pattern: String) -> Array:
	var out := []
	var p = pattern.replace("/", "")
	var starts = p.replace("*", "")
	for line in lines:
		var name = str(line).replace("/", "")
		if p == "*" or p == "":
			out.append(line)
		elif p.begins_with("*") and name.ends_with(starts):
			out.append(line)
		elif p.ends_with("*") and name.begins_with(starts):
			out.append(line)
		elif name.findn(starts) != -1:
			out.append(line)
	return out

func _vfs_cat(path_raw: String) -> Dictionary:
	var path = _vfs_resolve(path_raw)
	if path.begins_with("/proc"):
		return _vfs_cat_proc(path)
	if path.begins_with("/bin"):
		return _vfs_cat_bin(path)
	if path.begins_with("/scripts"):
		return _vfs_cat_script(path)
	if path.begins_with("/root"):
		return _vfs_cat_node(path)
	return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}

func _vfs_cat_proc(path: String) -> Dictionary:
	var lines := []
	if path == "/proc" or path == "/proc/":
		lines = ["fps=%s" % str(Engine.get_frames_per_second()), "memory_static=%s" % str(OS.get_static_memory_usage()), "object_count=%s" % str(Performance.get_monitor(Performance.OBJECT_COUNT))]
		return {"ok": true, "lines": lines}
	if path == "/proc/fps":
		return {"ok": true, "lines": [str(Engine.get_frames_per_second())]}
	if path == "/proc/memory_static":
		return {"ok": true, "lines": [str(OS.get_static_memory_usage())]}
	if path == "/proc/object_count":
		return {"ok": true, "lines": [str(Performance.get_monitor(Performance.OBJECT_COUNT))]}
	return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}

func _vfs_cat_bin(path: String) -> Dictionary:
	if path == "/bin":
		var keys = _commands.keys()
		keys.sort()
		return {"ok": true, "lines": keys}
	var cmd = path.replace("/bin/", "")
	if _commands.has(cmd):
		var meta = _commands[cmd]
		return {"ok": true, "lines": ["%s - %s" % [cmd, str(meta.description)], "usage: %s" % str(meta.usage)]}
	return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}

func _vfs_cat_script(path: String) -> Dictionary:
	var resolved = _vfs_script_resolve(path)
	if not bool(resolved.get("ok", false)):
		return {"ok": false, "message": str(resolved.get("message", ERR_IO))}
	if bool(resolved.get("is_dir", false)):
		var scripts = _find_oys_scripts()
		var lines := []
		for s in scripts:
			lines.append(s.replace("res://", ""))
		lines.sort()
		return {"ok": true, "lines": lines}
	var file = File.new()
	if file.open(str(resolved.get("path", "")), File.READ) != OK:
		return {"ok": false, "message": "%s: cannot read script" % ERR_IO}
	var lines := []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	return {"ok": true, "lines": lines}

func _vfs_cat_node(path: String) -> Dictionary:
	var node = _vfs_node_from_root(path)
	if node == null:
		return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, path]}
	var lines := []
	var plist = node.get_property_list()
	for p in plist:
		var usage = int(p.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var name = str(p.get("name", ""))
		var value = node.get(name)
		lines.append("%s=%s" % [name, str(value)])
	if node is Spatial:
		lines.append("global_position=%s" % str((node as Spatial).global_transform.origin))
	if "velocity" in node:
		lines.append("velocity=%s" % str(node.get("velocity")))
	if "current_state" in node:
		lines.append("current_state=%s" % str(node.get("current_state")))
	lines.sort()
	return {"ok": true, "lines": lines}

func _vfs_script_resolve(path: String) -> Dictionary:
	var clean = _vfs_normalize_abs(path)
	var rel = clean.replace("/scripts", "").strip_edges()
	if rel.begins_with("/"):
		rel = rel.substr(1, rel.length())
	if rel == "":
		return {"ok": true, "path": "res://core_v2/scripts", "is_dir": true}
	if rel.find("..") != -1:
		return {"ok": false, "message": "%s: namespace escape blocked" % ERR_PERMISSION}
	var file = File.new()
	var candidates = [
		"res://core_v2/scripts/" + rel,
		"res://core_v2/tests/" + rel,
		"res://" + rel
	]
	for c in candidates:
		if file.file_exists(c):
			return {"ok": true, "path": c, "is_dir": false}
	var d = Directory.new()
	for c in candidates:
		if d.open(c) == OK:
			return {"ok": true, "path": c, "is_dir": true}
	return {"ok": false, "message": "%s: %s" % [ERR_NOT_FOUND, clean]}

func _vfs_node_from_root(path: String) -> Node:
	var p = _vfs_normalize_abs(path)
	if p == "/root":
		return get_tree().current_scene
	if not p.begins_with("/root/"):
		return null
	var scene = get_tree().current_scene
	if scene == null:
		return null
	var rel = p.substr("/root/".length(), p.length())
	return scene.get_node_or_null(NodePath(rel))

func _vfs_path_from_node(node: Node) -> String:
	if node == null:
		return ""
	var scene = get_tree().current_scene
	if scene == null:
		return "/root"
	if node == scene:
		return "/root"
	var rel = str(scene.get_path_to(node))
	return "/root/" + rel

func _vfs_unique_child_name(parent: Node, base_name: String) -> String:
	var clean = base_name if base_name != "" else "copy"
	var candidate = clean
	var idx = 1
	while parent.has_node(candidate):
		candidate = "%s_%d" % [clean, idx]
		idx += 1
	return candidate

func _vfs_is_protected_node(node: Node) -> bool:
	if node == null:
		return true
	if node.get_parent() == null:
		return true
	if "protected" in node and bool(node.get("protected")):
		return true
	return false

func _vfs_set_property(path_raw: String, raw_value: String) -> Dictionary:
	var path = _vfs_resolve(path_raw)
	if not path.begins_with("/root/"):
		return {"ok": false, "message": "%s: write target must be under /root" % ERR_PERMISSION}
	var split = _vfs_split_parent_child(path)
	var node = _vfs_node_from_root(split.parent)
	if node == null:
		return {"ok": false, "message": "%s: node missing" % ERR_NOT_FOUND}
	var prop = split.child
	if prop == "":
		return {"ok": false, "message": "%s: property missing" % ERR_NOT_FOUND}
	var plist = node.get_property_list()
	var expected_type = -1
	for p in plist:
		if str(p.get("name", "")) == prop:
			expected_type = int(p.get("type", -1))
			break
	if expected_type == -1:
		return {"ok": false, "message": "%s: property not found" % ERR_NOT_FOUND}
	var converted = _vfs_convert_to_expected(raw_value, expected_type)
	if converted == null and expected_type != TYPE_NIL:
		return {"ok": false, "message": "%s: type mismatch for %s" % [ERR_IO, prop]}
	node.set(prop, converted)
	add_log("CORE", "set %s/%s=%s" % [split.parent, prop, str(converted)])
	return {"ok": true, "message": "ok"}

func _vfs_convert_to_expected(raw_value: String, expected_type: int):
	var text = raw_value.strip_edges()
	match expected_type:
		TYPE_BOOL:
			var low = text.to_lower()
			if low in ["true", "1", "on", "yes"]:
				return true
			if low in ["false", "0", "off", "no"]:
				return false
			return null
		TYPE_INT:
			if text.is_valid_integer():
				return int(text)
			return null
		TYPE_REAL:
			if text.is_valid_float():
				return float(text)
			return null
		TYPE_STRING:
			return text
		_:
			return text

func _on_oys_run_completed(_result = null, path: String = "", interpreter = null) -> void:
	add_log("CORE", "Finished OYS script: %s" % path)
	if interpreter != null:
		_active_interpreters.erase(interpreter)
