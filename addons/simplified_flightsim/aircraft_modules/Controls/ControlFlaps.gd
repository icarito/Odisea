extends AircraftModule
class_name AircraftModule_ControlFlaps

export(bool) var ControlActive = true

var flaps_module = null

func _ready():
	ReceiveInput = true
	
func setup(aircraft_node):
	aircraft = aircraft_node
	# Busca el primer módulo de flaps disponible en el avión
	var flaps_modules = aircraft.find_modules_by_type("flaps")
	if not flaps_modules.empty():
		flaps_module = flaps_modules.pop_front()
		print("ControlFlaps: Flaps module found: %s" % str(flaps_module))
	else:
		print("ControlFlaps: WARNING - No flaps module found on aircraft.")

func receive_input(event):
	if (not flaps_module) or (not ControlActive):
		return

	# --- Control por Teclado ---
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.scancode == KEY_T: # Tecla T para subir flaps
			print("ControlFlaps: Matched Key T. Decreasing flaps.")
			flaps_module.flap_increase_position(-0.25)
		elif event.scancode == KEY_G: # Tecla G para bajar flaps
			print("ControlFlaps: Matched Key G. Increasing flaps.")
			flaps_module.flap_increase_position(0.25)

	if event is InputEventJoypadButton and event.pressed:
		print("ControlFlaps: Joypad button pressed. Index: ", event.button_index)
		match event.button_index:
			14: # D-Pad Izquierda
				print("ControlFlaps: Matched D-Pad Left (14). Increasing flaps.")
				flaps_module.flap_increase_position(0.25) # Aumenta flaps en pasos de 25%
			15: # D-Pad Derecha
				print("ControlFlaps: Matched D-Pad Right (15). Decreasing flaps.")
				flaps_module.flap_increase_position(-0.25) # Disminuye flaps en pasos de 25%