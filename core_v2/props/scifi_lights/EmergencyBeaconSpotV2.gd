tool
extends PropBaseV2
class_name EmergencyBeaconSpotV2

# EmergencyBeaconSpotV2.gd - Variante de EmergencyBeaconV2.gd con SpotLight en vez de
# OmniLight, para comparar a ojo cuál se ve mejor colgado del HangingDisplay (FD-270).
# Copia deliberada, no una refactorización compartida: EmergencyBeaconV2.gd ya lo usan
# los beacons de airlock en producción, tocarlo para generalizar Omni/Spot es más riesgo
# que valor para una comparación de una noche.

export(Color) var _color := Color(1.0, 0.07, 0.0, 1.0) setget set__color
export(Color) var light_color := Color(1.0, 0.07, 0.0, 1.0) setget set_light_color
export(Color) var beacon_color := Color(1.0, 0.07, 0.0, 1.0) setget set_beacon_color
export(float, 0.1, 20.0) var rotation_speed := 3.0 # Rotations per second
export(float, 0.1, 10.0) var pulse_speed := 2.0 # Pulse frequency
export(float, 0.5, 30.0) var light_range := 6.0 setget set_light_range
export(float, 0.0, 10.0) var light_energy_max := 3.0 setget set_light_energy_max
export(float, 0.1, 8.0) var light_attenuation := 1.5 setget set_light_attenuation
export(bool) var enable_shadows := true setget set_enable_shadows
export(float, 0.0, 1.0) var pulse_min := 0.3 # Minimum pulse brightness (0 = fully off)
export(float, 0.0, 12.0) var dome_emission_energy := 3.0
export(float, 0.0, 12.0) var lens_emission_energy := 5.0
export(bool) var sound_enabled := true setget set_sound_enabled
export(float, -80.0, 24.0) var sound_unit_db := 4.0 setget set_sound_unit_db
export(float, 1.0, 120.0) var sound_max_distance := 80.0 setget set_sound_max_distance
export(int, 1, 4) var visual_tick_interval_frames := 2
# Ángulo del cono del SpotLight (no existe en la variante Omni).
export(float, 5.0, 89.0) var spot_angle_deg := 45.0 setget set_spot_angle_deg
# Ver comentario equivalente en EmergencyBeaconV2.gd: apaga la luz dinámica fuera de
# rango, la malla emisiva sigue igual de visible de lejos.
export(float, 0.0, 60.0) var light_activation_distance := 0.0
export(bool) var light_enabled := true setget set_light_enabled

var _dome_mesh: MeshInstance = null
var _base_mesh: MeshInstance = null
var _lens_mesh: MeshInstance = null
var _spot_light: SpotLight = null
var _sfx_alarm: Node = null
var _time_accumulator := 0.0
var _visual_tick_countdown := 0
var _visual_tick_accumulator := 0.0

func _ready():
	_dome_mesh = get_node_or_null("DomeMesh")
	_base_mesh = get_node_or_null("BaseMesh")
	_lens_mesh = get_node_or_null("DomeMesh/Lens")
	_spot_light = get_node_or_null("SpotLight")
	var mgr := get_node_or_null("/root/AirlockManager")
	if is_instance_valid(mgr) and is_instance_valid(mgr.get("_beacon_sfx_proxy")):
		_sfx_alarm = mgr._beacon_sfx_proxy
		var own_sfx := get_node_or_null("SFX Alarm")
		if is_instance_valid(own_sfx):
			own_sfx.queue_free()
	else:
		_sfx_alarm = get_node_or_null("SFX Alarm")
	._ready()
	_apply_settings()

	if not Engine.editor_hint and is_active and sound_enabled and is_instance_valid(_sfx_alarm):
		_sfx_alarm.play_sfx()

func set__color(v: Color) -> void:
	_color = v
	light_color = v
	beacon_color = v
	if is_inside_tree():
		_apply_color()

func set_light_color(v: Color) -> void:
	light_color = v
	_color = v
	beacon_color = v
	if is_inside_tree():
		_apply_color()

func set_beacon_color(v: Color) -> void:
	beacon_color = v
	_color = v
	light_color = v
	if is_inside_tree():
		_apply_color()

func set_light_enabled(v: bool) -> void:
	light_enabled = v
	_refresh_light_visibility()


func set_light_range(v: float) -> void:
	light_range = v
	if _spot_light:
		_spot_light.spot_range = v

func set_light_energy_max(v: float) -> void:
	light_energy_max = v
	if is_inside_tree():
		_update_visuals()

func set_light_attenuation(v: float) -> void:
	light_attenuation = v
	if _spot_light:
		_spot_light.spot_attenuation = v

func set_spot_angle_deg(v: float) -> void:
	spot_angle_deg = v
	if _spot_light:
		_spot_light.spot_angle = v

func set_enable_shadows(v: bool) -> void:
	enable_shadows = v
	if _spot_light:
		_spot_light.shadow_enabled = v

func set_sound_enabled(v: bool) -> void:
	sound_enabled = v
	if is_instance_valid(_sfx_alarm) and not sound_enabled:
		_sfx_alarm.stop_sfx()

