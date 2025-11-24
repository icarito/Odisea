extends Spatial


var template_explosion = preload("res://example/scenes/Explosion/Explosion.tscn")

onready var aircraft = get_node("Aircraft")

var is_reloading_fuel = false

func _on_Aircraft_crashed(_impact_velocity):
	var new_explosion = template_explosion.instance()
	add_child(new_explosion)
	new_explosion.global_transform.origin = $Aircraft.global_transform.origin
	new_explosion.explode()
	aircraft.queue_free()
	yield(get_tree().create_timer(2.0), "timeout")
	var __= get_tree().reload_current_scene()


func _on_Aircraft_parked():
	print("PARKED")
	if $FuelArea.overlaps_body(aircraft):
		# Parked on runway - refuel
		is_reloading_fuel = true
		print("RELOADING FUEL")


func _on_Aircraft_moved():
	# Started moving, if reloading fuel, stop
	if is_reloading_fuel:
		is_reloading_fuel = false
		print("REFUEL STOPPED")

func _unhandled_input(event):
	if is_instance_valid(aircraft):
		var control_steering = null
		# Buscar el módulo de control de steering
		for child in aircraft.get_children():
			if child is AircraftModule_ControlSteering:
				control_steering = child
				break
		if control_steering and event is InputEventJoypadButton:
			control_steering.receive_input(event)
		# Throttle con D-pad (botones 12 y 13)
		if event is InputEventJoypadButton:
			if event.button_index == 12 and event.pressed:
				if aircraft.has_method("set_engine_power"):
					aircraft.set_engine_power(aircraft.engine_power + 0.1)
			elif event.button_index == 13 and event.pressed:
				if aircraft.has_method("set_engine_power"):
					aircraft.set_engine_power(aircraft.engine_power - 0.1)

func _physics_process(delta):
	# --- Control de Steering (roll, pitch, yaw) con joypad motion ---
	var joy_id = 0 # Cambia si usas otro joypad
	if Input.is_joy_known(joy_id) and is_instance_valid(aircraft):
		var steering = aircraft.get_node_or_null("Steering")
		if steering:
			# RG351V: Ejes invertidos
			var pitch = -Input.get_joy_axis(joy_id, JOY_AXIS_1) # Elevador (X)
			var yaw = -Input.get_joy_axis(joy_id, JOY_AXIS_2)   # Rudder (Y)
			var roll = -Input.get_joy_axis(joy_id, JOY_AXIS_0)  # Aileron (Z)
			steering.set_x(pitch)
			steering.set_y(yaw)
			steering.set_z(roll)

	if is_reloading_fuel and is_instance_valid(aircraft):
		var amount_per_second = 5.0
		var is_aircraft_full = aircraft.load_energy("fuel", amount_per_second * delta)
		if is_aircraft_full:
			is_reloading_fuel = false
			print("REFUEL COMPLETE")

	# --- Controles de motor, flaps y tren de aterrizaje usando Input Actions ---
	if Input.is_action_pressed("engine_up"):
		if is_instance_valid(aircraft) and aircraft.has_method("set_engine_power"):
			aircraft.set_engine_power(aircraft.engine_power + 0.1)
	if Input.is_action_pressed("engine_down"):
		if is_instance_valid(aircraft) and aircraft.has_method("set_engine_power"):
			aircraft.set_engine_power(aircraft.engine_power - 0.1)
	if Input.is_action_just_pressed("flaps_up"):
		if is_instance_valid(aircraft) and aircraft.has_method("set_flaps"):
			aircraft.set_flaps(aircraft.flaps + 1)
	if Input.is_action_just_pressed("flaps_down"):
		if is_instance_valid(aircraft) and aircraft.has_method("set_flaps"):
			aircraft.set_flaps(aircraft.flaps - 1)
	if Input.is_action_just_pressed("gear_toggle"):
		if is_instance_valid(aircraft) and aircraft.has_method("toggle_landing_gear"):
			aircraft.toggle_landing_gear()


func _on_BtnBack_pressed():
	get_tree().change_scene("res://example/ExampleList.tscn")
