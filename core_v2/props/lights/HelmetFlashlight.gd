extends Spatial

const SpringMath = preload("res://core_v2/camera/SpringMath.gd")

export(bool) var enabled := true setget set_enabled
export(float, 0.5, 5.9) var spot_range := 5.9 setget set_spot_range
# Cono angosto a proposito: con la lampara a ~20cm del cuerpo, un cono ancho mete el
# torso y la cabeza de Elias dentro del haz y proyecta astillas de poligonos al suelo.
# Godot 3 no permite excluir un mesh de las sombras de UNA luz (light_cull_mask solo
# excluye la iluminacion, no el casteo de sombra), asi que se resuelve con geometria.
export(float, 10.0, 90.0) var spot_angle := 32.0 setget set_spot_angle
export(Color) var light_color := Color(0.85, 0.95, 1.0, 1.0) setget set_light_color
# 7.0 -> 6.0: con el cono de 32 el spot cercano clipeaba la difusa del piso de
# RingHub a blanco y tapaba su PBR. El default de aca es la fuente de runtime
# (HelmetFlashlight.tscn lo espeja); spot_range/spot_range<6 y MobileLightBudget
# quedan intactos.
export(float, 0.0, 16.0) var light_energy := 6.0 setget set_light_energy
export(bool) var scan_mode := false setget set_scan_mode
export(float, 0.1, 10.0) var scan_speed := 2.0
export(bool) var shadow_enabled := false setget set_shadow_enabled
# Relleno corto alrededor de la lampara: Elias queda detras de la SpotLight, asi que sin
# esto es una silueta negra. 0.0 lo apaga (una luz dinamica menos en movil).
export(float, 0.0, 4.0) var fill_energy := 0.6 setget set_fill_energy
export(float, 0.2, 4.0) var fill_range := 1.4 setget set_fill_range
export(Texture) var mask_texture: Texture = null
export(Vector2) var mask_tiling := Vector2(1.0, 4.0)
export(NodePath) var skeleton_path := NodePath("Visual/Pivot/Skeleton/Skinned_Mesh_0/Skeleton")
export(NodePath) var visual_pivot_path := NodePath("Visual/Pivot")
# DEF-shoulderR nace en el esternon (x = -0.04): el hueso que esta en la hombrera
# es DEF-upper_armR (x = -0.17). Solo usamos su origen, no su rotacion.
export(String) var mount_bone := "DEF-upper_armR"
# Offset sobre el hueso, en espacio del cuerpo. El modelo mira a +Z, asi que su
# derecha es -X: X negativo saca la linterna hacia afuera del hombro.
export(Vector3) var mount_offset := Vector3(-0.05, 0.09, 0.1)
# Adelanta la SpotLight (no el nodo ni el cono: el mesh emisivo y el apice del haz se
# quedan en el hombro). Es la palanca del compromiso: mas alto saca a Elias del frustum de
# sombra (menos astillas de poligonos), pero aleja del cuerpo el arranque de la zona
# iluminada. Con spot_angle angosto alcanza con poco.
export(float) var muzzle_offset := 0.3
# Apertura maxima respecto del frente del cuerpo: la linterna no atraviesa a Elias.
export(float, 10.0, 170.0) var aim_limit_deg := 75.0
# Suavizado del giro. Se aplica como 1 - exp(-k*dt), que es independiente del frame rate.
export(float, 0.5, 40.0) var aim_lerp_speed := 9.0

# Springs criticos exactos y sway/bob procedimental (FD-318)
export(float, 0.01, 1.0) var aim_half_life := 0.08
export(float, 0.0, 0.3) var turn_lead_seconds := 0.12
export(float, 0.0, 60.0) var max_turn_lead_deg := 45.0
export(float, 0.01, 1.0) var turn_lead_half_life := 0.04
export(float, 0.0, 15.0) var walk_lower_deg := 4.0
export(float, 0.01, 1.0) var walk_lower_half_life := 0.12
export(float, 0.0, 0.05) var sway_jump_gain := 0.008
export(float, 0.0, 0.1) var sway_landing_gain := 0.03
export(float, 0.0, 0.1) var bob_pitch_amplitude := 0.005
export(float, 0.1, 10.0) var bob_frequency := 1.8