func set_sound_unit_db(v: float) -> void:
	sound_unit_db = v
	if is_instance_valid(_sfx_alarm):
		_sfx_alarm.unit_db = v
		if "_base_unit_db" in _sfx_alarm:
			_sfx_alarm._base_unit_db = v

func set_sound_max_distance(v: float) -> void:
	sound_max_distance = v
	if is_instance_valid(_sfx_alarm):
		_sfx_alarm.max_distance = v

func set_active(value: bool, immediate: bool = false) -> void:
	var was_active = is_active
	.set_active(value, immediate)

	if Engine.editor_hint:
		return

	if is_instance_valid(_sfx_alarm):
		if value and not was_active and sound_enabled:
			if _sfx_alarm is Spatial and is_inside_tree():
				(_sfx_alarm as Spatial).global_transform = global_transform
			_sfx_alarm.play_sfx()
		elif not value and was_active:
			_sfx_alarm.stop_sfx()

func _apply_settings() -> void:
	_apply_color()
	set_light_range(light_range)
	set_light_enabled(light_enabled)
	set_light_attenuation(light_attenuation)
	set_spot_angle_deg(spot_angle_deg)
	set_enable_shadows(enable_shadows)
	set_sound_unit_db(sound_unit_db)
	set_sound_max_distance(sound_max_distance)
	set_sound_enabled(sound_enabled)
	_update_visuals()

func _apply_color():
	if _spot_light:
		_spot_light.light_color = light_color
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		_dome_mesh.material_override.emission = light_color
	if _lens_mesh and _lens_mesh.material_override is SpatialMaterial:
		_lens_mesh.material_override.emission = light_color

func _physics_process(delta: float) -> void:
	._physics_process(delta)
	var visual_dt = _consume_visual_tick(delta)
	if visual_dt < 0.0:
		return
	if is_active:
		_time_accumulator += visual_dt

		if _dome_mesh:
			_dome_mesh.rotation.y = _time_accumulator * rotation_speed * TAU

		if _spot_light:
			_refresh_light_visibility()
			if _spot_light.visible:
				var pulse = lerp(pulse_min, 1.0, (sin(_time_accumulator * pulse_speed * TAU) + 1.0) * 0.5)
				_spot_light.light_energy = pulse * light_energy_max * anim_progress

		if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
			var pulse = lerp(pulse_min, 1.0, (sin(_time_accumulator * pulse_speed * TAU) + 1.0) * 0.5)
			_dome_mesh.material_override.emission_energy = pulse * dome_emission_energy * anim_progress
		if _lens_mesh and _lens_mesh.material_override is SpatialMaterial:
			var pulse = lerp(pulse_min, 1.0, (sin(_time_accumulator * pulse_speed * TAU) + 1.0) * 0.5)
			_lens_mesh.material_override.emission_energy = pulse * lens_emission_energy * anim_progress

func _refresh_light_visibility() -> void:
	if _spot_light == null:
		return
	var should_light: bool = light_enabled and is_active and anim_progress > 0.01 \
		and _player_within_light_range()
	if _spot_light.visible != should_light:
		_spot_light.visible = should_light


func _player_within_light_range() -> bool:
	if not light_enabled:
		return false
	if light_activation_distance <= 0.0:
		return true
	if Engine.editor_hint:
		return true
	var player: Spatial = null
	var session := get_node_or_null("/root/SessionManager")
	if is_instance_valid(session):
		player = session.player
	if not is_instance_valid(player):
		return true
	var reach := light_activation_distance * light_activation_distance
	return global_transform.origin.distance_squared_to(player.global_transform.origin) <= reach


func _wants_continuous_step() -> bool:
	return is_active

func _update_visuals() -> void:
	._update_visuals()
	_refresh_light_visibility()
	var t = anim_progress
	if _spot_light:
		if t < 0.1:
			_spot_light.light_energy = 0.0
		else:
			_spot_light.light_energy = t * light_energy_max
	if _dome_mesh and _dome_mesh.material_override is SpatialMaterial:
		if t < 0.1:
			_dome_mesh.material_override.emission_energy = 0.1
		else:
			_dome_mesh.material_override.emission_energy = t * dome_emission_energy
	if _lens_mesh and _lens_mesh.material_override is SpatialMaterial:
		if t < 0.1:
			_lens_mesh.material_override.emission_energy = 0.1
		else:
			_lens_mesh.material_override.emission_energy = t * lens_emission_energy

func get_snapshot() -> Dictionary:
	var snap = .get_snapshot()
	snap["beacon_time"] = _time_accumulator
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_time_accumulator = data.get("beacon_time", 0.0)

func _consume_visual_tick(delta: float) -> float:
	_visual_tick_accumulator += max(0.0, delta)
	if visual_tick_interval_frames <= 1:
		var dt = _visual_tick_accumulator
		_visual_tick_accumulator = 0.0
		return dt
	if _visual_tick_countdown > 0:
		_visual_tick_countdown -= 1
		return -1.0
	_visual_tick_countdown = visual_tick_interval_frames - 1
	var sampled_dt = _visual_tick_accumulator
	_visual_tick_accumulator = 0.0
	return sampled_dt
