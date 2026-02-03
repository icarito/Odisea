tool
extends InteractableBaseV2
class_name HoloTerminalV2

# HoloTerminalV2.gd - Interactive Holographic Screen
# Inherits InteractableBaseV2 for replay determinism.

export(float) var slide_speed := 2.0

export(float) var slide_height := 0.8
export(bool) var active setget set_active_debug


func _ready():
	interaction_text = "Toggle Terminal"


	# Configure base class speed
	if slide_speed > 0:
		anim_speed = slide_speed
		# Keep anim_duration consistent (though logic uses anim_speed)
		anim_duration = 1.0 / slide_speed
	else:
		anim_speed = 1.0

	# Initial state update
	_update_visuals()

	# Fix ViewportTexture path issue by explicit assignment
	var screen_mesh = $ScreenContainer/ScreenMesh
	var viewport = $Viewport
	if screen_mesh and viewport:
		var mat = screen_mesh.material
		if mat is ShaderMaterial:
			mat.set_shader_param("texture_albedo", viewport.get_texture())
	
	# Initial toggle logic (ensure correct state)
	if not is_active:
		$ProjectorMesh/HoloParticles.emitting = false
		if has_node("ScreenContainer"):
			$ScreenContainer.scale = Vector3.ZERO

func _on_interact(_actor: Node) -> void:
	# Toggle open/close (override base behavior if needed, or rely on base if it toggles)
	# InteractableBaseV2 usually just opens. We want toggle.
	if is_active:
		set_active(false)
	else:
		set_active(true)


func _update_visuals() -> void:
	# 2. Apply Movement (Visuals)
	if has_node("ScreenContainer"):
		# Interpolate the Y position of the ScreenContainer (existing logic, maybe adjust)
		# Actually, user wants "size up from center". 
		# We'll Scale it up instead of just moving it, or both.
		var progress = _ease_out_cubic(anim_progress)
		var scale_val = lerp(Vector3.ZERO, Vector3.ONE, progress)
		$ScreenContainer.scale = scale_val
		
		# Also manage Projector Particles
		if has_node("ProjectorMesh/HoloParticles"):
			$ProjectorMesh/HoloParticles.emitting = is_active


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

func set_active_debug(val: bool) -> void:
	active = val
	set_active(val, true) # Immediate update for editor
