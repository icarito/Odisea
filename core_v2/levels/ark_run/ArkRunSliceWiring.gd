extends Node

# FD-324 F7 — cableado F5/F6 + HUD + autonavegador del Ark-Run.
# Construye los módulos una vez y delega el loop jugable en ArkRunLiveLoop
# (<200). Helper <200 para dejar ArkRunSlice.gd corto.

const IgnitionScript = preload("res://core_v2/levels/ark_run/ArkRunEngineIgnition.gd")
const ConversionScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceConversion.gd")
const RaceScript = preload("res://core_v2/levels/ark_run/ArkRunRaceController.gd")
const CylinderScript = preload("res://core_v2/camera/ArkRunCylindricalCamera.gd")
const ShadowScript = preload("res://core_v2/levels/ark_run/ArkRunGravityShadow.gd")
const LodScript = preload("res://core_v2/levels/ark_run/ArkRunLodTronPass.gd")
const HudScript = preload("res://core_v2/levels/ark_run/ArkRunHudOverlay.gd")
const AutopilotScript = preload("res://core_v2/input/AutopilotInputV2.gd")
const LoopScript = preload("res://core_v2/levels/ark_run/ArkRunLiveLoop.gd")
const ScenarioScript = preload("res://core_v2/levels/ark_run/ArkRunVerticalSliceScenario.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const AnchorVisualsScript = preload("res://core_v2/levels/ark_run/ArkRunAnchorVisuals.gd")
const RouteGuidesScript = preload("res://core_v2/levels/ark_run/ArkRunRouteGuides.gd")
const FeedbackScript = preload("res://core_v2/levels/ark_run/ArkRunControlsFeedback.gd")
const SLICE_SEED := 32401
const PROXY_PLATES := 4

var slice = null
var ignition = null
var conversion = null
var race = null
var cylindrical = null
var shadow = null
var lod = null
var hud = null
var autopilot = null
var loop = null
var feedback = null
var anchors: Array = []
var _determinism_state: Dictionary = {}

func setup(owner_slice) -> void:
	slice = owner_slice
	process_priority = 110
	_build_f5()
	_build_f6()
	_build_loop()
	loop = LoopScript.new()
	loop.name = "ArkRunLiveLoop"
	add_child(loop)
	feedback = FeedbackScript.new()
	feedback.setup(loop, self)
	loop.setup(self)

func _build_f5() -> void:
	var root: Node = slice.get_node("EngineIgnitionRoot")
	ignition = slice._attach(root, "ArkRunEngineIgnition", IgnitionScript)
	ignition.seed_value = SLICE_SEED
	ignition.set_industry_streamer(slice.industry_streamer)
	for spoke in slice.spokes:
		ignition.add_elevator(spoke.get_elevator())
	ignition.set_physics_process(false)
	conversion = slice._attach(root, "ArkRunTerraceConversion", ConversionScript)
	conversion.omega = slice.spin_omega
	conversion.set_ignition(ignition)
	ignition.connect("ignition_triggered", self, "_on_ignition_triggered")
	conversion.add_spiral_plates(slice, slice.pilot.global_transform.origin, PROXY_PLATES)
	conversion.set_physics_process(false)

func _on_ignition_triggered(_time_since_arm) -> void:
	conversion.start_conversion()
	if race != null and not race.running:
		race.start_run()

func _build_f6() -> void:
	var hud_root: Node = slice.get_node("RaceHudRoot")
	race = slice._attach(hud_root, "ArkRunRaceController", RaceScript)
	race.engine_z_max = slice.get_engine_z_max()
	cylindrical = slice._attach(hud_root, "ArkRunCylindricalCamera", CylinderScript)
	if slice.spin_camera != null:
		slice.spin_camera.camera_basis_prefix = Basis.IDENTITY
		slice.spin_camera.enable_25d_override = false
	shadow = slice._attach(slice.get_node("TraversalRoot"), "ArkRunGravityShadow", ShadowScript)
	lod = slice._attach(slice.get_node("TraversalRoot"), "ArkRunLodTronPass", LodScript)
	lod.build_static()
	var world_env = slice.get_node_or_null("WorldEnvironment")
	if world_env != null and lod.get_environment() != null:
		world_env.environment = lod.get_environment()
	var points := []
	for waypoint in slice.get_canonical_route().get_waypoints():
		points.append(waypoint["position"] as Vector3)
	lod.add_emissive_polyline(points, LodScript.TRON_COLOR)
	RouteGuidesScript.new().build(lod, slice.get_canonical_route().get_waypoints(),
		slice.get_bridge_target(), slice.get_engine_target())
	hud = HudScript.new()
	hud.name = "ArkRunHudOverlay"
	hud_root.add_child(hud)

func _build_loop() -> void:
	if slice.rope_input != null:
		slice.rope_input.set_physics_process(false)
		anchors = collect_rope_anchors()
		slice.rope_input.set_anchors(anchors)
		AnchorVisualsScript.new().build(slice.get_node_or_null("TraversalRoot"), anchors)
	if slice.thruster_input != null:
		slice.thruster_input.keyboard_thruster_scancode = KEY_SHIFT
	var route = slice.get_canonical_route()
	if route != null:
		autopilot = AutopilotScript.new()
		autopilot.setup(slice.pilot)
		autopilot.set_route(route.get_waypoints())
		if slice.pilot.has_method("ensure_input_provider"):
			slice.pilot.ensure_input_provider()
		if slice.pilot.input_provider != null:
			slice.pilot.input_provider.autopilot = autopilot

# El loop real corre en ArkRunLiveLoop._physics_process.
func _physics_process(delta: float) -> void:
	if slice == null or not is_instance_valid(slice) or not slice.is_physics_processing():
		return
	if loop != null:
		loop.advance_play_loop(delta)

func present(dt: float) -> void:
	if loop != null:
		loop.present(dt)

func advance_play_loop(dt: float) -> void:
	if loop != null:
		loop.advance_play_loop(dt)

# FD-325 determinismo: la escena de replay corre pasos de física explícitos con pilot.step y
# sin loop vivo; el aim de cuerda debe quedar sin override para no alterar el hash exportado.
func is_live_loop_running() -> bool:
	return loop != null and is_instance_valid(loop) and loop.is_physics_processing()

func restart_run() -> void:
	if loop != null:
		loop.restart_run()

# Anclajes en todo el cilindro: un anclaje por domo (600) + DomeRegistry.
func collect_rope_anchors() -> Array:
	var anchors: Array = []
	if slice.terrace_props != null:
		for entry in slice.terrace_props.get_dome_entries():
			var xform: Transform = entry["transform"]
			var height: float = float(entry["variant"]["height"])
			anchors.append(xform.origin + xform.basis.y.normalized() * (height + 6.0))
	_add_terrace_pylons(anchors)
	_add_spoke_rings(anchors)
	var registry = slice.get_node_or_null("/root/DomeRegistry")
	if slice.spiral_field == null or registry == null:
		return anchors
	var plate_count: int = SpiralGeometry.plate_count_for(slice.get_spiral_config())
	for dome_id in registry.get_all_dome_ids():
		var info: Dictionary = registry.get_dome(String(dome_id))
		var plate_index: int = int(info.get("plate_index", 0))
		if int(info.get("spiral_index", 0)) != 0 or plate_index < 0 or plate_index >= plate_count:
			continue
		anchors.append_array(slice.spiral_field.get_plate_world_anchors(
			0, plate_index, registry.get_anchors(String(dome_id))))
	return anchors

# Pilones elevados en las terrazas abiertas (placas impares): altura de balanceo.
func _add_terrace_pylons(anchors: Array) -> void:
	if slice.spiral_field == null:
		return
	var configs: Array = slice.spiral_field.get_spiral_configs()
	for spiral_index in range(configs.size()):
		var config: Dictionary = configs[spiral_index]
		for plate_index in range(SpiralGeometry.plate_count_for(config)):
			if (plate_index + spiral_index) % 2 == 0:
				continue
			var xform: Transform = SpiralGeometry.plate_transform(config, plate_index)
			var up: Vector3 = xform.basis.y.normalized()
			var tangent: Vector3 = xform.basis.x.normalized()
			anchors.append(xform.origin + tangent * 55.0 + up * 24.0)
			anchors.append(xform.origin - tangent * 55.0 + up * 24.0)

# Anillos de anclaje a lo largo de cada spoke radial.
func _add_spoke_rings(anchors: Array) -> void:
	for spoke in slice.spokes:
		var hub: Vector3 = spoke.get_hub_origin()
		var plate: Vector3 = spoke.get_plate_origin()
		for factor in [0.3, 0.5, 0.7]:
			anchors.append(hub.linear_interpolate(plate, float(factor)))

func run_determinism_scenario() -> Dictionary:
	_determinism_state = ScenarioScript.new().run(slice, self)
	return _determinism_state
