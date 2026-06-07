extends VBoxContainer
class_name OysCameras

# FD-161: OdiseaOS Surveillance Camera App
# Acts as a Viewport-based camera switcher.

export(float) var preview_width := 480.0
export(float) var preview_height := 360.0
export(bool) var show_framerate := false
export(float) var camera_switch_time := 0.3

var _header: HBoxContainer
var _back_button: Button
var _status_label: Label
var _content_stack: Control
var _browse_view: ScrollContainer
var _camera_list: VBoxContainer
var _preview_view: ViewportContainer
var _viewport: Viewport
var _current_camera: Spatial = null

class CameraEntry:
	var name: String
	var rig: Spatial
	var camera_node: Spatial
	var groups: Array
	var is_recording: bool = false
	var list_button: Button = null

var _cameras: Array = [] # Array of CameraEntry
var _blink_timer := 0.0

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	theme = preload("res://core_v2/ui/retro/RetroOS.tres")

	_setup_ui()
	_discover_cameras()
	_show_browse()

func _setup_ui() -> void:
	# Header
	_header = HBoxContainer.new()
	add_child(_header)

	_back_button = Button.new()
	_back_button.text = "<- Back"
	_back_button.connect("pressed", self, "_on_back_pressed")
	_header.add_child(_back_button)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_status_label.text = "SURVEILLANCE"
	_status_label.align = Label.ALIGN_CENTER
	_header.add_child(_status_label)

	# Content Stack
	_content_stack = Control.new()
	_content_stack.size_flags_horizontal = SIZE_EXPAND_FILL
	_content_stack.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_content_stack)

	# Browse View
	_browse_view = ScrollContainer.new()
	_browse_view.anchor_right = 1.0
	_browse_view.anchor_bottom = 1.0
	_content_stack.add_child(_browse_view)

	_camera_list = VBoxContainer.new()
	_camera_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_browse_view.add_child(_camera_list)

	# Preview View
	_preview_view = ViewportContainer.new()
	_preview_view.stretch = true
	_preview_view.anchor_right = 1.0
	_preview_view.anchor_bottom = 1.0
	_preview_view.visible = false
	_content_stack.add_child(_preview_view)

	_viewport = Viewport.new()
	_viewport.size = Vector2(preview_width, preview_height)
	_viewport.render_target_v_flip = true
	_preview_view.add_child(_viewport)

	var vp_cam = Camera.new()
	_viewport.add_child(vp_cam)
	_viewport_camera = vp_cam

	# Footer
	var footer = HBoxContainer.new()
	add_child(footer)
	var version_label = Label.new()
	version_label.text = "OD-OS v4.21 | SURVEILLANCE"
	footer.add_child(version_label)
	_cam_name_footer = Label.new()
	_cam_name_footer.size_flags_horizontal = SIZE_EXPAND_FILL
	_cam_name_footer.align = Label.ALIGN_RIGHT
	footer.add_child(_cam_name_footer)

var _viewport_camera: Camera
var _cam_name_footer: Label

func _process(delta: float) -> void:
	if is_instance_valid(_current_camera) and is_instance_valid(_viewport_camera):
		_viewport_camera.global_transform = _current_camera.global_transform

	if _browse_view.visible:
		_blink_timer += delta
		var is_on = fmod(_blink_timer, 1.0) < 0.5
		_update_list_blinking(is_on)

func _update_list_blinking(is_on: bool) -> void:
	for entry in _cameras:
		if entry.list_button and entry.is_recording:
			var status_text = " ● REC" if is_on else "   REC"
			entry.list_button.text = entry.name + status_text

func _discover_cameras() -> void:
	_cameras.clear()
	var rigs = get_tree().get_nodes_in_group("vcamera_system")

	# Fallback scan
	if rigs.empty():
		for child in get_tree().root.get_children():
			if child is VCameraSystemRig:
				rigs.append(child)

	for rig in rigs:
		var vcameras_node = rig.get_node_or_null("VCameras")
		if vcameras_node:
			for vcam in vcameras_node.get_children():
				if vcam is Spatial:
					var entry = CameraEntry.new()
					entry.name = vcam.name
					entry.rig = rig
					entry.camera_node = vcam
					entry.groups = vcam.get_groups()
					entry.is_recording = _check_recording_status(vcam)
					_cameras.append(entry)

	_populate_list()

func _check_recording_status(vcam: Spatial) -> bool:
	var sec_cams = get_tree().get_nodes_in_group("security_camera")
	if sec_cams.empty():
		sec_cams = _find_nodes_by_class(get_tree().root, "SecurityCameraV2")

	for cam in sec_cams:
		if cam is Spatial:
			if cam.global_transform.origin.distance_to(vcam.global_transform.origin) < 5.0:
				if "recording" in cam:
					return cam.recording
	return false

func _find_nodes_by_class(node: Node, class_name_str: String) -> Array:
	var found = []
	var script = node.get_script()
	var is_match = node.is_class(class_name_str)
	if not is_match and script:
		if script.resource_path.ends_with(class_name_str + ".gd"):
			is_match = true

	if is_match:
		found.append(node)
	for child in node.get_children():
		found += _find_nodes_by_class(child, class_name_str)
	return found

func _populate_list() -> void:
	for child in _camera_list.get_children():
		child.queue_free()

	# Group by tags
	var grouped = {} # String (tag) -> Array (CameraEntry)
	var untagged = []

	for entry in _cameras:
		var tags = []
		for g in entry.groups:
			if not g.begins_with("_"): # Filter out internal groups
				tags.append(g)

		if tags.empty():
			untagged.append(entry)
		else:
			for tag in tags:
				if not grouped.has(tag):
					grouped[tag] = []
				grouped[tag].append(entry)

	for tag in grouped:
		_add_tag_header(tag)
		for entry in grouped[tag]:
			_add_camera_button(entry)

	if not untagged.empty():
		_add_tag_header("Other")
		for entry in untagged:
			_add_camera_button(entry)

func _add_tag_header(tag: String) -> void:
	var label = Label.new()
	label.text = "--- " + tag.to_upper() + " ---"
	label.add_color_override("font_color", Color("e0af41")) # Amber
	_camera_list.add_child(label)

func _add_camera_button(entry: CameraEntry) -> void:
	var btn = Button.new()
	var rec_status = " ● REC" if entry.is_recording else " ○ OFF"
	btn.text = entry.name + rec_status
	btn.align = Button.ALIGN_LEFT
	btn.connect("pressed", self, "_on_camera_selected", [entry])
	_camera_list.add_child(btn)
	entry.list_button = btn

func _on_camera_selected(entry: CameraEntry) -> void:
	_current_camera = entry.camera_node
	_cam_name_footer.text = "CAM: " + entry.name
	_show_preview()

func _on_back_pressed() -> void:
	if _preview_view.visible:
		_show_browse()
	else:
		_close_app()

func _show_browse() -> void:
	_browse_view.visible = true
	_preview_view.visible = false
	_back_button.visible = true
	_back_button.text = "X Close"
	_status_label.text = "SURVEILLANCE | BROWSE"
	_cam_name_footer.text = ""
	_current_camera = null

func _show_preview() -> void:
	_browse_view.visible = false
	_preview_view.visible = true
	_back_button.text = "<- Back"
	_status_label.text = "SURVEILLANCE | LIVE"

func _close_app() -> void:
	queue_free()

# ESC (ui_cancel) handling removed to comply with system-level constraints.
# Users should use the "Back" or "Close" buttons in the UI.
