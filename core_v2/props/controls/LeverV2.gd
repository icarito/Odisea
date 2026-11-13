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

# --- SIGNALS ---
signal lever_toggled(is_on)

var _handle: Spatial = null
var _rest: Transform
var _pivot: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3(1, 0, 0)
var _use_hinge_pivot := false

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
		var col := Color(1.0, 0.35, 0.05).linear_interpolate(Color(0.05, 0.95, 0.78), anim_progress)
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy = 1.2 + anim_progress * 1.0

func _on_animation_completed() -> void:
	._on_animation_completed()
	lever_on = is_active
	emit_signal("lever_toggled", is_active)

func interact() -> void:
	.interact()
	# Sound or other feedback could go here