export(float) var battery_max := 100.0
export(float) var battery_drain_per_second := 0.4
export(float) var battery_low_threshold := 20.0

var battery := battery_max
var _last_emitted_battery := battery_max

signal battery_changed(value, max_value)

onready var _spot_light: SpotLight = $SpotLight
onready var _volumetric_cone: MeshInstance = $VolumetricCone
onready var _emitter: MeshInstance = $Emitter
onready var _fill_light: OmniLight = $FillLight

var _material: ShaderMaterial = null
var _scroll_offset: float = 0.0
var _skeleton: Skeleton = null
var _mount_bone_idx: int = -1
var _visual_pivot: Spatial = null
var _aim_smoothed := Vector3.FORWARD
var _aim_initialized := false
var _aim_yaw: float = 0.0
var _aim_pitch: float = 0.0
var _aim_yaw_vel: float = 0.0
var _aim_pitch_vel: float = 0.0
var _prev_camera_yaw: float = 0.0
var _turn_lead_offset: float = 0.0
var _turn_lead_vel: float = 0.0
var _walk_pitch_offset: float = 0.0
var _walk_pitch_vel: float = 0.0
var _prev_vel_y: float = 0.0
var _was_grounded: bool = true
var _landing_dip: float = 0.0
var _bob_phase: float = 0.0

# Encender no debe mostrar la linterna en el origen del rig mientras el esqueleto/camara
# todavia no permiten montarla en el hombro: queda invisible hasta que _physics_process lo
# logre (o se agoten los intentos, para no dejarla invisible para siempre).
var _mount_pending_visible := false
var _mount_attempts := 0
const MOUNT_MAX_ATTEMPTS := 30
# Precalentamiento del shader (ver _start_flashlight_preheat): un Timer y el quad
# temporal colgado de la camara.
const FLASHLIGHT_PREHEAT_SECONDS := 0.3
var _preheat_timer: Timer = null
var _preheat_quad: MeshInstance = null


func _ready() -> void:
	if mask_texture == null and ResourceLoader.exists("res://core_v2/props/lights/HelmetFlashlightMask.png"):
		mask_texture = load("res://core_v2/props/lights/HelmetFlashlightMask.png")
	if _volumetric_cone and _volumetric_cone.get_surface_material(0):
		_material = _volumetric_cone.get_surface_material(0).duplicate()
		_volumetric_cone.set_surface_material(0, _material)

	var owner_node := get_parent()
	if owner_node:
		var skel = owner_node.get_node_or_null(skeleton_path)
		if skel is Skeleton:
			_skeleton = skel
			_mount_bone_idx = skel.find_bone(mount_bone)
		_visual_pivot = owner_node.get_node_or_null(visual_pivot_path) as Spatial

	_apply_light_params()
	_update_cone_transform()
	set_enabled(enabled)
	# La linterna nace apagada y la escena nunca compila su variante con spot ni el
	# material del cono hasta el primer "L". En WebGL eso es un freeze medido de ~3.4 s
	# (compilacion sincronica del primer draw). Se precalienta detras de la pantalla de
	# carga: solo durante una transicion de escena, que es cuando el nivel se monta con
	# esa pantalla arriba. En otros contextos (instanciar la escena suelta, tests) no se
	# toca la visibilidad, que es parte del contrato de la linterna.
	if not enabled and _can_preheat_flashlight():
		_start_flashlight_preheat()


# Solo precalienta si SceneManager esta en medio de una transicion: ahi el nivel se esta
# montando detras de la pantalla de carga. Fuera de eso no hay pantalla que tape el
# encendido temporal ni hace falta el warmup.
func _can_preheat_flashlight() -> bool:
	var sm = get_node_or_null("/root/SceneManager")
	return sm != null and sm.has_method("is_transitioning") and sm.is_transitioning()


