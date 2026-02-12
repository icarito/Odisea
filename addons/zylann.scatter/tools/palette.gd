tool
extends Control

signal pattern_selected(pattern_index)
signal pattern_added(path)
signal pattern_removed(path)

onready var _item_list: ItemList = get_node("VBoxContainer/ItemList")


var _file_dialog = null
var _preview_provider: EditorResourcePreview = null
var _spacing_slider: HSlider
var _spacing_label: Label
var _interval_slider: HSlider
var _interval_label: Label


func _ready():
	var vbox = get_node("VBoxContainer")
	if vbox:
		var hbox = HBoxContainer.new()
		vbox.add_child(hbox)
		vbox.move_child(hbox, 1) # Below buttons
		
		var label = Label.new()
		label.text = "Spacing: 1.0"
		hbox.add_child(label)
		_spacing_label = label
		
		var slider = HSlider.new()
		slider.min_value = 0.1
		slider.max_value = 5.0
		slider.step = 0.1
		slider.value = 1.0
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.connect("value_changed", self, "_on_spacing_changed")
		hbox.add_child(slider)
		_spacing_slider = slider

		var hbox2 = HBoxContainer.new()
		vbox.add_child(hbox2)
		vbox.move_child(hbox2, 2)
		
		var label2 = Label.new()
		label2.text = "Interval: 0.05s"
		hbox2.add_child(label2)
		_interval_label = label2
		
		var slider2 = HSlider.new()
		slider2.min_value = 0.0
		slider2.max_value = 1.0
		slider2.step = 0.05
		slider2.value = 0.05
		slider2.size_flags_horizontal = SIZE_EXPAND_FILL
		slider2.connect("value_changed", self, "_on_interval_changed")
		hbox2.add_child(slider2)
		_interval_slider = slider2


func _on_spacing_changed(value):
	if _spacing_label:
		_spacing_label.text = "Spacing: " + str(value)


func _on_interval_changed(value):
	if _interval_label:
		_interval_label.text = "Interval: " + str(value) + "s"


func get_spacing_modifier():
	if _spacing_slider:
		return _spacing_slider.value
	return 1.0


func get_paint_interval():
	if _interval_slider:
		return _interval_slider.value
	return 0.05


func setup_dialogs(base_control):
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	_file_dialog.add_filter("*.tscn ; TSCN files")
	_file_dialog.connect("file_selected", self, "_on_FileDialog_file_selected")
	_file_dialog.hide()
	base_control.add_child(_file_dialog)


func set_preview_provider(provider: EditorResourcePreview):
	assert(_preview_provider == null)
	assert(provider != null)
	_preview_provider = provider
	_preview_provider.connect("preview_invalidated", self, "_on_EditorResourcePreview_preview_invalidated")


func _exit_tree():
	if _file_dialog != null:
		_file_dialog.queue_free()
		_file_dialog = null


func load_patterns(patterns):
	var selected_pattern = get_selected_pattern()
	_item_list.clear()
	#print("Loading ", len(patterns), " patterns")
	for scene in patterns:
		add_pattern(scene.resource_path)
	if selected_pattern != null:
		var i = find_pattern(selected_pattern.path)
		if i != -1:
			_item_list.select(i)


func add_pattern(scene_path):
	# TODO I need scene thumbnails from the editor
	var default_icon = get_icon("PackedScene", "EditorIcons")
	var pattern_name = scene_path.get_file().get_basename()
	var i = _item_list.get_item_count()
	_item_list.add_item(pattern_name, default_icon)
	_item_list.set_item_metadata(i, scene_path)
	
	_preview_provider.queue_resource_preview(\
		scene_path, self, "_on_EditorResourcePreview_preview_loaded", null)


func _on_EditorResourcePreview_preview_loaded(path, texture, userdata):
	var i = find_pattern(path)
	if i == -1:
		return
	if texture != null:
		_item_list.set_item_icon(i, texture)
	else:
		print("No preview available for ", path)


func _on_EditorResourcePreview_preview_invalidated(path):
	# TODO Handle thumbnail invalidation
	#`path` is actually the folder in which the file was, NOT the file itself... useful for FileSystemDock only :(
	pass


func remove_pattern(scene_path):
	var i = find_pattern(scene_path)
	if i != -1:
		_item_list.remove_item(i)


func get_selected_pattern():
	var selected_items = _item_list.get_selected_items()
	if len(selected_items) == 0:
		return null
	var i = selected_items[0]
	var scene_path = _item_list.get_item_metadata(i)
	return {
		"index": i,
		"path": scene_path
	}


func find_pattern(path):
	for i in _item_list.get_item_count():
		var scene_path = _item_list.get_item_metadata(i)
		if scene_path == path:
			return i
	return -1


func select_pattern(path):
	var i = find_pattern(path)
	if i != -1:
		_item_list.select(i)


func _on_ItemList_item_selected(index):
	emit_signal("pattern_selected", index)


func _on_AddButton_pressed():
	_file_dialog.popup_centered_ratio(0.7)


func _on_RemoveButton_pressed():
	var s = get_selected_pattern()
	if s == null:
		return
	emit_signal("pattern_removed", s.path)


func _on_FileDialog_file_selected(fpath):
	emit_signal("pattern_added", fpath)
