extends VBoxContainer
class_name NodeScan

var _tree: Tree
var _footer_label: Label

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	rect_min_size = Vector2(250, 350)
	mouse_filter = MOUSE_FILTER_PASS
	focus_mode = FOCUS_NONE


	var top_bar = HBoxContainer.new()
	add_child(top_bar)

	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.focus_mode = FOCUS_NONE
	refresh_btn.connect("pressed", self , "_on_refresh_pressed")

	refresh_btn.add_color_override("font_color", Color("9bfa94")) # Green
	refresh_btn.add_color_override("font_color_focus", Color("e0af41")) # Amber
	refresh_btn.add_color_override("font_color_hover", Color("e0af41")) # Amber
	top_bar.add_child(refresh_btn)

	rect_clip_content = true
	
	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.rect_min_size = Vector2(100, 250)
	_tree.hide_root = false
	_tree.allow_reselect = true # Help with focus/redraw triggers
	_tree.connect("item_selected", self , "_on_item_selected")
	_tree.connect("gui_input", self , "_on_tree_gui_input")
	_tree.mouse_filter = MOUSE_FILTER_STOP
	_tree.focus_mode = FOCUS_NONE # CRITICAL: Stop the tree from blanking when it gains focus


	# Style the tree internals
	_tree.add_color_override("font_color", Color("9bfa94")) # Green
	_tree.add_color_override("font_color_selected", Color("ffffff")) # White text for contrast on amber
	
	var tree_bg = StyleBoxFlat.new()
	tree_bg.bg_color = Color("1a241b") # Solid dark background
	tree_bg.border_width_left = 1
	tree_bg.border_width_top = 1
	tree_bg.border_width_right = 1
	tree_bg.border_width_bottom = 1
	tree_bg.border_color = Color("56755c")
	_tree.add_stylebox_override("bg", tree_bg) # USE SOLID BG
	_tree.add_stylebox_override("bg_focus", tree_bg)
	
	var selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color("e0af41") # Amber selection
	_tree.add_stylebox_override("selected", selected_style)
	_tree.add_stylebox_override("selected_focus", selected_style)
	
	add_child(_tree)


	_footer_label = Label.new()
	_footer_label.text = "Global Position: N/A"
	_footer_label.add_color_override("font_color", Color("9bfa94")) # Green
	add_child(_footer_label)

	_on_refresh_pressed()

func _on_refresh_pressed() -> void:
	_tree.clear()
	var root = get_tree().get_root()
	if root:
		var root_item = _tree.create_item()
		_populate_tree(root, root_item)

func _populate_tree(node: Node, tree_item: TreeItem) -> void:
	tree_item.set_text(0, node.name + " (" + node.get_class() + ")")
	tree_item.set_metadata(0, node)

	for i in range(node.get_child_count()):
		var child = node.get_child(i)
		var child_item = _tree.create_item(tree_item)
		_populate_tree(child, child_item)

func _on_item_selected() -> void:
	var selected = _tree.get_selected()
	if selected:
		var node = selected.get_metadata(0)
		if is_instance_valid(node) and node is Node:
			if node is Spatial:
				_footer_label.text = "Global Position: " + str(node.global_transform.origin)
			elif node is Node2D:
				_footer_label.text = "Global Position: " + str(node.global_position)
			elif node is Control:
				_footer_label.text = "Global Position: " + str(node.rect_global_position)
			else:
				_footer_label.text = "Global Position: N/A"
		else:
			_footer_label.text = "Node Invalid"
	_footer_label.update()
	_tree.update()

func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_tree.update()
