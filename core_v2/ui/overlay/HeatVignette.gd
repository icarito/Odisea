extends Control

# FD-051: viñeta roja de calor. Capa VISUAL pura, one-way.
#
# Deriva su alpha del ratio de integridad del traje y de si hay contacto de calor activo.
# No entra al snapshot: en un replay se recomputa idéntica desde el ratio, que sí es
# determinista.

# Pulso base mientras hay contacto de calor.
export(float) var base_pulse := 0.22
# Cuánto pesa la degradación del traje en la intensidad.
export(float) var damage_weight := 0.75
# Velocidad del pulso (rad/s) con contacto activo.
export(float) var pulse_speed := 4.0
# Amplitud del pulso.
export(float) var pulse_amount := 0.12
# Suavizado hacia la intensidad objetivo.
export(float) var responsiveness := 6.0
# Ratio bajo el cual la viñeta entra en modo peligro (pulso rápido, avance al centro).
export(float) var danger_ratio := 0.3
# Desplazamiento UV máximo de la onda de calor. Es deliberadamente pequeño para no marear.
export(float) var max_distortion := 0.007

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _ratio := 1.0
var _heat_active := false
var _heat_hold := 0.0
var _intensity := 0.0
var _pulse_time := 0.0
var _heat_proximity := 0.0
var _distortion := 0.0
var _damage_direction := Vector2.ZERO
var _directionality := 0.0

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_rect = get_node_or_null("Vignette")
	if is_instance_valid(_rect) and _rect.material is ShaderMaterial:
		_material = _rect.material
	_apply_to_shader(0.0, 0.0)
	var _err = get_viewport().connect("size_changed", self, "_on_viewport_resized")
	_on_viewport_resized()

# Conecta este overlay a un SuitThermalResistance concreto (se llama de nuevo en cada
# respawn, con un traje recién creado): limpia todo estado visual residual del anterior
# antes de re-atarse, si no la viñeta puede quedar a full tras morir quemado.
func bind_suit(suit: Node) -> void:
	if not is_instance_valid(suit):
		return
	_heat_active = false
	_heat_hold = 0.0
	_pulse_time = 0.0
	_intensity = 0.0
	_ratio = 1.0
	_heat_proximity = 0.0
	_distortion = 0.0
	if suit.has_signal("thermal_state_changed") and not suit.is_connected("thermal_state_changed", self, "set_thermal_ratio"):
		var _e1 = suit.connect("thermal_state_changed", self, "set_thermal_ratio")
	if suit.has_method("get_ratio"):
		set_thermal_ratio(suit.get_ratio())
	_apply_to_shader(0.0, 0.0)

func set_thermal_ratio(ratio: float) -> void:
	var previous := _ratio
	_ratio = clamp(ratio, 0.0, 1.0)
	# Una bajada de integridad implica contacto activo; se sostiene un instante.
	if _ratio < previous - 0.00001:
		_heat_hold = 0.35

# El contacto de calor llega como pulsos por frame; el hold decae solo, así que un
# emisor que deja de reportar apaga la viñeta sin necesitar un set_heat_active(false).
func set_heat_active(active: bool) -> void:
	if active:
		_heat_hold = 0.35
	else:
		_heat_active = false
		_heat_hold = 0.0

func set_heat_proximity(proximity: float) -> void:
	_heat_proximity = clamp(proximity, 0.0, 1.0)

# API común para futuras viñetas de daño. La dirección está en espacio de pantalla:
# +X derecha, +Y abajo; Vector2.ZERO mantiene el efecto radial.
func set_hazard_active(active: bool) -> void:
	set_heat_active(active)

func set_hazard_proximity(proximity: float) -> void:
	set_heat_proximity(proximity)

func set_damage_direction(direction: Vector2, strength: float = 1.0) -> void:
	_damage_direction = direction.limit_length(1.0)
	_directionality = clamp(strength, 0.0, 1.0)
	if is_instance_valid(_material):
		_material.set_shader_param("damage_direction", _damage_direction)
		_material.set_shader_param("directionality", _directionality)

func _process(delta: float) -> void:
	if get_tree().paused:
		_distortion = 0.0
		_apply_to_shader(_intensity, 0.0)
		return
	if _heat_hold > 0.0:
		_heat_hold = max(_heat_hold - delta, 0.0)
	var contact_active: bool = _heat_active or _heat_hold > 0.0

	var target := 0.0
	if contact_active:
		target += base_pulse
	target += (1.0 - _ratio) * damage_weight

	if contact_active:
		var speed := pulse_speed
		if _ratio <= danger_ratio:
			speed *= 2.0
		_pulse_time += delta * speed
		target += sin(_pulse_time) * pulse_amount
	else:
		_pulse_time = 0.0

	target = clamp(target, 0.0, 1.0)
	_intensity = lerp(_intensity, target, clamp(delta * responsiveness, 0.0, 1.0))
	var distortion_target := _heat_proximity * _heat_proximity * max_distortion
	_distortion = lerp(_distortion, distortion_target, clamp(delta * responsiveness, 0.0, 1.0))

	var creep := 0.0
	if danger_ratio > 0.0 and _ratio < danger_ratio:
		creep = clamp(1.0 - (_ratio / danger_ratio), 0.0, 1.0)
	_apply_to_shader(_intensity, creep)

	if is_instance_valid(_rect):
		_rect.visible = _intensity > 0.002 or _distortion > 0.00002

func _apply_to_shader(intensity: float, creep: float) -> void:
	if not is_instance_valid(_material):
		return
	_material.set_shader_param("intensity", intensity)
	_material.set_shader_param("creep", creep)
	_material.set_shader_param("distortion", _distortion)
	_material.set_shader_param("damage_direction", _damage_direction)
	_material.set_shader_param("directionality", _directionality)

func _on_viewport_resized() -> void:
	if not is_instance_valid(_material):
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y > 0.0:
		_material.set_shader_param("aspect", size.x / size.y)
