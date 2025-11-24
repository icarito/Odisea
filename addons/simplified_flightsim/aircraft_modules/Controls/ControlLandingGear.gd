extends AircraftModule
class_name AircraftModule_ControlLandingGear

export(bool) var ControlActive = true

var landing_gear_modules = []
var is_deployed = true # Asumimos que empieza desplegado, como en el ejemplo

func _ready():
	ReceiveInput = true
	
func setup(aircraft_node):
	aircraft = aircraft_node
	landing_gear_modules = aircraft.find_modules_by_type("landing_gear")
	if not landing_gear_modules.empty():
		print("ControlLandingGear: Landing gear modules found: %s" % str(landing_gear_modules))
		# Asumimos el estado inicial del primer módulo encontrado
		is_deployed = landing_gear_modules[0].InitialState == 1 # 1 es Deployed
	else:
		print("ControlLandingGear: WARNING - No landing gear modules found.")

func receive_input(event):
	if landing_gear_modules.empty() or (not ControlActive):
		return

	# --- Control por Teclado ---
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.scancode == KEY_L: # Tecla L para el tren de aterrizaje
			print("ControlLandingGear: Matched Key L. Toggling gear.")
			_toggle_gear()

	if event is InputEventJoypadButton and event.pressed:
		print("ControlLandingGear: Joypad button pressed. Index: ", event.button_index)
		if event.button_index == 6: # Botón Select
			print("ControlLandingGear: Matched Select (6). Toggling gear.")
			_toggle_gear()

func _toggle_gear():
	is_deployed = not is_deployed
	print("ControlLandingGear: Toggling gear. New state: ", "Deployed" if is_deployed else "Stowed")
	for gear_module in landing_gear_modules:
		if is_deployed:
			gear_module.deploy()
		else:
			gear_module.stow()