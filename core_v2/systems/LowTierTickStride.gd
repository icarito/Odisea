extends Reference

# FD-299: espacia un sistema ambiental del tick de fisica en el tier LOW del gate.
#
# En el Anbernic el tick de Dome_Intro era ~18 ms de GDScript y a ese costo cada frame
# arrastraba varios ticks; los sistemas que solo pintan o resumen estado no necesitan
# correr en cada uno. step() devuelve el delta acumulado cuando toca procesar y -1.0
# cuando no. Fuera del tier el paso es 1 y devuelve el mismo delta: desktop, CI y
# replays no cambian.
#
#   var _paso_lowend = preload("res://core_v2/systems/LowTierTickStride.gd").new(self, 2)
#   func _physics_process(delta):
#       delta = _paso_lowend.step(delta)
#       if delta < 0.0:
#           return

var _dueno: WeakRef
var _paso_low := 1
var _paso := 0
var _ticks := 0
var _acumulado := 0.0

func _init(dueno: Node, paso_low: int) -> void:
	_dueno = weakref(dueno)
	_paso_low = max(1, paso_low)

func step(delta: float) -> float:
	if _paso == 0:
		var dueno = _dueno.get_ref()
		if dueno == null or not dueno.is_inside_tree():
			return delta
		var gate = dueno.get_node_or_null("/root/GLES3VendorGate")
		_paso = _paso_low if gate != null and gate.is_low_tier() else 1
	_ticks += 1
	_acumulado += delta
	if _ticks < _paso:
		return -1.0
	var total := _acumulado
	_ticks = 0
	_acumulado = 0.0
	return total
