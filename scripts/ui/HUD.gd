extends Control

onready var health_label: Label = $HealthLabel

func _ready() -> void:
	if PlayerManager:
		# Connect to the signal
		PlayerManager.connect("health_updated", self, "_on_health_updated")
		# Set initial health
		_on_health_updated(PlayerManager.player_health)

func _on_health_updated(new_health: int) -> void:
	if health_label:
		health_label.text = "Health: " + str(new_health)
