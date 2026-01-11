extends Spatial

onready var pilot = $Pilot
onready var box = $Floor/BoxOnConveyor

func _ready():
	set_process(true)

func _process(_delta):
	var p_vel = Vector3.ZERO
	if pilot.has_method("get_linear_velocity"):
		p_vel = pilot.get_linear_velocity()
	elif "velocity" in pilot:
		p_vel = pilot.velocity
		
	var b_vel = box.linear_velocity
	
	if OS.get_ticks_msec() % 500 < 50: # Throttle prints
		print("T: %.2f | Pilot Vel: %s | Box Vel: %s" % [OS.get_ticks_msec() / 1000.0, p_vel, b_vel])
