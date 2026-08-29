extends Spatial

export(bool) var enabled := true setget set_enabled
export(float, 0.5, 5.9) var spot_range := 5.9 setget set_spot_range
# Cono angosto a proposito: con la lampara a ~20cm del cuerpo, un cono ancho mete el
# torso y la cabeza de Elias dentro del haz y proyecta astillas de poligonos al suelo.
# Godot 3 no permite excluir un mesh de las sombras de UNA luz (light_cull_mask solo
# excluye la iluminacion, no el casteo de sombra), asi que se resuelve con geometria.
export(float, 10.0, 90.0) var spot_angle := 32.0 setget set_spot_angle
export(Color) var light_color := Color(0.85, 0.95, 1.0, 1.0) setget set_light_color
export(float, 0.0, 16.0) var light_energy := 7.0 setget set_light_energy
export(bool) var scan_mode := false setget set_scan_mode
export(float, 0.1, 10.0) var scan_speed := 2.0
export(bool) var shadow_enabled := false setget set_shadow_enabled
# Relleno corto alrededor de la lampara: Elias queda detras de la SpotLight, asi que sin
# esto es una silueta negra. 0.0 lo apaga (una luz dinamica menos en movil).
export(float, 0.0, 4.0) var fill_energy := 0.6 setget set_fill_energy
export(float, 0.2, 4.0) var fill_range := 1.4 setget set_fill_range
export(Texture) var mask_texture: Texture = preload("res://core_v2/props/lights/HelmetFlashlightMask.png")
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


func _ready() -> void:
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


# En _physics_process, no en _process: la camara y el esqueleto se actualizan en el paso
# de fisica, y con dt fijo el suavizado da el mismo resultado a cualquier frame rate.
func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_update_mount(delta)


func _update_mount(delta: float) -> void:
	if _skeleton == null or _mount_bone_idx < 0:
		return
	var camera := get_viewport().get_camera()
	if camera == null:
		return

	# El modelo mira hacia +Z del pivot (misma convencion que _get_multi_tool_forward).
	var body_forward: Vector3 = -global_transform.basis.z.normalized()
	var body_basis := Basis()
	if _visual_pivot and is_instance_valid(_visual_pivot):
		body_basis = _visual_pivot.global_transform.basis
		body_forward = body_basis.z.normalized()

	var origin: Vector3 = (_skeleton.global_transform * _skeleton.get_bone_global_pose(_mount_bone_idx)).origin
	origin += body_basis.orthonormalized().xform(mount_offset)

	var target: Vector3 = _resolve_aim(-camera.global_transform.basis.z.normalized(), body_forward)
	if not _aim_initialized:
		_aim_smoothed = target
		_aim_initialized = true
	else:
		# 1 - exp(-k*dt) en vez de k*dt: mismo resultado con cualquier dt, y frena al
		# acercarse al objetivo (easing) en vez de cortar de golpe contra el limite.
		var t: float = 1.0 - exp(-aim_lerp_speed * delta)
		_aim_smoothed = _aim_smoothed.linear_interpolate(target, t).normalized()

	var xf := Transform(global_transform.basis, origin)
	global_transform = xf.looking_at(origin + _aim_smoothed, Vector3.UP)


# Direccion objetivo de la linterna, con la misma forma que el head-look del animator:
# dentro del limite sigue a la camara; pasado el limite queda en el borde del cono; y si
# la camara se va por detras, vuelve al frente. Sin ese ultimo tramo la linterna se tira
# de un hombro al otro al cruzar por atras (el borde del cono cambia de lado).
func _resolve_aim(dir: Vector3, axis: Vector3) -> Vector3:
	var max_angle: float = deg2rad(aim_limit_deg)
	var angle: float = acos(clamp(dir.dot(axis), -1.0, 1.0))
	if angle <= max_angle:
		return dir
	if angle >= PI * 0.5:
		return axis
	var rot_axis: Vector3 = axis.cross(dir)
	if rot_axis.length_squared() < 0.000001:
		return axis # camara exactamente en linea con el cuerpo: no hay eje de giro
	return axis.rotated(rot_axis.normalized(), max_angle).normalized()


func toggle() -> void:
	set_enabled(not enabled)


func set_enabled(val: bool) -> void:
	enabled = val
	if is_inside_tree():
		if _spot_light:
			_spot_light.visible = enabled
		if _volumetric_cone:
			_volumetric_cone.visible = enabled
		if _emitter:
			_emitter.visible = enabled
		if _fill_light:
			_fill_light.visible = enabled and fill_energy > 0.0
		set_process(enabled)
		set_physics_process(enabled)


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
