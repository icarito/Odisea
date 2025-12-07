extends CPUParticles

export var emission_radius = 12.0
export var particle_color = Color(0.8,0.9,1,0.7)

func _ready():
	emitting = true
	amount = self.amount
	# process_material.emission_sphere_radius = emission_radius
	# process_material.color = particle_color
