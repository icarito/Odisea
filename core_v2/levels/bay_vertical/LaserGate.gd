extends StaticBody
class_name LaserGate

# Puerta de LÁSER (FD-322): panel que bloquea un paso del anillo. El láser del
# `MultiToolV2` (API pública: `target.laser_hit()` por frame de física) va
# acumulando calor; al superar `cut_time` el panel se corta y abre el paso.
#
# Determinismo: la acumulación usa delta de física (acumulada en `laser_hit`,
# enfriada en `_physics_process`). Estado serializable (`get_state`/`restore_state`).

signal opened()

export(float) var cut_time := 2.5
export(float) var cool_rate := 0.4
# Incremento por `laser_hit()` (el rayo llama una vez por frame de física a 60 Hz).
const HIT_STEP := 1.0 / 60.0
export(Color) var panel_color := Color(0.35, 0.4, 0.5, 1.0)
export(Color) var heat_color := Color(1.0, 0.35, 0.12, 1.0)

var _heat := 0.0
var _opened := false

var _panel: MeshInstance = null
var _panel_mat: SpatialMaterial = null
var _collision: CollisionShape = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	_build_panel()

func _build_panel() -> void:
	_panel_mat = SpatialMaterial.new()
	_panel_mat.albedo_color = panel_color
	_panel_mat.roughness = 0.5
	_panel_mat.metallic = 0.3
	_panel_mat.emission_enabled = true
	_panel_mat.emission = Color(0.0, 0.0, 0.0, 0.0)

	_panel = MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(0.25, 3.0, 2.6)
	_panel.mesh = box
	_panel.material_override = _panel_mat
	add_child(_panel)

	_collision = CollisionShape.new()
	var colbox := BoxShape.new()
	colbox.extents = Vector3(0.18, 1.5, 1.3)
	_collision.shape = colbox
	add_child(_collision)

	# Capa 1 (Entorno): incluida en la máscara del láser del MultiTool (765) Y en la
	# máscara del jugador (79), así el rayo la detecta (laser_hit) y además bloquea
	# el paso. La capa 2 es la del jugador y el láser la excluye.
	collision_layer = 1
	collision_mask = 0

func _physics_process(_delta: float) -> void:
	if _opened:
		return
	if _heat > 0.0:
		_heat = max(0.0, _heat - cool_rate * _delta)
		_update_visual()

func laser_hit() -> void:
	if _opened:
		return
	_heat += HIT_STEP
	if _heat >= cut_time:
		_open()

func _open() -> void:
	_opened = true
	if is_instance_valid(_panel):
		_panel.visible = false
	if is_instance_valid(_collision):
		_collision.disabled = true
	collision_layer = 0
	emit_signal("opened")

func is_opened() -> bool:
	return _opened

func _update_visual() -> void:
	if not is_instance_valid(_panel_mat):
		return
	var t: float = clamp(_heat / max(cut_time, 0.001), 0.0, 1.0)
	_panel_mat.albedo_color = Color(
		panel_color.r + (heat_color.r - panel_color.r) * t,
		panel_color.g + (heat_color.g - panel_color.g) * t,
		panel_color.b + (heat_color.b - panel_color.b) * t,
		panel_color.a)
	_panel_mat.emission = heat_color * t * 2.0

func set_phase(_phase: int) -> void:
	# Las puertas de láser son independientes del ciclo; dejamos la interfaz para
	# uniformidad con el resto de atajos (sin comportamiento).
	pass

func get_state() -> Dictionary:
	return {"heat": _heat, "opened": _opened}

func restore_state(data: Dictionary) -> void:
	_heat = float(data.get("heat", 0.0))
	var was_open: bool = bool(data.get("opened", false))
	if was_open and not _opened:
		_open()
	elif not was_open and _opened:
		_opened = false
		_panel.visible = true
		_collision.disabled = false
		collision_layer = 1