# Enciende la linterna unos 0.3 s (con la pantalla de carga arriba) para forzar la
# compilacion de la variante de escena con spot, y dibuja el material del cono sobre un
# quad pegado a la camara para forzar la del shader del cono. Un Timer, no una
# corrutina: si la escena se libera en el medio no queda una funcion reanudando sobre un
# nodo muerto (los tests instancian y liberan la escena en el acto).
func _start_flashlight_preheat() -> void:
	if _preheat_timer != null:
		return
	set_enabled(true)
	# El precalentamiento necesita la variante visible dibujandose: saltea la espera de montaje.
	_mount_pending_visible = false
	_apply_light_visibility()
	call_deferred("_add_flashlight_preheat_quad")
	_preheat_timer = Timer.new()
	_preheat_timer.one_shot = true
	_preheat_timer.wait_time = FLASHLIGHT_PREHEAT_SECONDS
	_preheat_timer.connect("timeout", self, "_finish_flashlight_preheat")
	add_child(_preheat_timer)
	_preheat_timer.start()


func _add_flashlight_preheat_quad() -> void:
	if not is_inside_tree() or _volumetric_cone == null or _preheat_quad != null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera() if vp != null else null
	if cam == null:
		return
	var src = _volumetric_cone.get_surface_material(0)
	if src == null:
		return
	_preheat_quad = MeshInstance.new()
	_preheat_quad.mesh = QuadMesh.new()
	_preheat_quad.material_override = src
	cam.add_child(_preheat_quad)
	_preheat_quad.translation = Vector3(0.0, 0.0, -0.5)


func _finish_flashlight_preheat() -> void:
	if _preheat_quad != null and is_instance_valid(_preheat_quad):
		_preheat_quad.queue_free()
	_preheat_quad = null
	if _preheat_timer != null:
		_preheat_timer.queue_free()
	_preheat_timer = null
	set_enabled(false)


func _exit_tree() -> void:
	# El quad vive colgado de la camara, no de este nodo: si la escena se libera antes
	# del timeout, se lo lleva el _exit_tree.
	if _preheat_quad != null and is_instance_valid(_preheat_quad):
		_preheat_quad.queue_free()
	_preheat_quad = null


func get_battery() -> float:
	return battery


func get_battery_max() -> float:
	return battery_max


func is_battery_low() -> bool:
	return battery <= battery_low_threshold


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flashlight"):
		toggle()
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled:
		return

	if scan_mode:
		_scroll_offset += delta * scan_speed
		if _material:
			_material.set_shader_param("mask_scroll", _scroll_offset)

	if enabled and battery > 0.0:
		var prev_battery := battery
		battery = max(0.0, battery - battery_drain_per_second * delta)
		if battery <= 0.0:
			battery = 0.0
			_last_emitted_battery = 0.0
			emit_signal("battery_changed", battery, battery_max)
			set_enabled(false)
		elif abs(battery - _last_emitted_battery) >= 1.0 or (prev_battery > battery_low_threshold and battery <= battery_low_threshold):
			_last_emitted_battery = battery
			emit_signal("battery_changed", battery, battery_max)


# En _physics_process, no en _process: la camara y el esqueleto se actualizan en el paso
# de fisica, y con dt fijo el suavizado da el mismo resultado a cualquier frame rate.
func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if _mount_pending_visible:
		_mount_attempts += 1
		if _update_mount(delta) or not _can_mount() or _mount_attempts >= MOUNT_MAX_ATTEMPTS:
			_mount_pending_visible = false
			_apply_light_visibility()
		return
	_update_mount(delta)


