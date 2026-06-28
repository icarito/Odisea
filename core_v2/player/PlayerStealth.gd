extends Node

# PlayerStealth.gd
# Manages player stealth state and visibility parameters.

enum State {
	VISIBLE,
	HIDDEN,
	DETECTED
}

signal stealth_state_changed(is_visible)

var current_state = State.VISIBLE setget set_state
var is_crouching := false
var in_cover := false setget set_in_cover

var _cover_area: Area = null

func _ready() -> void:
	add_to_group("player_stealth")
	_setup_cover_detection()

func _setup_cover_detection() -> void:
	_cover_area = Area.new()
	_cover_area.name = "CoverArea"
	_cover_area.collision_mask = 1 << 6 # Layer 7: Prop (where cover usually lives)
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	_cover_area.add_child(shape)
	add_child(_cover_area)
	
	_cover_area.connect("body_entered", self, "_on_cover_body_entered")
	_cover_area.connect("body_exited", self, "_on_cover_body_exited")

func _on_cover_body_entered(body: Node) -> void:
	if body.is_in_group("cover"):
		self.in_cover = true

func _on_cover_body_exited(body: Node) -> void:
	if body.is_in_group("cover"):
		# Check if still in other cover
		var bodies = _cover_area.get_overlapping_bodies()
		var still_in_cover = false
		for b in bodies:
			if b.is_in_group("cover"):
				still_in_cover = true
				break
		self.in_cover = still_in_cover

func set_state(new_state: int) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	emit_signal("stealth_state_changed", current_state != State.HIDDEN)

func set_in_cover(value: bool) -> void:
	in_cover = value
	_update_stealth_state()

func _update_stealth_state() -> void:
	if in_cover:
		self.current_state = State.HIDDEN
	elif current_state == State.HIDDEN:
		self.current_state = State.VISIBLE

func get_visibility_score() -> float:
	# Returns a value between 0.0 (invisible) and 1.0 (fully visible)
	if current_state == State.HIDDEN:
		return 0.1
	
	var score = 1.0
	if is_crouching:
		score *= 0.5
		
	return score

func get_snapshot() -> Dictionary:
	return {
		"state": current_state,
		"is_crouching": is_crouching,
		"in_cover": in_cover
	}

func restore_snapshot(data: Dictionary) -> void:
	is_crouching = data.get("is_crouching", false)
	in_cover = data.get("in_cover", false)
	self.current_state = data.get("state", State.VISIBLE)
