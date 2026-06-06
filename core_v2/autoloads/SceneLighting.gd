extends Node

# SceneLighting — autoload that owns scene-level lighting state.
#
# Other systems (e.g. AirlockTransitionFX) call set_brightness(t) to dim/restore
# all WorldEnvironments and scene lights without needing to search the tree themselves.
#
# Call chain:
#   SceneManager emits scene_ready → SceneLighting.refresh()
#   AirlockTransitionFX._apply_brightness() → SceneLighting.set_brightness(t)
#   AirlockTransitionFX._restore_lights()   → SceneLighting.restore_brightness()

var _entries: Array = []  # [{ node, type, base_value, ?environment }]
var _current_t: float = 1.0

func _ready() -> void:
	var sm := get_node_or_null("/root/SceneManager")
	if sm and sm.has_signal("scene_ready"):
		sm.connect("scene_ready", self, "_on_scene_ready")

func _on_scene_ready(_path, _scene_root, _params) -> void:
	refresh()

# Re-scan scene tree for managed lights. Call after a scene swap.
func refresh() -> void:
	_entries.clear()
	_current_t = 1.0
	_collect_from_root(get_tree().root)

# t in [0.0, 1.0] — multiplies all base_values
func set_brightness(t: float) -> void:
	_current_t = t
	_apply(t)

func restore_brightness() -> void:
	set_brightness(1.0)

func get_brightness() -> float:
	return _current_t

func _collect_from_root(root: Node) -> void:
	var stack: Array = [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		# Skip airlock chambers — AirlockTransitionFX manages their lights directly
		if node.is_in_group("airlock_chamber"):
			continue
		if node is WorldEnvironment:
			var env: Environment = node.get("environment")
			if env is Environment:
				_entries.append({
					"node": node,
					"type": "world_env",
					"base_value": float(env.ambient_light_energy),
					"environment": env
				})
		elif node is DirectionalLight or node is OmniLight or node is SpotLight:
			_entries.append({"node": node, "type": "light_energy", "base_value": float(node.light_energy)})
		for child in node.get_children():
			stack.push_back(child)
	# If no WorldEnvironment found in scene tree, fall back to default_env.tres
	var has_env := false
	for e in _entries:
		if e["type"] == "world_env":
			has_env = true
			break
	if not has_env:
		var default_env_path: String = ProjectSettings.get_setting("rendering/environment/default_environment")
		if default_env_path != "":
			var env_res = load(default_env_path)
			if env_res is Environment:
				_entries.append({
					"node": null,
					"type": "default_env_bg",
					"base_value": float(env_res.background_energy),
					"environment": env_res
				})

func _apply(t: float) -> void:
	for entry in _entries:
		match entry["type"]:
			"world_env":
				var env: Environment = entry["environment"]
				if env != null:
					env.ambient_light_energy = float(entry["base_value"]) * t
			"default_env_bg":
				var env: Environment = entry["environment"]
				if env != null:
					env.background_energy = float(entry["base_value"]) * t
			"light_energy":
				var node: Node = entry["node"]
				if is_instance_valid(node):
					node.set("light_energy", float(entry["base_value"]) * t)
