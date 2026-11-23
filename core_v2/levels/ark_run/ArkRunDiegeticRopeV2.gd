extends Spatial
class_name ArkRunDiegeticRopeV2

# FD-325 T4 — feedback diegético de cuerda.
# Retícula magnética 2D proyectada sobre el anclaje (badge veraz del dispositivo),
# tether 3D emisivo por estado (SWING cian / REELING dorado-naranja con aro),
# empuje suave de FOV de catapulta y audio procedural seguro en headless (helper
# make_cue reutilizado por el jet). Sólo presentación: sin rig nuevo ni
# randf()/randomize(). La retícula se pinta con la Línea2D del HUD.

const SWING_COLOR := Color(0.15, 0.92, 1.0, 1.0); const REEL_COLOR := Color(1.0, 0.62, 0.12, 1.0)
const ROPE_WIDTH := 0.035; const BRACKET_SIZE := 26.0; const BRACKET_GAP := 34.0
const FOV_MAX_OFFSET := 5.0; const FOV_RISE_RATE := 7.0; const FOV_FALL_RATE := 4.0
const FOV_SPEED_FULL := 30.0; const PULSE_TRAVEL_SPEED := 2.2
const BADGE_BY_DEVICE := {"gamepad": "RT", "keyboard": "E", "touch": "CUERDA"}

var _tether: MeshInstance = null
var _ring: MeshInstance = null
var _reticle_line = null
var _click: AudioStreamPlayer = null
var _fov_offset := 0.0
var _elapsed := 0.0
var _state := "IDLE"
var _badge := "E"
var _tether_color := SWING_COLOR
var _last_audio := ""
var _reticle_text := ""

# Función pura: sube suave hacia +max_offset con retracción/alta velocidad y
# vuelve suave a 0. Nunca salta (acotada por rate * dt por paso).
static func step_catapult_fov_offset(
	current_offset: float, reeling: bool, speed: float, dt: float, max_offset: float = FOV_MAX_OFFSET
) -> float:
	var ceiling: float = max(max_offset, 0.0)
	var speed_ratio: float = clamp(max(speed, 0.0) / FOV_SPEED_FULL, 0.0, 1.0)
	var target: float = ceiling if reeling else ceiling * speed_ratio * 0.6
	var delta: float = target - current_offset
	var rate: float = FOV_RISE_RATE if delta >= 0.0 else FOV_FALL_RATE
	var next: float = current_offset + clamp(delta, -rate * max(dt, 0.0), rate * max(dt, 0.0))
	return clamp(next, 0.0, ceiling)

static func badge_for_device(input_device: String) -> String:
	return BADGE_BY_DEVICE.get(input_device, BADGE_BY_DEVICE["keyboard"])

static func format_distance(distance: float) -> String:
	return "%d m" % int(round(max(distance, 0.0)))

# Línea2D del HUD donde se dibuja la retícula (reusa un draw call existente).
func attach_hud_lines(reticle_line) -> void:
	_reticle_line = reticle_line

func get_state() -> String:
	return _state

func get_badge() -> String:
	return _badge

func get_fov_offset() -> float:
	return _fov_offset

func get_tether_color() -> Color:
	return _tether_color

func update_rope_feedback(
	pilot_pos: Vector3, anchor_pos: Vector3, distance: float, has_target: bool,
	attached: bool, reeling: bool, input_device: String, cam: Camera, dt: float
) -> Dictionary:
	_elapsed += max(dt, 0.0)
	_state = "REELING" if reeling else ("SWING" if attached else ("READY" if has_target else "IDLE"))
	_badge = badge_for_device(input_device)
	_tether_color = REEL_COLOR if reeling else SWING_COLOR
	var front: bool = _is_front_of_camera(anchor_pos, cam)
	var reticle_visible: bool = has_target and not attached and front
	_update_tether(pilot_pos, anchor_pos, attached, reeling)
	_draw_reticle(anchor_pos, distance, reticle_visible, cam)
	_update_audio(_audio_mode(attached, reeling, has_target, front))
	_fov_offset = step_catapult_fov_offset(_fov_offset, reeling, distance, max(dt, 0.0))
	return {
		"state": _state, "badge": _badge, "tether_color": _tether_color,
		"tether_visible": attached, "reticle_visible": reticle_visible,
		"fov_offset": float(_fov_offset),
	}

func _is_front_of_camera(world: Vector3, cam: Camera) -> bool:
	if cam == null or not is_instance_valid(cam):
		return false
	return (world - cam.global_transform.origin).dot(-cam.global_transform.basis.z.normalized()) > 0.0

