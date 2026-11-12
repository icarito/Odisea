extends Spatial
# Sin class_name: registrarlo exige que el editor reescriba project.godot.

# FD-320: arma un nivel de maquinas a partir de un layout JSON. El mismo formato sirve
# para (a) los niveles prehechos, (b) guardar/cargar lo que arma el jugador y (c) el
# futuro editor. Contrato del formato: .operator-shared/specs/machine-layout.md
#
# Items (todos aceptan "name", "pos" [x,y,z] y "rot" [x,y,z] en grados):
#   block  — geometria estatica: "size", "color"
#   part   — MachinePart: "size", "density", "held", "color"
#   hinge  — MachineHinge: "a", "b" (nombres de items), "limit" [lo,hi], "motor" {speed,torque,on}, "axle" (bool)
#   scene  — instancia cualquier .tscn: "path", "props" {propiedad: valor}
#   link   — conecta una senal: "from", "signal", "to", "method", "args", "delay" (s)

const MachinePart = preload("res://core_v2/props/machines/MachinePart.gd")
const MachineHinge = preload("res://core_v2/props/machines/MachineHinge.gd")

export(String, FILE, "*.json") var layout_path := ""

var _items := {} # name -> Node
var _pending := [] # links con retardo: [ticks_restantes, destino, metodo, args]


func _ready() -> void:
	set_physics_process(false)
	if layout_path != "":
		load_layout_file(layout_path)


func load_layout_file(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		push_error("MachineLevel: no se pudo abrir " + path)
		return false
	var parsed := JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not (parsed.result is Dictionary):
		push_error("MachineLevel: JSON invalido en %s (linea %d)" % [path, parsed.error_line])
		return false
	build(parsed.result)
	return true


func build(layout: Dictionary) -> void:
	var links := []
	for item in layout.get("items", []):
		if not (item is Dictionary):
			continue
		if str(item.get("type", "")) == "link":
			links.append(item)
			continue
		var node := _make(item)
		if node == null:
			continue
		node.name = str(item.get("name", node.name))
		node.set_meta("layout_item", item)
		_place(node, item)
		add_child(node)
		_items[node.name] = node
	for link in links:
		_connect_link(link)


func get_item(item_name: String) -> Node:
	return _items.get(item_name)


# Estado actual de las piezas moviles como layout, para guardar lo que armo el jugador.
func export_layout() -> Dictionary:
	var items := []
	for node in _items.values():
		if not is_instance_valid(node) or not node.has_meta("layout_item"):
			continue
		var item: Dictionary = node.get_meta("layout_item").duplicate(true)
		var t: Transform = (node as Spatial).transform
		var e := t.basis.get_euler()
		item["pos"] = [t.origin.x, t.origin.y, t.origin.z]
		item["rot"] = [rad2deg(e.x), rad2deg(e.y), rad2deg(e.z)]
		items.append(item)
	return {"items": items}


func save_layout_file(path: String) -> bool:
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		return false
	f.store_string(JSON.print(export_layout(), "\t"))
	f.close()
	return true


func _make(item: Dictionary) -> Spatial:
	match str(item.get("type", "")):
		"block":
			return _make_block(item)
		"part":
			var part = MachinePart.new()
			part.size = _vec(item.get("size", [2, 0.2, 1]))
			part.density = float(item.get("density", 150.0))
			part.held = bool(item.get("held", false))
			if item.has("color"):
				part.color = Color(str(item["color"]))
			return part
		"hinge":
			var hinge = MachineHinge.new()
			# Las piezas son hermanas dentro de este nivel.
			hinge.body_a_path = NodePath("../" + str(item.get("a", "")))
			if str(item.get("b", "")) != "":
				hinge.body_b_path = NodePath("../" + str(item["b"]))
			if item.has("limit"):
				hinge.use_limit = true
				hinge.limit_lower_deg = float(item["limit"][0])
				hinge.limit_upper_deg = float(item["limit"][1])
			hinge.show_axle = bool(item.get("axle", true))
			var motor: Dictionary = item.get("motor", {})
			hinge.motor_speed = float(motor.get("speed", hinge.motor_speed))
			hinge.motor_torque = float(motor.get("torque", hinge.motor_torque))
			hinge.motor_enabled = bool(motor.get("on", false))
			return hinge
		"scene":
			var packed = load(str(item.get("path", "")))
			if not (packed is PackedScene):
				push_error("MachineLevel: escena invalida " + str(item.get("path", "")))
				return null
			var inst = packed.instance()
			var props: Dictionary = item.get("props", {})
			for key in props:
				var value = props[key]
				if value is Array and value.size() == 3:
					value = _vec(value)
				inst.set(key, value)
			return inst as Spatial
	push_error("MachineLevel: tipo de item desconocido: " + str(item.get("type", "")))
	return null


func _make_block(item: Dictionary) -> StaticBody:
	var size := _vec(item.get("size", [1, 1, 1]))
	var body := StaticBody.new()
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = size * 0.5
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance.new()
	var cube := CubeMesh.new()
	cube.size = size
	mesh.mesh = cube
	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(str(item.get("color", "#3a4048")))
	mat.roughness = 0.85
	mat.metallic = 0.2
	mesh.material_override = mat
	body.add_child(mesh)
	return body


func _place(node: Spatial, item: Dictionary) -> void:
	var rot := _vec(item.get("rot", [0, 0, 0]))
	node.transform = Transform(
		Basis(Vector3(deg2rad(rot.x), deg2rad(rot.y), deg2rad(rot.z))),
		_vec(item.get("pos", [0, 0, 0])))


func _connect_link(link: Dictionary) -> void:
	var from := get_item(str(link.get("from", "")))
	var to := get_item(str(link.get("to", "")))
	var sig := str(link.get("signal", "activated"))
	var method := str(link.get("method", "set_active"))
	if from == null or to == null or not from.has_signal(sig) or not to.has_method(method):
		push_error("MachineLevel: link invalido " + str(link))
		return
	# Las senales de los interactuables no llevan argumentos: se liga el valor aca.
	var args: Array = link.get("args", [])
	var delay_ticks := int(round(float(link.get("delay", 0.0)) * Engine.iterations_per_second))
	from.connect(sig, self, "_on_link_fired", [to, method, args, delay_ticks])


func _on_link_fired(to: Node, method: String, args: Array, delay_ticks: int) -> void:
	if delay_ticks <= 0:
		if is_instance_valid(to):
			to.callv(method, args)
		return
	_pending.append([delay_ticks, to, method, args])
	set_physics_process(true)


# Los retardos se cuentan en ticks de fisica (no Timer): determinista bajo replay.
func _physics_process(_delta: float) -> void:
	var i := _pending.size() - 1
	while i >= 0:
		var entry: Array = _pending[i]
		entry[0] -= 1
		if entry[0] <= 0:
			_pending.remove(i)
			if is_instance_valid(entry[1]):
				entry[1].callv(entry[2], entry[3])
		i -= 1
	if _pending.empty():
		set_physics_process(false)


static func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
