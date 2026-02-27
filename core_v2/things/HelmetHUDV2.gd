tool
extends HoloTerminalV2
class_name HelmetHUDV2

# HUD-only inspector surface. Keeps regular terminals clean.
export(bool) var hud_cfg_attach_to_active_camera := true
export(bool) var hud_cfg_attach_as_child := true
export(float, 0.0, 3.0) var hud_cfg_attach_transition_time := 0.45
export(NodePath) var hud_cfg_attach_target_path := NodePath("ScreenContainer/ScreenMesh")

export(float, 0.0, 1.0) var hud_cfg_screen_x := 0.5
export(float, 0.0, 1.0) var hud_cfg_screen_y := 0.5
export(float, 0.0, 1.0) var hud_cfg_screen_depth := 0.05
export(float, 0.0, 1.0) var hud_cfg_screen_scale := 1.0

export(float, 0.0, 10.0) var hud_cfg_interaction_radius := 6.0
export(bool) var hud_cfg_auto_close_out_of_range := true
export(bool) var hud_cfg_ui_bridge_requires_focus := true
export(bool) var hud_cfg_ui_bridge_use_system_mouse := true
export(bool) var hud_cfg_focus_on_activate := true

export(float, 0.0, 1.0) var hud_cfg_background_alpha := 0.15
export(float, 0.0, 8.0) var hud_cfg_background_emission := 3.0
export(Vector3) var hud_cfg_local_offset := Vector3.ZERO
export(Vector3) var hud_cfg_local_rotation_deg := Vector3(0, 180, 0)
export(NodePath) var hud_cfg_reference_node_path := NodePath("")

func _ready() -> void:
	_apply_hud_config()
	._ready()

func _apply_hud_config() -> void:
	attach_to_active_camera = hud_cfg_attach_to_active_camera
	hud_attach_as_child = hud_cfg_attach_as_child
	hud_attach_transition_time = hud_cfg_attach_transition_time
	hud_attach_target_path = hud_cfg_attach_target_path

	hud_screen_x = hud_cfg_screen_x
	hud_screen_y = hud_cfg_screen_y
	hud_screen_depth = hud_cfg_screen_depth
	hud_screen_scale = hud_cfg_screen_scale

	hud_interaction_radius = hud_cfg_interaction_radius
	hud_auto_close_out_of_range = hud_cfg_auto_close_out_of_range
	hud_ui_bridge_requires_focus = hud_cfg_ui_bridge_requires_focus
	hud_ui_bridge_use_system_mouse = hud_cfg_ui_bridge_use_system_mouse
	hud_focus_on_activate = hud_cfg_focus_on_activate

	hud_background_alpha = hud_cfg_background_alpha
	hud_background_emission = hud_cfg_background_emission
	hud_local_offset = hud_cfg_local_offset
	hud_local_rotation_deg = hud_cfg_local_rotation_deg
	hud_reference_node_path = hud_cfg_reference_node_path