# 4 corchetes magnéticos que se cierran sobre el anclaje proyectado.
func _draw_reticle(anchor_pos: Vector3, distance: float, visible_now: bool, cam: Camera) -> void:
	if not is_instance_valid(_reticle_line):
		return
	if not visible_now or cam == null or not is_instance_valid(cam):
		_reticle_line.points = PoolVector2Array()
		return
	var breath: float = 0.5 + 0.5 * sin(_elapsed * 3.2)
	var screen: Vector2 = cam.unproject_position(anchor_pos)
	var gap: float = BRACKET_GAP - breath * 6.0
	var baked := PoolVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var start: Vector2 = screen + Vector2(corner.x * gap, corner.y * gap)
		baked.append(start)
		baked.append(start - Vector2(corner.x * BRACKET_SIZE, corner.y * BRACKET_SIZE))
	_reticle_line.points = baked
	_reticle_line.default_color = Color(0.15, 0.92, 1.0, 0.70 + 0.30 * breath)
	_reticle_text = "%s  %s" % [format_distance(distance), _badge]

func get_reticle_label() -> String:
	return _reticle_text

func _update_tether(pilot_pos: Vector3, anchor_pos: Vector3, attached: bool, reeling: bool) -> void:
	if not is_instance_valid(_tether):
		_tether = _cylinder("RopeTether", SWING_COLOR)
	_tether.visible = attached
	var delta: Vector3 = anchor_pos - pilot_pos
	var length: float = delta.length()
	if not attached or length < 1e-4:
		_update_ring(Vector3.ZERO, false)
		return
	var pulse: float = 1.0 + (0.18 * sin(_elapsed * 14.0) if reeling else 0.05 * sin(_elapsed * 4.0))
	_tether.global_transform = Transform(_basis_along(delta / length).scaled(Vector3(pulse, length, pulse)),
		pilot_pos + delta * 0.5)
	var material: SpatialMaterial = _tether.material_override
	material.albedo_color = _tether_color
	material.emission_energy = 2.6 if reeling else 1.7
	_update_ring(anchor_pos if reeling else Vector3.ZERO, reeling)

func _update_ring(anchor_pos: Vector3, visible_now: bool) -> void:
	if not visible_now:
		if is_instance_valid(_ring):
			_ring.visible = false
		return
	if not is_instance_valid(_ring):
		_ring = MeshInstance.new()
		_ring.name = "RopeAnchorRing"
		var mesh := TorusMesh.new()
		mesh.inner_radius = 1.1
		mesh.outer_radius = 1.4
		mesh.rings = 16
		mesh.ring_segments = 6
		mesh.material = _material(REEL_COLOR, 2.4)
		_ring.mesh = mesh
		add_child(_ring)
	_ring.visible = true
	_ring.global_transform = Transform(Basis().scaled(Vector3.ONE
		* (1.0 + 0.25 * fmod(_elapsed * PULSE_TRAVEL_SPEED, 1.0))), anchor_pos)

func _cylinder(node_name: String, color: Color) -> MeshInstance:
	var node := MeshInstance.new()
	node.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = ROPE_WIDTH
	cylinder.bottom_radius = ROPE_WIDTH
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	node.mesh = cylinder
	node.material_override = _material(color)
	add_child(node)
	return node

static func _basis_along(axis_y: Vector3) -> Basis:
	var x_axis: Vector3 = axis_y.cross(Vector3(0.0, 0.0, 1.0))
	x_axis = (x_axis if x_axis.length_squared() > 1e-6 else axis_y.cross(Vector3.RIGHT)).normalized()
	return Basis(x_axis, axis_y, x_axis.cross(axis_y).normalized())

func _material(color: Color, energy: float = 1.8) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = energy
	return material

# Audio procedural protegido: con driver "Dummy" (headless) el stream se ignora.
static func make_cue(node_name: String, mix_rate: float, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.volume_db = volume_db
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = mix_rate
	stream.buffer_length = 0.10
	player.stream = stream
	return player

func _audio_mode(attached: bool, reeling: bool, has_target: bool, front: bool) -> String:
	return "reel" if reeling else ("hook" if attached else ("ready" if has_target and front else "none"))

func _update_audio(mode: String) -> void:
	var changed: bool = mode != _last_audio
	_last_audio = "" if mode == "none" else mode
	if not changed or mode == "none":
		return
	if not is_instance_valid(_click):
		_click = make_cue("RopeCue", 22050.0, -16.0)
		add_child(_click)
	if not _click.playing:
		_click.play()
