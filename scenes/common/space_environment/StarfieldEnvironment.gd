extends WorldEnvironment

export var star_density = 0.002 # Densidad de estrellas
export var star_size = 1.5 # Tamaño de estrellas
export var star_color = Color(1,1,1,1) # Color de estrellas
export var twinkle_speed = 0.8 # Velocidad de parpadeo

func _ready():
	# Aquí podrías modificar el shader del cielo procedural con los parámetros exportados
	pass