func _update_mount(delta: float) -> bool:
	if _skeleton == null or _mount_bone_idx < 0:
		return false
	var vp := get_viewport()
	var camera := vp.get_camera() if vp != null else null
	if camera == null:
		return false

	# El modelo mira hacia +Z del pivot (misma convencion que _get_multi_tool_forward).
	var body_forward: Vector3 = -global_transform.basis.z.normalized()
	var body_basis := Basis()
	if _visual_pivot and is_instance_valid(_visual_pivot):
		body_basis = _visual_pivot.global_transform.basis
		body_forward = body_basis.z.normalized()

	var origin: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_mount_bone_idx)).origin
	origin += body_basis.orthonormalized().xform(mount_offset)

	var camera_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var target: Vector3 = _resolve_aim(camera_forward, body_forward)

	# Suavizar en mundo: si el cuerpo gira hacia la direccion de marcha pero la camara
	# no cambia, el haz tampoco debe ser arrastrado por ese giro.
	var target_yaw: float = atan2(target.x, target.z)
	var target_pitch: float = asin(clamp(target.y, -1.0, 1.0))

	if not _aim_initialized:
		_aim_yaw = target_yaw
		_aim_pitch = target_pitch
		_aim_yaw_vel = 0.0
		_aim_pitch_vel = 0.0
		_prev_camera_yaw = atan2(camera_forward.x, camera_forward.z)
		_turn_lead_offset = 0.0
		_turn_lead_vel = 0.0
		_walk_pitch_offset = 0.0
		_walk_pitch_vel = 0.0
		_prev_vel_y = 0.0
		_was_grounded = true
		_landing_dip = 0.0
		_bob_phase = 0.0
		_aim_initialized = true
	elif delta > 0.0:
		var dt: float = delta

		var yaw_goal: float = _aim_yaw + wrapf(target_yaw - _aim_yaw, -PI, PI)
		var yaw_step: Vector2 = SpringMath.critical_spring_step(_aim_yaw, _aim_yaw_vel, yaw_goal, aim_half_life, dt)
		_aim_yaw = wrapf(yaw_step.x, -PI, PI)
		_aim_yaw_vel = yaw_step.y

		var pitch_step: Vector2 = SpringMath.critical_spring_step(_aim_pitch, _aim_pitch_vel, target_pitch, aim_half_life, dt)
		_aim_pitch = pitch_step.x
		_aim_pitch_vel = pitch_step.y

	# Retrieve body velocity and grounded state from owner/parent node
	var owner_node := get_parent()
	var vel := Vector3.ZERO
	var grounded := true
	if owner_node != null:
		if "velocity" in owner_node:
			vel = owner_node.velocity
		if owner_node.has_method("is_effectively_grounded"):
			grounded = owner_node.is_effectively_grounded()
		elif owner_node.has_method("is_on_floor"):
			grounded = owner_node.is_on_floor()

	# Pitch jump / airborne & landing dip
	var sway_pitch: float = 0.0
	if not grounded:
		sway_pitch += vel.y * sway_jump_gain
		_was_grounded = false
	else:
		if not _was_grounded:
			_landing_dip = clamp(-_prev_vel_y * sway_landing_gain, 0.0, 0.25)
			_was_grounded = true
		if delta > 0.0:
			_landing_dip = lerp(_landing_dip, 0.0, min(1.0, 10.0 * delta))
		sway_pitch -= _landing_dip
	_prev_vel_y = vel.y

	# Grounded movement: al arrancar baja suavemente el haz. La direccion de marcha no
	# interviene en yaw, para que mirar y caminar hacia lados distintos no produzca yank.
	var h_speed: float = Vector2(vel.x, vel.z).length()
	var walking: bool = grounded and h_speed > 0.1
	if delta > 0.0:
		var dt: float = delta
		var camera_yaw: float = atan2(camera_forward.x, camera_forward.z)
		var camera_yaw_rate: float = wrapf(camera_yaw - _prev_camera_yaw, -PI, PI) / dt
		_prev_camera_yaw = camera_yaw
		var base_dir := Vector3(sin(_aim_yaw) * cos(_aim_pitch), sin(_aim_pitch), cos(_aim_yaw) * cos(_aim_pitch)).normalized()
		var used_angle: float = acos(clamp(base_dir.dot(body_forward), -1.0, 1.0))
		var lead_limit: float = min(deg2rad(max_turn_lead_deg), max(0.0, deg2rad(aim_limit_deg) - used_angle))
		var lead_goal: float = _turn_lead_goal(camera_yaw_rate, walking, lead_limit)
		var lead_step: Vector2 = SpringMath.critical_spring_step(_turn_lead_offset, _turn_lead_vel, lead_goal, turn_lead_half_life, dt)
		_turn_lead_offset = lead_step.x
		_turn_lead_vel = lead_step.y
		var walk_goal: float = -deg2rad(walk_lower_deg) if walking else 0.0
		var walk_step: Vector2 = SpringMath.critical_spring_step(_walk_pitch_offset, _walk_pitch_vel, walk_goal, walk_lower_half_life, dt)
		_walk_pitch_offset = walk_step.x
		_walk_pitch_vel = walk_step.y
	if walking and delta > 0.0:
		_bob_phase += h_speed * bob_frequency * delta
		sway_pitch += sin(_bob_phase * 2.0) * bob_pitch_amplitude

	var final_yaw: float = _aim_yaw + _turn_lead_offset
	var final_pitch: float = _aim_pitch + _walk_pitch_offset + sway_pitch

	var final_dir := Vector3(sin(final_yaw) * cos(final_pitch), sin(final_pitch), cos(final_yaw) * cos(final_pitch)).normalized()

	# Clamp against body_forward with aim_limit_deg limit
	_aim_smoothed = _resolve_aim(final_dir, body_forward)

	var xf := Transform(global_transform.basis, origin)
	global_transform = xf.looking_at(origin + _aim_smoothed, Vector3.UP)
	return true


