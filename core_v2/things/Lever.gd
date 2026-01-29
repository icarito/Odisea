extends Spatial
tool

export(Material) var base_material setget set_base_material
export(Color) var lever_color = Color(1, 0.5, 0.1) setget set_lever_color


onready var base = $LeverBase
onready var lever = $LeverBase/RotatingLever

func set_base_material(mat):
	base_material = mat
	if base and base_material:
		base.material = base_material
	# No llamar a update(), Spatial no lo tiene

func set_lever_color(c):
	lever_color = c
	if lever:
		var mesh_instance = _find_mesh_instance(lever)
		if mesh_instance:
			var mat = mesh_instance.get_surface_material(0)
			if not mat:
				mat = SpatialMaterial.new()
				mesh_instance.set_surface_material(0, mat)
			# SpatialMaterial always has 'albedo_color', so set it directly
			mat.albedo_color = lever_color
	# No llamar a update(), Spatial no lo tiene

# Recursively find the first MeshInstance in the node tree

func _find_mesh_instance(node):
	   if node is MeshInstance:
		   return node
	   for child in node.get_children():
		   var found = _find_mesh_instance(child)
		   if found:
			   return found
	   return null


# Ensure properties update in editor and runtime
func _ready():
	set_base_material(base_material)
	set_lever_color(lever_color)

	# Intentar conectar la señal 'activated' del RotatingObjectV2 (hijo RotatingLever)
	var rotating = _find_rotating_object(lever)
	if rotating:
		if rotating.has_signal("activated"):
			rotating.connect("activated", self, "_on_lever_activated")
		if rotating.has_signal("deactivated"):
			rotating.connect("deactivated", self, "_on_lever_deactivated")

func _find_rotating_object(node):
	if node and node.get_script() and node.get_script().resource_path.find("RotatingObjectV2.gd") != -1:
		return node
	for child in node.get_children():
		var found = _find_rotating_object(child)
		if found:
			return found
	return null

# Handler para la señal de la palanca
func _on_lever_activated():
	# Buscar Conveyor llamado 'LeverConveyor' en la escena
	var root = get_tree().current_scene
	if not root:
		return
	var conveyor = root.get_node_or_null("LeverConveyor")
	if conveyor and conveyor.has_method("set_active"):
		conveyor.set_active(true)


# Handler para desactivar
func _on_lever_deactivated():
	   var root = get_tree().current_scene
	   if not root:
		   return
	   var conveyor = root.get_node_or_null("LeverConveyor")
	   if conveyor and conveyor.has_method("set_active"):
		   conveyor.set_active(false)


func _notification(what):
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_POSTINITIALIZE or (Engine.editor_hint and what == NOTIFICATION_READY):
		set_base_material(base_material)
		set_lever_color(lever_color)

# Forzar actualización visual en editor
func _process(delta):
	if Engine.editor_hint:
		set_lever_color(lever_color)
