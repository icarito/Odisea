extends Spatial

# Referencia al nodo BakedLightmap de tu escena
onready var baked_lightmap_node = $".."            # BakedLightmap (si existe)
onready var env := get_tree().get_current_scene().find_node("Environment", true, false)

# FPS mínimo que consideras aceptable
const MIN_FPS := 20

# Bandera para saber si la iluminación ya está desactivada
var is_light_disabled := false
var _time_since_start := 0.0
var _cooldown := 0.0
const START_DELAY := 2.0
const CHECK_INTERVAL := 0.5

func _ready():
	# Ajustes base para GLES2
	# MSAA y efectos de postproceso fuera
	
	"""
	# Environment: quitar Glow/SSAO/Reflections si están
	if env and env.has_method("get_environment"):
		var e = env.get_environment()
		if e:
			e.glow_enabled = false
			e.ssao_enabled = false
			e.tone_mapper = Environment.TONE_MAPPER_LINEAR
			e.ssa_enabled = false
			e.dof_blur_far_enabled = false
			e.dof_blur_near_enabled = false
	"""

func _process(delta):
	# Acumula tiempo desde que inicia la escena
	_time_since_start += delta
	# Espera 2 segundos antes de comenzar a chequear
	if _time_since_start < START_DELAY:
		return

	# Enfriamiento para evitar ejecutar cada frame
	_cooldown -= delta
	if _cooldown > 0.0:
		return

	# Reinicia cooldown para que corra cada 0.5s
	_cooldown = CHECK_INTERVAL

	var fps := Engine.get_frames_per_second()
	if fps < MIN_FPS and not is_light_disabled:
		toggle_heavy_features(false)
		is_light_disabled = true
		print("FPS bajo: efectos pesados DESACTIVADOS.")
	elif fps >= (MIN_FPS + 5) and is_light_disabled:
		toggle_heavy_features(true)
		is_light_disabled = false
		print("FPS recuperados: efectos pesados ACTIVADOS.")

func toggle_heavy_features(enable: bool):
	# 1) Lightmap horneado (en GLES2 no aplica; por si lo tienes en desktop)
	if baked_lightmap_node and baked_lightmap_node is BakedLightmap:
		baked_lightmap_node.visible = enable

	# 2) Sombras dinámicas (muy costosas en GLES2)
	for light in get_tree().get_nodes_in_group("lights"): # crea este grupo en tus luces
		if light is OmniLight or light is SpotLight or light is DirectionalLight:
			light.shadow_enabled = enable
			# Reducir energía y rango cuando desactivas sombras ayuda a rendimiento
			if not enable:
				if light is OmniLight:
					light.omni_range = min(light.omni_range, 16.0)
				if light is SpotLight:
					light.spot_range = min(light.spot_range, 20.0)

	# 3) Partículas: apágalas si hay muchas
	for p in get_tree().get_nodes_in_group("particles"):
		if p is Particles or p is CPUParticles:
			p.emitting = enable

	# 4) Postprocesos (glow/ssao) desde Environment
	if env and env.has_method("get_environment"):
		var e = env.get_environment()
		if e:
			e.glow_enabled = enable
			e.ssao_enabled = enable

	# 5) Materiales: usar un shader simple (opcional)
	# Puedes marcar materiales prototipo sin iluminación cuando enable=false.
	# Recorre nodos MeshInstance si quieres aplicar material ligero.
