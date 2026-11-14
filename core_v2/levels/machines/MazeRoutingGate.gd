extends InteractableBaseV2
class_name MazeRoutingGate

# MazeRoutingGate.gd — compuerta determinista de ruteo del laberinto de la Bahía.
#
# Reutiliza la base determinista `InteractableBaseV2` (is_active / anim_progress /
# set_active / step / snapshot en el grupo `replay_sync`) igual que los demás props
# interactuables del repo. No es un sistema nuevo de cámara/streaming: es un
# "paso/gate" que el director de ruteo (`MachineBayMazeRouting`) abre o cierra
# según el estado de las máquinas, no el jugador.
#
# El `Barrier` (StaticBody + MeshInstance) bloquea el paso cuando la compuerta está
# cerrada y se retrae bajo el piso al abrirse; la colisión se deshabilita a mitad de
# animación. La animación es puro `anim_progress` (easing de la base), sin randf ni
# reloj de pared → replay idéntico.

signal opened()
signal closed()

export(float) var open_travel := 3.2  # metros que baja el panel al abrirse (+Y local)
export(NodePath) var barrier_path := NodePath("Barrier")
export(NodePath) var status_light_path := NodePath("StatusLight")
export(Color) var color_closed := Color(0.95, 0.22, 0.08)
export(Color) var color_open := Color(0.15, 0.95, 0.75)

const PROP_COLLISION_LAYER := 64
const PROP_COLLISION_MASK := 255

var _barrier: Spatial = null
var _barrier_home := Vector3.ZERO
var _status: MeshInstance = null
var _status_mat: SpatialMaterial = null
var _closed_announced := true

func _ready() -> void:
	._ready()
	_barrier = get_node_or_null(barrier_path) as Spatial
	if _barrier != null:
		_barrier_home = _barrier.transform.origin
	_status = get_node_or_null(status_light_path) as MeshInstance
	_closed_announced = not is_active
	_update_visuals()

func is_open() -> bool:
	return is_active

func open(immediate: bool = false) -> void:
	set_active(true, immediate)

func close(immediate: bool = false) -> void:
	set_active(false, immediate)

func set_active(value: bool, immediate: bool = false) -> void:
	var changed: bool = value != is_active
	.set_active(value, immediate)
	if changed:
		if value:
			emit_signal("opened")
			_closed_announced = false
		else:
			emit_signal("closed")
			_closed_announced = true

func _update_visuals() -> void:
	if _barrier != null:
		# Al abrir, el panel baja y se oculta bajo el piso; a mitad de carrera se
		# libera la colisión para que el paso quede franco.
		_barrier.transform.origin = _barrier_home + Vector3(0.0, -open_travel * anim_progress, 0.0)
		if _barrier is CollisionObject:
			var blocked: bool = anim_progress < 0.5
			(_barrier as CollisionObject).collision_layer = PROP_COLLISION_LAYER if blocked else 0
			(_barrier as CollisionObject).collision_mask = PROP_COLLISION_MASK if blocked else 0
	if _status != null:
		if _status_mat == null:
			_status_mat = _status.material_override as SpatialMaterial
			if _status_mat == null:
				_status_mat = SpatialMaterial.new()
				_status_mat.flags_unshaded = true
				_status.material_override = _status_mat
		var col: Color = color_closed.linear_interpolate(color_open, clamp(anim_progress, 0.0, 1.0))
		_status_mat.albedo_color = col
		_status_mat.emission_enabled = true
		_status_mat.emission = col
		_status_mat.emission_energy = 1.6