func _turn_lead_goal(camera_yaw_rate: float, walking: bool, limit: float = -1.0) -> float:
	if limit < 0.0:
		limit = deg2rad(max_turn_lead_deg)
	if abs(camera_yaw_rate) < 0.01:
		return 0.0 if walking else clamp(_turn_lead_offset, -limit, limit)
	return SpringMath.predictive_lead(camera_yaw_rate, aim_half_life, turn_lead_seconds, limit)


# Direccion objetivo de la linterna: dentro del limite sigue a la camara y pasado el
# limite permanece en el borde. No volver al frente a 90 grados: ese salto era visible
# cuando el adelanto y la mirada alcanzaban juntos ese angulo.
func _resolve_aim(dir: Vector3, axis: Vector3) -> Vector3:
	var max_angle: float = deg2rad(aim_limit_deg)
	var angle: float = acos(clamp(dir.dot(axis), -1.0, 1.0))
	if angle <= max_angle:
		return dir
	var rot_axis: Vector3 = axis.cross(dir)
	if rot_axis.length_squared() < 0.000001:
		rot_axis = axis.cross(_aim_smoothed)
		if rot_axis.length_squared() < 0.000001:
			return axis # sin direccion previa no hay lado estable que preservar
	return axis.rotated(rot_axis.normalized(), max_angle).normalized()


func get_aim_direction() -> Vector3:
	return _aim_smoothed


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(val: bool) -> void:
	if val and battery <= 0.0:
		val = false
	enabled = val
	if not is_inside_tree():
		return
	if not enabled:
		_mount_pending_visible = false
		_mount_attempts = 0
		_apply_light_visibility()
		set_process(false)
		set_physics_process(false)
		return
	# Encender no debe teletransportar la linterna del origen del rig al hombro: se monta
	# ANTES de hacerse visible. Si el esqueleto/camara todavia no estan listos (perfil low
	# end al arrancar), queda invisible hasta que _physics_process logre montarla.
	_aim_initialized = false
	_aim_yaw_vel = 0.0
	_aim_pitch_vel = 0.0
	_prev_camera_yaw = 0.0
	_turn_lead_offset = 0.0
	_turn_lead_vel = 0.0
	_walk_pitch_offset = 0.0
	_walk_pitch_vel = 0.0
	_prev_vel_y = 0.0
	_was_grounded = true
	_landing_dip = 0.0
	_bob_phase = 0.0
	_mount_attempts = 0
	if not _can_mount():
		# Sin hueso de montura no hay a donde ir: se muestra igual (comportamiento previo).
		_mount_pending_visible = false
		_apply_light_visibility()
	elif _update_mount(0.0):
		_mount_pending_visible = false
		_apply_light_visibility()
	else:
		_mount_pending_visible = true
		_hide_light_visibility()
	set_process(true)
	set_physics_process(true)

func _can_mount() -> bool:
	return _skeleton != null and _mount_bone_idx >= 0

