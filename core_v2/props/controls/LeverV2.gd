extends InteractableBaseV2
class_name LeverV2

# LeverV2.gd - Vertical lever prop
# Emits lever_toggled(is_on) and supports resistance.

# --- EXPORTS ---
export(bool) var lever_on := false setget set_lever_on
export(float) var lever_speed := 2.0
export(float) var resistance := 0.0 # Future use for holding interaction
export(NodePath) var handle_path := NodePath("Handle")
export(Vector3) var hinge_origin := Vector3.ZERO
export(Vector3) var hinge_axis := Vector3(1, 0, 0)
export(float) var angle_off_deg := 40.0
export(float) var angle_on_deg := -40.0

# --- FEEDBACK DIEGÉTICO ---
# El prop comunica su estado por luz/emisión propia, no solo por el texto del HUD:
#   - idle (off): ámbar tenue
#   - armado (en rango/enfoque): ámbar más brillante (bisel/perilla también)
#   - activando: rampa a cian según anim_progress
#   - recién activado: pulso breve de emisión (contado en ticks de física)
# Todo es función de anim_progress + un contador de ticks determinista: sin Tween,
# sin randf y sin reloj de pared, así el replay es idéntico.
const PULSE_TICKS := 20
export(Color) var color_idle := Color(1.0, 0.35, 0.05)
export(Color) var color_armed := Color(1.0, 0.72, 0.22)
export(Color) var color_active := Color(0.05, 0.95, 0.78)
export(float) var pulse_energy_boost := 1.1
export(float) var armed_energy_boost := 0.3

# --- SIGNALS ---
signal lever_toggled(is_on)

var _handle: Spatial = null
var _rest: Transform
var _pivot: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3(1, 0, 0)
var _use_hinge_pivot := false
var _pulse_ticks := 0
var _arm_visual := false
var _owns_knob_material := false

func set_lever_on(v: bool) -> void:
	lever_on = v
	set_active(v)

func _ready():
	_handle = get_node_or_null(handle_path) as Spatial
	if _handle == null:
		_handle = get_node_or_null("Handle") as Spatial
	if _handle != null:
		_rest = _handle.transform
		if hinge_origin.length_squared() > 0.00001:
			_use_hinge_pivot = true
			var to_parent: Transform = _handle.get_parent().global_transform.affine_inverse() * global_transform
			_pivot = to_parent.xform(hinge_origin)
			_axis = to_parent.basis.xform(hinge_axis).normalized()
			if _axis.length_squared() < 0.0001:
				_axis = Vector3(1, 0, 0)
	# Sync initial state
	if lever_on != is_active:
		set_active(lever_on, true)

	anim_duration = 1.0 / lever_speed if lever_speed > 0 else 1.0
	_update_visuals()

func _own_knob_material():
	var knob := get_node_or_null("Handle/Knob") as MeshInstance
	if knob == null:
		return null
	if not _owns_knob_material:
		# Mismo criterio que el bisel del botón: material espacial propio, ya que el
		# dither manager puede haber dejado un ShaderMaterial en material_override.
		var mat := SpatialMaterial.new()
		mat.resource_local_to_scene = true
		var base_mat = knob.get_active_material(0) if knob.mesh != null else null
		if base_mat is SpatialMaterial:
			mat.albedo_color = (base_mat as SpatialMaterial).albedo_color
		knob.material_override = mat
		_owns_knob_material = true
	return knob.material_override

func set_proximity_highlight(enabled: bool, color: Color = Color(0.0, 1.0, 1.0, 0.1)) -> void:
	.set_proximity_highlight(enabled, color)
	if _arm_visual != enabled:
		_arm_visual = enabled
		_update_visuals()

func set_highlighted(enabled: bool, color: Color = Color.cyan) -> void:
	.set_highlighted(enabled, color)
	if _arm_visual != enabled:
		_arm_visual = enabled
		_update_visuals()

func _update_visuals() -> void:
	var handle = _handle if _handle != null else get_node_or_null("Handle")
	if handle:
		var deg: float = lerp(angle_off_deg, angle_on_deg, anim_progress)
		if _use_hinge_pivot:
			var basis := Basis(_axis, deg2rad(deg))
			handle.transform = Transform(basis, _pivot - basis.xform(_pivot)) * _rest
		else:
			handle.rotation_degrees = Vector3(deg, 0, 0)
	var status_light := get_node_or_null("StatusLight") as MeshInstance
	if status_light and status_light.material_override is SpatialMaterial:
		var mat := status_light.material_override as SpatialMaterial
		var base_col := color_armed if (_arm_visual and not is_active) else color_idle
		var col := base_col.linear_interpolate(color_active, anim_progress)
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		var energy := 1.2 + anim_progress * 1.0
		if _pulse_ticks > 0:
			energy += pulse_energy_boost * float(_pulse_ticks) / float(PULSE_TICKS)
		elif _arm_visual and not is_active:
			energy += armed_energy_boost
		mat.emission_energy = energy
	var knob_mat = _own_knob_material()
	if knob_mat is SpatialMaterial:
		var km := knob_mat as SpatialMaterial
		var knob_emissive := _pulse_ticks > 0 or anim_progress > 0.0 or (_arm_visual and not is_active)
		km.emission_enabled = knob_emissive
		km.emission = color_active if anim_progress > 0.5 else (color_armed if _arm_visual else color_idle)
		km.emission_energy = 0.4 + (1.2 if _pulse_ticks > 0 else 0.0)

func set_active(value: bool, immediate: bool = false) -> void:
	.set_active(value, immediate)
	if value and immediate:
		_pulse_ticks = PULSE_TICKS
		set_physics_process(_pulse_ticks > 0)

func _on_animation_completed() -> void:
	._on_animation_completed()
	if is_active:
		_pulse_ticks = PULSE_TICKS
	lever_on = is_active
	emit_signal("lever_toggled", is_active)
	_update_visuals()

func _wants_continuous_step() -> bool:
	return _pulse_ticks > 0

func step(dt: float) -> void:
	.step(dt)
	if _pulse_ticks > 0:
		_pulse_ticks -= 1
		if _pulse_ticks <= 0:
			_pulse_ticks = 0
			_update_visuals()

func get_snapshot() -> Dictionary:
	var snap := .get_snapshot()
	snap["pulse_ticks"] = _pulse_ticks
	return snap

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_pulse_ticks = int(data.get("pulse_ticks", 0))
	_arm_visual = false
	set_physics_process(_pulse_ticks > 0)
	_update_visuals()

func interact() -> void:
	.interact()
	# Sound or other feedback could go here
