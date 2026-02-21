extends Node

# InteractComponentV2.gd - Configures interaction visuals for the player
# Place this under Logic/Interact in Pilot_V2.tscn

export(Color) var highlight_color := Color(0.0, 1.0, 1.0, 0.6) # Stronger cyan
export(Color) var proximity_color := Color(0.0, 1.0, 1.0, 0.3) # More visible proximity
export(float) var proximity_radius := 8.0 # Slightly larger range
