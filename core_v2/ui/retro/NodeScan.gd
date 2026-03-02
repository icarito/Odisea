extends WindowDialog
class_name NodeScan

var _tree: Tree
var _footer_label: Label

func _ready() -> void:
	window_title = "NODE-SCAN"
	rect_min_size = Vector2(300, 400)
	rect_size = Vector2(300, 400)
	theme = preload("res://core_v2/ui/retro/RetroOS.tres")

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_MINSIZE, 8)
	add_child(vbox)

	var top_bar = HBoxContainer.new()
	vbox.add_child(top_bar)

	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.connect("pressed", self, "_on_refresh_pressed")
	refresh_btn.add_color_override("font_color", Color("9bfa94")) # Green
	refresh_btn.add_color_override("font_color_focus", Color("e0af41")) # Amber
	refresh_btn.add_color_override("font_color_hover", Color("e0af41")) # Amber
	top_bar.add_child(refresh_btn)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = false
	_tree.connect("item_selected", self, "_on_item_selected")
	_tree.add_color_override("font_color", Color("9bfa94")) # Green
	_tree.add_color_override("font_color_selected", Color("e0af41")) # Amber
	vbox.add_child(_tree)

	_footer_label = Label.new()
	_footer_label.text = "Global Position: N/A"
	_footer_label.add_color_override("font_color", Color("9bfa94")) # Green
	vbox.add_child(_footer_label)

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
		var node = selected.get_metadata(0) as Node
		if node:
			if node is Spatial:
				_footer_label.text = "Global Position: " + str(node.global_transform.origin)
			elif node is Node2D:
				_footer_label.text = "Global Position: " + str(node.global_position)
			elif node is Control:
				_footer_label.text = "Global Position: " + str(node.rect_global_position)
			else:
				_footer_label.text = "Global Position: N/A"
