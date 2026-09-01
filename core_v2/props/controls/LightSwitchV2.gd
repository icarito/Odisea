tool
extends InteractableBaseV2
class_name LightSwitchV2

# LightSwitchV2.gd - Wall-mounted sci-fi light switch prop.
# Extends InteractableBaseV2 for deterministic binary toggling.

export(Color) var active_color := Color(0.0, 0.9, 1.0)
export(Color) var inactive_color := Color(0.15, 0.15, 0.2)
export(float, 0.0, 5.0) var emission_energy_max := 2.5

var _rocker: Spatial = null
var _status_lens: MeshInstance = null
var _owns_lens_material := false

func _init() -> void:
	interaction_text = "accionar"

func _ready() -> void:
	interaction_text = "accionar"
	_find_nodes()
	._ready()

func _find_nodes() -> void:
	if not _rocker:
		_rocker = get_node_or_null("RockerPivot") as Spatial
	if not _status_lens:
		_status_lens = get_node_or_null("StatusStrip") as MeshInstance

func _update_visuals() -> void:
	._update_visuals()
	_find_nodes()

	# Rocker rotation: OFF (progress 0.0) -> -20 deg, ON (progress 1.0) -> +20 deg around X axis
	if _rocker:
		var rx: float = lerp(-20.0, 20.0, anim_progress)
		_rocker.rotation_degrees = Vector3(rx, 0.0, 0.0)

	# Status lens emission & color: OFF (energy 0) -> ON (energy max)
	if _status_lens:
		var mat = _own_lens_material()
		if mat is SpatialMaterial:
			var current_color: Color = lerp(inactive_color, active_color, anim_progress)
			mat.albedo_color = current_color
			mat.emission_enabled = true
			mat.emission = active_color
			mat.emission_energy = anim_progress * emission_energy_max

func _own_lens_material() -> SpatialMaterial:
	if _status_lens == null:
		return null
	var mat = _status_lens.material_override
	if not _owns_lens_material or mat == null:
		mat = mat.duplicate() if mat != null else SpatialMaterial.new()
		mat.resource_local_to_scene = true
		_status_lens.material_override = mat
		_owns_lens_material = true
	return mat as SpatialMaterial

func get_snapshot() -> Dictionary:
	return .get_snapshot()

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_update_visuals()
