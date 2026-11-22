extends Spatial
class_name DomeSpiralDetailPool

# Pool determinista de K slots de detalle (FD-321, Fase 0 B).
# Los slots se reasignan a las K placas más cercanas sólo cada N ticks.
# No toca la geometría estática de las placas: sólo mueve estos nodos.

const GEOMETRY_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralFieldGeometry.gd"
)

var slot_count: int = 8
var update_interval_ticks: int = 10
var reference_position: Vector3 = Vector3.ZERO

var _spiral_configs: Array = []
var _slots: Array = []
var _selection: Array = []
var _tick_counter: int = 0
var _revision: int = 0

func configure(
	configs: Array, p_slot_count: int, p_interval: int, p_reference: Vector3
) -> void:
	_spiral_configs = configs.duplicate(true)
	slot_count = int(max(0, p_slot_count))
	update_interval_ticks = int(max(1, p_interval))
	reference_position = p_reference
	_rebuild_slots()
	_tick_counter = 0
	update_now()

func tick() -> void:
	_tick_counter += 1
	if _tick_counter >= update_interval_ticks:
		_tick_counter = 0
		update_now()

func update_now() -> void:
	_selection = GEOMETRY_SCRIPT.select_closest_plates(
		_spiral_configs, reference_position, slot_count
	)
	for slot_index in range(_slots.size()):
		var slot: Spatial = _slots[slot_index]
		if slot_index < _selection.size():
			var selection: Dictionary = _selection[slot_index]
			var spiral: Dictionary = _spiral_configs[int(selection["spiral_index"])]
			slot.transform = GEOMETRY_SCRIPT.plate_transform(
				spiral, int(selection["plate_index"])
			)
			slot.set_meta("spiral_index", int(selection["spiral_index"]))
			slot.set_meta("plate_index", int(selection["plate_index"]))
		else:
			slot.transform = Transform.IDENTITY
			slot.set_meta("spiral_index", -1)
			slot.set_meta("plate_index", -1)
	_revision += 1

func set_reference_position(position: Vector3) -> void:
	reference_position = position
	_tick_counter = 0
	if not _slots.empty():
		update_now()

func get_revision() -> int:
	return _revision

func get_selection() -> Array:
	return _selection.duplicate(true)

func get_slots() -> Array:
	return _slots.duplicate()

func _rebuild_slots() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_slots.clear()
	for slot_index in range(slot_count):
		var slot := Spatial.new()
		slot.name = "DetailSlot_%d" % slot_index
		add_child(slot)
		_slots.append(slot)
