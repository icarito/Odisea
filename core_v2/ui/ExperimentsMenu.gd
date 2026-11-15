extends PopupPanel

# Submenu "Experimentos" del menu principal: un boton por episodio de prueba
# (core_v2/levels/Experiments.gd). Elegir uno emite la escena; el menu la arranca como
# cualquier partida.

signal experiment_chosen(scene_path)

const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
const Experiments = preload("res://core_v2/levels/Experiments.gd")

var _list: VBoxContainer = null


func _ready() -> void:
	VirtualMouse.attach_popup(self)
	_list = VBoxContainer.new()
	_list.add_constant_override("separation", 10)
	add_child(_list)
	for entry in Experiments.LIST:
		if not ResourceLoader.exists(str(entry["scene"])):
			continue
		var button := Button.new()
		button.name = str(entry["id"])
		button.text = tr(str(entry["title"])).to_upper()
		button.rect_min_size = Vector2(320, 48)
		button.connect("pressed", self, "_on_pressed", [str(entry["scene"])])
		_list.add_child(button)


func open() -> void:
	popup_centered()
	if _list.get_child_count() > 0:
		(_list.get_child(0) as Button).grab_focus()


func _on_pressed(scene_path: String) -> void:
	hide()
	emit_signal("experiment_chosen", scene_path)
