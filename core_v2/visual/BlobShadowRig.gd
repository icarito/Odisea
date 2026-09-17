extends Node

# BlobShadowRig.gd
# Shared, per-scene rig for the real BlobShadow backport (godot-box3d fork:
# BlobShadow / BlobFocus / Light.blob_shadow_*). FakeShadow asks for one on
# demand and only when the running engine exposes BlobShadow, so on stock
# Godot nothing here is ever loaded.
#
# There is one rig per scene:
#   - a single "shadow only" DirectionalLight, straight down and high above the
#     casters (the engine's directional blob AABB hangs from the light's
#     position, so it has to sit above them), with blob shadows enabled;
#   - one BlobFocus that follows the active camera, so the engine spends its
#     small caster budget on the shadows closest to the player.
#
# Each FakeShadow keeps its own BlobShadow caster; this node owns only the
# light and the focus.

const GROUP := "blob_shadow_rig"

# Light blob shadow param indices (engine: Light::BlobShadowParam).
const PARAM_RANGE_HARDNESS := 0
const PARAM_RANGE_MAX := 1
const PARAM_INTENSITY := 2

# Tuned to look close to the legacy FakeShadow defaults (opacity 0.62,
# hardness ~0.42). The rest (range/gamma) comes from the project settings.
const DEFAULT_INTENSITY := 0.62
const DEFAULT_HARDNESS := 0.42

var blob_light: DirectionalLight = null
var blob_focus: Node = null
var _pending_params := {}

func _ready() -> void:
	add_to_group(GROUP)
	_build()

func _build() -> void:
	if blob_light != null:
		return

	# Ajustes globales equivalentes a rendering/quality/blob_shadows/*. Se
	# aplican en runtime para no depender de que el proyecto traiga las claves
	# (en un engine sin el backport has_method() da false y no pasa nada).
	if VisualServer.has_method("blob_shadows_set_range"):
		VisualServer.call("blob_shadows_set_range", 3.0)
		VisualServer.call("blob_shadows_set_gamma", 1.0)
		VisualServer.call("blob_shadows_set_intensity", 1.0)

	blob_light = DirectionalLight.new()
	blob_light.name = "BlobShadowLight"
	add_child(blob_light)
	blob_light.translation = Vector3(0, 60, 0)
	blob_light.rotation_degrees = Vector3(-90, 0, 0)
	blob_light.light_energy = 1.0
	blob_light.shadow_enabled = false
	blob_light.set("blob_shadow_enabled", true)
	blob_light.set("blob_shadow_shadow_only", true)
	blob_light.call("set_blob_shadow_param", PARAM_RANGE_MAX, 0.0) # directional: infinite
	blob_light.call("set_blob_shadow_param", PARAM_RANGE_HARDNESS, DEFAULT_HARDNESS)
	blob_light.call("set_blob_shadow_param", PARAM_INTENSITY, DEFAULT_INTENSITY)
	# The rig enters the tree deferred (the level is still setting up children
	# when the first FakeShadow asks for it), so per-actor tuning can arrive
	# before the light exists.
	for param in _pending_params:
		blob_light.call("set_blob_shadow_param", param, _pending_params[param])
	_pending_params.clear()

	blob_focus = ClassDB.instance("BlobFocus")
	blob_focus.name = "BlobFocus"
	add_child(blob_focus)

func set_light_param(param: int, value: float) -> void:
	if blob_light != null:
		blob_light.call("set_blob_shadow_param", param, value)
	else:
		_pending_params[param] = value

func _process(_delta: float) -> void:
	if blob_focus == null:
		return
	var vp := get_viewport()
	var cam: Camera = vp.get_camera() if vp != null else null
	if cam != null and is_instance_valid(cam):
		blob_focus.global_transform.origin = cam.global_transform.origin
