extends Spatial

# FD-324 — vertical slice "Del hub al motor" (F0 base + F1..F4), marco SpinFrame axial sin rotadores.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const FieldResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")
const CameraControllerScript = preload("res://core_v2/camera/SpinRealCameraController.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const ExplosionScript = preload("res://core_v2/levels/ark_run/ArkRunExplosion.gd")
const HandrailsScript = preload("res://core_v2/levels/ark_run/ArkRunHubHandrails.gd")
const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const TerracePropsScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceProps.gd")
const RouteScript = preload("res://core_v2/levels/ark_run/ArkRunCanonicalRoute.gd")
const SpokeScript = preload("res://core_v2/components/SpinSpokeV2.gd")
const RopeInputScript = preload("res://core_v2/player/traversal/SpinRopeInputV2.gd")
const StreamerScript = preload("res://core_v2/levels/ark_run/ArkRunIndustryStreamer.gd")
const SuitOSHostScript = preload("res://core_v2/ui/suit_os/ArkRunSuitOSHost.gd")
const WiringScript = preload("res://core_v2/levels/ark_run/ArkRunSliceWiring.gd")

const SLICE_SEED := 32401; const SLICE_LENGTH := 2000.0; const R_HULL := 340.0; const R_HUB := 8.0
const BRIDGE_PLATE_INDICES := [47, 48, 49]; const ENGINE_Z_MAX := -940.0; const ENGINE_IGNITION_Z := 0.0
const ZONE_BRIDGE := "Puente"; const ZONE_ENGINE := "Motor"; const ELEVATOR_PLATE_INDICES := [45, 35, 15, 5]

var pilot = null; var spiral_field = null; var spin_camera = null; var spin_predictor = null
var hub = null; var hull = null; var spin_omega := 0.0
var explosion = null; var handrails = null; var thruster_input = null
var terrace_props = null; var canonical_route = null; var rope_input = null
var industry_streamer = null; var spokes: Array = []
var _spiral_config: Dictionary = {}; var _bridge_z_min := 0.0; var _previous_gravity_mode := -1; var _wiring = null

func _ready() -> void:
	process_priority = 100
	spiral_field = get_node_or_null("DomeSpiralField"); pilot = get_node_or_null("Pilot")
	hub = get_node_or_null("AxialHub/SpinAxialHub"); hull = get_node_or_null("ArkRunHull")
	if spin_omega <= 0.0: spin_omega = SpinFrame.omega_for()
	_spiral_config = _resolve_spiral_config()
	_bridge_z_min = SpiralGeometry.plate_transform(_spiral_config, int(BRIDGE_PLATE_INDICES[0])).origin.z
	_ensure_presentation_nodes(); _configure_zone_nodes()
	_build_explosion_modules(); _build_traversal_modules(); _build_industry_modules(); _build_suit_os_modules(); _build_wiring()
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null: suit_os.shoulder_slots_suppressed = true
	if pilot != null:
		# F7: arranque real en ZERO_G; SPIN_REAL se activa recién al detonar.
		spawn_at_hub_start()

func _exit_tree() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null and _previous_gravity_mode >= 0: world.set_gravity_mode(_previous_gravity_mode)
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null: suit_os.shoulder_slots_suppressed = false

func _physics_process(delta: float) -> void: update_spin_presentation(delta)

# --- Consultas estables (F1–F6) ---
func get_spiral_config() -> Dictionary: return _spiral_config.duplicate(true)
func get_slice_length() -> float: return SLICE_LENGTH
func get_hull_radius() -> float: return R_HULL
func get_hub_radius() -> float: return R_HUB
func get_bridge_plate_indices() -> Array: return BRIDGE_PLATE_INDICES.duplicate()
func get_bridge_z_min() -> float: return _bridge_z_min
func get_engine_z_max() -> float: return ENGINE_Z_MAX
func get_engine_ignition_z() -> float: return ENGINE_IGNITION_Z
func get_canonical_route(): return canonical_route
func get_waypoint_count() -> int: return canonical_route.get_waypoints().size() if canonical_route != null else 0
# Objetivo de eyección: la placa 48, en pleno Puente (+Z).
func get_bridge_target() -> Vector3: return SpiralGeometry.plate_transform(_spiral_config, int(BRIDGE_PLATE_INDICES[1])).origin

func zone_at(position: Vector3) -> String:
	if position.z <= ENGINE_Z_MAX: return ZONE_ENGINE
	if position.z >= _bridge_z_min: return ZONE_BRIDGE
	return ""

func is_in_bridge(position: Vector3) -> bool: return zone_at(position) == ZONE_BRIDGE
func is_in_engine(position: Vector3) -> bool: return zone_at(position) == ZONE_ENGINE

# --- Setup ---
func _resolve_spiral_config() -> Dictionary:
	if spiral_field != null and spiral_field.has_method("get_spiral_configs"):
		var configs: Array = spiral_field.get_spiral_configs()
		if not configs.empty(): return configs[0]
	return FieldResource.default_spiral_config()

func _ensure_presentation_nodes() -> void:
	spin_camera = get_node_or_null("SpinRealCamera")
	if spin_camera == null:
		spin_camera = CameraControllerScript.new(); spin_camera.name = "SpinRealCamera"; add_child(spin_camera)
	spin_predictor = get_node_or_null("SpinLandingPredictor")
	if spin_predictor == null:
		spin_predictor = PredictorScript.new(); spin_predictor.name = "SpinLandingPredictor"; add_child(spin_predictor)

func _configure_zone_nodes() -> void:
	var bridge = get_node_or_null("BridgeZone")
	if bridge != null:
		bridge.set_meta("zone_name", ZONE_BRIDGE); bridge.set_meta("z_min", _bridge_z_min)
		bridge.set_meta("plate_indices", BRIDGE_PLATE_INDICES.duplicate())
	var engine = get_node_or_null("EngineZone")
	if engine != null:
		engine.set_meta("zone_name", ZONE_ENGINE); engine.set_meta("z_max", ENGINE_Z_MAX)

# Adjunta (o reutiliza) un nodo de módulo bajo su contenedor.
func _attach(parent: Node, node_name: String, script_resource):
	var node = parent.get_node_or_null(node_name)
	if node == null:
		node = script_resource.new(); node.name = node_name; parent.add_child(node)
	return node

# --- F1: hub ZERO_G, explosión al Puente y propulsores LT ---
func _build_explosion_modules() -> void:
	var root: Node = get_node("ExplosionController")
	handrails = _attach(root, "ArkRunHubHandrails", HandrailsScript)
	handrails.omega = spin_omega; handrails.hub_radius = R_HUB; handrails.attach_target(pilot)
	explosion = _attach(root, "ArkRunExplosion", ExplosionScript)
	explosion.omega = spin_omega; explosion.hub_radius = R_HUB
	explosion.bridge_target = get_bridge_target(); explosion.arm(pilot, spin_predictor)
	thruster_input = _attach(root, "ArkRunThrusterInput", ThrusterScript)

# --- F2: domos, ascensores radiales, cuerda y ruta proa→popa ---
func _build_traversal_modules() -> void:
	var root: Node = get_node("TraversalRoot")
	terrace_props = _attach(root, "ArkRunTerraceProps", TerracePropsScript)
	terrace_props.build_from_configs(spiral_field.get_spiral_configs() if spiral_field != null else [_spiral_config], SLICE_SEED)
	var elevators: Node = _attach(root, "Elevators", Spatial)
	spokes = []
	for plate_index in ELEVATOR_PLATE_INDICES:
		var spoke = _attach(elevators, "SpinSpoke_%d" % int(plate_index), SpokeScript)
		spoke.configure_from_plate(SpiralGeometry.plate_transform(_spiral_config, int(plate_index)), R_HUB)
		spokes.append(spoke)
	rope_input = _attach(root, "Rope", RopeInputScript)
	rope_input.set_pilot(pilot); rope_input.max_range = 190.0; rope_input.cone_deg = 55.0
	rope_input.get_rope().max_len = 200.0
	canonical_route = RouteScript.new(); canonical_route.configure(_spiral_config)

# Anclajes de cuerda: los resuelve el wiring (domos de TerraceProps + DomeRegistry).
func collect_rope_anchors() -> Array:
	return _wiring.collect_rope_anchors() if _wiring != null else []

# --- F3: industria procedural determinista (colisión gruesa + streaming) ---
func _build_industry_modules() -> void:
	var root: Node = get_node("IndustryRoot")
	industry_streamer = root.get_node_or_null("ArkRunIndustryStreamer")
	if industry_streamer == null:
		industry_streamer = StreamerScript.new(); industry_streamer.name = "ArkRunIndustryStreamer"
		industry_streamer.seed_value = SLICE_SEED; root.add_child(industry_streamer)
	industry_streamer.set_stream_target(pilot)

# --- F4: Suit OS (host en RaceHudRoot; destinos/ruta desde ArkRunCanonicalRoute) ---
func _build_suit_os_modules() -> void:
	var host = _attach(get_node("RaceHudRoot"), "ArkRunSuitOSHost", SuitOSHostScript)
	host.set_slice(self)

func activate_spin_gravity() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world == null: return
	if _previous_gravity_mode < 0: _previous_gravity_mode = int(world.get_current_gravity_mode())
	world.set_gravity_mode(GravityModes.Mode.SPIN_REAL)

func deactivate_spin_gravity() -> void:
	var world = get_node_or_null("/root/GravityWorld"); if world != null and _previous_gravity_mode >= 0: world.set_gravity_mode(_previous_gravity_mode)

# --- Pilot ---
func spawn_at_hub_start(r0: float = 4.0, z0: float = ENGINE_IGNITION_Z) -> void:
	if pilot == null: return
	var position := Vector3(max(r0, 0.01), 0.0, z0)
	var up: Vector3 = SpinFrame.up(position, Vector3.UP)
	var x_axis: Vector3 = up.cross(Vector3(0.0, 0.0, -1.0)).normalized()
	_place_pilot(Transform(Basis(x_axis, up, Vector3(0.0, 0.0, -1.0)).orthonormalized(), position), up, Vector3.ZERO)

func _place_pilot(body_transform: Transform, up: Vector3, body_velocity: Vector3) -> void:
	pilot.global_transform = body_transform; pilot.velocity = body_velocity; pilot.set_sim_up(up)
	if "movement_logic" in pilot and is_instance_valid(pilot.movement_logic):
		pilot.movement_logic.horizontal_velocity = Vector3.ZERO; pilot.movement_logic.wish_direction = Vector3.ZERO
	if "jump_logic" in pilot and is_instance_valid(pilot.jump_logic): pilot.jump_logic.set_internal_velocity(0.0)
	if "traversal_logic" in pilot and is_instance_valid(pilot.traversal_logic):
		pilot.traversal_logic.is_climbing = false; pilot.traversal_logic.is_hanging = false
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	if physics != null:
		physics._was_grounded = false; physics._slide_active = false; physics._tumble_timer = 0.0
		physics.spin_thruster_dv_remaining = physics.spin_thruster_dv_max

func r_local_for_position(position: Vector3) -> float:
	var count: int = SpiralGeometry.plate_count_for(_spiral_config)
	var total_height: float = float(_spiral_config.get("total_height", SLICE_LENGTH))
	var step: float = max(float(_spiral_config.get("plate_step", 40.0)), 0.001)
	var index: int = int(clamp(round((position.z + total_height * 0.5) / step), 0.0, float(count - 1)))
	return SpinFrame.r_perp(SpiralGeometry.plate_transform(_spiral_config, index).origin).length()

# --- F5/F6: cableado, presentación y determinismo en ArkRunSliceWiring ---
func _build_wiring() -> void:
	_wiring = WiringScript.new(); _wiring.name = "ArkRunWiring"; add_child(_wiring); _wiring.setup(self)

func update_spin_presentation(dt: float) -> void:
	if _wiring != null and is_instance_valid(_wiring): _wiring.present(dt)

func run_determinism_scenario() -> Dictionary:
	return _wiring.run_determinism_scenario() if _wiring != null else {}
