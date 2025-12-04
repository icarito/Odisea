extends Spatial

# Referencia al nodo BakedLightmap de la instancia pesada
var baked_lightmap_node = null
var heavy_instance = null
var heavy_effects_scene = preload("res://scenes/common/HeavyEffects.tscn")

# FPS mínimo que consideras aceptable
const MIN_FPS := 20

# Bandera para saber si la iluminación ya está desactivada
var is_light_disabled := false
var _time_since_start := 0.0
var _cooldown := 0.0
const START_DELAY := 2.0
const CHECK_INTERVAL := 0.5

func _ready():
	# Espera un poco para medir FPS inicial
	yield(get_tree().create_timer(START_DELAY), "timeout")
	var fps = Engine.get_frames_per_second()
	if fps > MIN_FPS:
		heavy_instance = heavy_effects_scene.instance()
		get_parent().add_child(heavy_instance)
		baked_lightmap_node = heavy_instance.get_node("BakedLightmap")
		is_light_disabled = false
	else:
		is_light_disabled = true

func _process(delta):
	# Acumula tiempo desde que inicia la escena
	_time_since_start += delta
	# Espera START_DELAY segundos antes de comenzar a chequear
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
	if enable:
		if not heavy_instance:
			heavy_instance = heavy_effects_scene.instance()
			get_parent().add_child(heavy_instance)
			baked_lightmap_node = heavy_instance.get_node("BakedLightmap")
		heavy_instance.visible = true
		var light = heavy_instance.get_node_or_null("OmniLight")
		if light:
			light.shadow_enabled = true
	else:
		if heavy_instance:
			get_parent().remove_child(heavy_instance)
			heavy_instance.queue_free()
			heavy_instance = null
			baked_lightmap_node = null

	# Partículas: apágalas si hay muchas
	for p in get_tree().get_nodes_in_group("particles"):
		if p is Particles or p is CPUParticles:
			p.emitting = enable

	# Postprocesos (glow/ssao) desde Environment
	var env = get_tree().get_current_scene().find_node("Environment", true, false)
	if env and env.has_method("get_environment"):
		var e = env.get_environment()
		if e:
			e.glow_enabled = enable
			e.ssao_enabled = enable
