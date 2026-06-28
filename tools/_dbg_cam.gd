extends Reference
class_name _DbgCam

# Spawn (or move) a debug camera in the LIVE tree and make it current, so the peer's
# `screenshot` command captures from this vantage instead of the player's spring-arm cam.
# Single-call entry point because /eval only runs one expression. load() re-reads this file
# from disk each call, so editing the framing and re-invoking picks up changes.
static func frame(tree: SceneTree, from: Vector3, to: Vector3, up := Vector3.UP) -> String:
	var root = tree.get_root()
	var cam = root.get_node_or_null("DBGCAM")
	if cam == null:
		cam = Camera.new()
		cam.name = "DBGCAM"
		cam.far = 600.0
		root.add_child(cam)
	cam.translation = from
	cam.look_at(to, up)
	cam.make_current()
	return "framed %s -> %s" % [str(from), str(to)]

static func clear(tree: SceneTree) -> String:
	var cam = tree.get_root().get_node_or_null("DBGCAM")
	if cam:
		cam.queue_free()
		return "cleared"
	return "none"
