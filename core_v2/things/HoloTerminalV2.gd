extends InteractableBaseV2
class_name HoloTerminalV2

# HoloTerminalV2.gd - Interactive Holographic Screen
# Inherits InteractableBaseV2 for replay determinism.

export(float) var slide_speed := 2.0
export(float) var slide_height := 0.8

func _ready():
	interaction_text = "Access Terminal"

	# Configure base class speed
	if slide_speed > 0:
		anim_speed = slide_speed
		# Keep anim_duration consistent (though logic uses anim_speed)
		anim_duration = 1.0 / slide_speed
	else:
		anim_speed = 1.0

	# Initial state update
	_update_visuals()

func _update_visuals() -> void:
	# 2. Apply Movement (Visuals)
	if has_node("ScreenContainer"):
		# Interpolate the Y position of the ScreenContainer
		# using cubic ease out as per spec
		var y_pos = lerp(0.0, slide_height, _ease_out_cubic(anim_progress))
		$ScreenContainer.translation.y = y_pos

	# 3. Update UI State (Optimization)
	if has_node("Viewport"):
		# Only render the viewport if the screen is at least partially visible
		var mode = Viewport.UPDATE_WHEN_VISIBLE if anim_progress > 0 else Viewport.UPDATE_DISABLED
		$Viewport.render_target_update_mode = mode

func _ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

# Property aliases for spec compliance (read-only access to state)
func get_is_open() -> bool:
	return is_active

func get_slide_progress() -> float:
	return anim_progress
