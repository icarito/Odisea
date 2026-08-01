extends Spatial

# TestScene_DDCKinetic.gd
# Configura el DDCSpawner (los gates ya estan definidos como hijos en la .tscn,
# porque DDCSpawner._ready() escanea sus children ANTES de que corra este script).

onready var spawner = $DDCSpawner

func _ready() -> void:
	spawner.spawn_interval = 8.0
	spawner.max_simultaneous_ddc = 3
	spawner.progressive_limit = true
	spawner.progressive_escalation_interval = 6.0

	print("DDC Kinetic Test Ready — corre y sobrevive")