func _apply_light_visibility() -> void:
	if _spot_light:
		_spot_light.visible = enabled
	if _volumetric_cone:
		_volumetric_cone.visible = enabled
	if _emitter:
		_emitter.visible = enabled
	if _fill_light:
		_fill_light.visible = enabled and fill_energy > 0.0 and not _mount_pending_visible

func _hide_light_visibility() -> void:
	if _spot_light:
		_spot_light.visible = false
	if _volumetric_cone:
		_volumetric_cone.visible = false
	if _emitter:
		_emitter.visible = false
	if _fill_light:
		_fill_light.visible = false


func set_spot_range(val: float) -> void:
	# Enforce MobileLightBudget contract: spot_range must stay < 6.0m
	spot_range = clamp(val, 0.5, 5.9)
	if is_inside_tree():
		_apply_light_params()
		_update_cone_transform()


func set_spot_angle(val: float) -> void:
	spot_angle = clamp(val, 10.0, 90.0)
	if is_inside_tree():
		_apply_light_params()
		_update_cone_transform()


func set_light_color(val: Color) -> void:
	light_color = val
	if is_inside_tree():
		_apply_light_params()


func set_light_energy(val: float) -> void:
	light_energy = val
	if is_inside_tree():
		_apply_light_params()


func set_scan_mode(val: bool) -> void:
	scan_mode = val
	if is_inside_tree() and _material:
		_material.set_shader_param("use_mask", scan_mode)


func set_shadow_enabled(val: bool) -> void:
	shadow_enabled = val
	if is_inside_tree() and _spot_light:
		_spot_light.shadow_enabled = shadow_enabled


func set_fill_energy(val: float) -> void:
	fill_energy = max(val, 0.0)
	if is_inside_tree():
		_apply_light_params()


func set_fill_range(val: float) -> void:
	# Por debajo de min_range_to_touch (6.0) para que MobileLightBudget no la recorte.
	fill_range = clamp(val, 0.2, 4.0)
	if is_inside_tree():
		_apply_light_params()


func _apply_light_params() -> void:
	if _fill_light:
		_fill_light.light_energy = fill_energy
		_fill_light.omni_range = fill_range
		_fill_light.light_color = light_color
		_fill_light.visible = enabled and fill_energy > 0.0

	if _spot_light:
		_spot_light.translation = Vector3(0.0, 0.0, -muzzle_offset)
		_spot_light.spot_range = spot_range
		_spot_light.spot_angle = spot_angle
		_spot_light.light_color = light_color
		_spot_light.light_energy = light_energy
		_spot_light.shadow_enabled = shadow_enabled

	if _material:
		_material.set_shader_param("color", light_color)
		_material.set_shader_param("use_mask", scan_mode)
		_material.set_shader_param("mask_scroll", _scroll_offset)
		if mask_texture:
			_material.set_shader_param("mask", mask_texture)
		_material.set_shader_param("mask_tiling", mask_tiling)


func _update_cone_transform() -> void:
	if not _volumetric_cone:
		return

	# El apice arranca en el EMISOR, no en la SpotLight. La luz esta adelantada
	# muzzle_offset para que el cuerpo no entre en su frustum de sombra, pero si el mesh
	# tambien arranca ahi el haz se despega de la lampara y no parece salir de ella.
	# El cono es entonces un poco mas largo que spot_range y su semi-angulo apenas menor,
	# pero cierra exactamente contra el disco iluminado en el extremo.
	# SpotLight.spot_angle en Godot es el SEMI-angulo (del eje al borde, tope 90), no la
	# apertura total: con spot_angle * 0.5 el mesh salia casi la mitad de ancho.
	var far_radius: float = tan(deg2rad(spot_angle)) * spot_range
	var length: float = muzzle_offset + spot_range
	# CylinderMesh mide 1.0 en Y (su eje) antes de la rotacion de X.
	_volumetric_cone.scale = Vector3(far_radius, length, far_radius)
	# +90 deja el ápice (top_radius = 0) en la lampara y la base ancha lejos.
	_volumetric_cone.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_volumetric_cone.translation = Vector3(0.0, 0.0, -length * 0.5)
