extends Node

# SceneManager (autoload: "SceneManager")
# Responsibility: Management of scene transitions, asynchronous loading logic,
# and viewport configuration for split-screen.

# --- Properties ---
var active_players: Array = []       # List of peer_ids or local player indices
var viewport_configs: Array = []   # Dynamic viewport configuration (half, quarters, etc.)
var _current_scene: Node = null

# --- Signals ---
signal scene_loaded(scene_name)
signal layout_changed()

func _ready() -> void:
	_current_scene = get_tree().get_current_scene()
	if _current_scene:
		_current_scene.connect("ready", self, "_on_scene_ready", [_current_scene.filename])

func _on_scene_ready(scene_path: String) -> void:
	emit_signal("scene_loaded", scene_path)

# --- Public API ---

func load_scene_async(path: String) -> void:
	# Here you would typically show a loading screen UI
	# For now, we'll just defer the scene change
	call_deferred("_deferred_load_scene", path)

func _deferred_load_scene(path: String) -> void:
	if _current_scene:
		_current_scene.free()
	
	var next_scene_res = load(path)
	if next_scene_res:
		_current_scene = next_scene_res.instance()
		get_tree().get_root().add_child(_current_scene)
		get_tree().set_current_scene(_current_scene)
		_current_scene.connect("ready", self, "_on_scene_ready", [_current_scene.filename], CONNECT_ONESHOT)
	else:
		push_error("SceneManager: Failed to load scene at path: " + path)


func spawn_network_player(peer_id: int, spawn_point: Transform) -> void:
	# This will be implemented with the MultiplayerManager in the future.
	# For now, it can handle local players if needed.
	print("SceneManager: Spawning player for peer %d" % peer_id)
	# Example: PlayerManager.spawn(spawn_point)
	pass


func update_split_screen_layout() -> void:
	# This method will readjust viewports based on the number of active_players.
	# The logic from commit b7ed493e should be refactored here.
	# Placeholder implementation:
	
	var window_size = OS.get_window_size()
	var player_count = active_players.size()
	
	if player_count <= 1:
		# Single player, fullscreen
		get_tree().get_root().get_viewport().set_attach_to_screen_rect(Rect2(0, 0, window_size.x, window_size.y))
	elif player_count == 2:
		# Two players, horizontal split
		# This requires having separate viewports and cameras per player.
		# This is a simplified example. A real implementation would be more complex.
		# get_viewport_for_player(0).set_attach_to_screen_rect(Rect2(0, 0, window_size.x, window_size.y / 2))
		# get_viewport_for_player(1).set_attach_to_screen_rect(Rect2(0, window_size.y / 2, window_size.x, window_size.y / 2))
		push_warning("SceneManager: update_split_screen_layout() for 2 players not fully implemented.")
	else:
		# 3-4 players, quadrants
		push_warning("SceneManager: update_split_screen_layout() for 3-4 players not implemented.")

	emit_signal("layout_changed")

# --- Private Helper Functions ---
# (Add helper functions for viewport management etc. as needed)
# func get_viewport_for_player(player_index: int) -> Viewport:
#	  pass
