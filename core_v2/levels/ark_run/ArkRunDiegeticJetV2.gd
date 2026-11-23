extends Spatial
class_name ArkRunDiegeticJetV2

# FD-325 T4 — feedback diegético de propulsión: doble boquilla emisiva en la
# mochila de Elías (siempre a lo largo de -thrust_dir), arco 2D de Δv proyectado
# junto al hombro y silbido de gas procedural. Sólo presentación (no muta
# simulación ni cámara), seguro en headless/Dummy, sin randf()/randomize(). El
# arco usa la Línea2D del HUD para no agregar draw calls.

const NOZZLE_OFFSETS := [Vector3(-0.22, 0.35, 0.28), Vector3(0.22, 0.35, 0.28)]  # espalda izq/der
const CONE_LENGTH := 0.55; const CONE_RADIUS := 0.09
const ARC_JOINTS := 6; const ARC_RADIUS := 46.0; const ARC_SPAN := 0.85
const FILL_COLOR := Color(0.15, 0.92, 1.0, 1.0); const WARN_COLOR := Color(1.0, 0.66, 0.12, 1.0)
const EMPTY_COLOR := Color(1.0, 0.22, 0.18, 1.0); const EMPTY_RATIO := 0.01; const WARN_RATIO := 0.30
const SHOULDER_OFFSET := Vector3(0.0, 0.35, 0.75)
const WHISTLE_FREQ := 2350.0; const MIX_RATE := 22050.0; const FILL_FRAMES := 1024
const RopeFeedback = preload("res://core_v2/levels/ark_run/ArkRunDiegeticRopeV2.gd")
const SHADER_CODE = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float pulse = 0.80 + 0.20 * sin(TIME * 26.0);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float core = smoothstep(0.0, 0.45, 1.0 - clamp(UV.y, 0.0, 1.0));
	vec3 color = mix(vec3(0.25, 0.75, 1.0), vec3(0.85, 0.98, 1.0), core);
	color = mix(color, vec3(1.0, 0.55, 0.18), fresnel * 0.5);
	ALBEDO = color * 1.25 * (0.9 + 0.5 * pulse);
	ALPHA = clamp(0.35 + 0.55 * fresnel + 0.15 * core, 0.0, 1.0) * (0.8 + 0.2 * pulse);
}
"""

var _nozzles: Array = []
var _arc_line = null
var _camera: Camera = null
var _arc_visible := false
var _arc_points: Array = []
var _arc_color := FILL_COLOR
var _blink := 0.0
var _whistle: AudioStreamPlayer = null
var _playback: AudioStreamPlayback = null
var _whistle_on := false
var _phase := 0.0

func _init() -> void:
	_ensure_nozzles()

# Línea2D del HUD (opcional) donde se dibuja el arco: evita un draw call propio.
func attach_hud_line(line) -> void:
	_arc_line = line

func update_jet(
	pilot_transform: Transform, thrust_dir: Vector3, thrusting: bool, dv_ratio: float,
	grounded: bool, cam: Camera, dt: float
) -> Dictionary:
	var dv: float = clamp(dv_ratio, 0.0, 1.0)
	var burning: bool = thrusting and dv > EMPTY_RATIO
	_orient_nozzles(pilot_transform, thrust_dir, burning)
	_update_arc(pilot_transform, thrusting, dv, grounded, cam, max(dt, 0.0))
	_update_audio(burning, dv, max(dt, 0.0))
	return {
		"jet_visible": burning, "arc_visible": _arc_visible, "arc_color": _arc_color,
		"empty": thrusting and dv <= EMPTY_RATIO,
		"nozzle_count": int(_nozzles.size()), "audio_active": _whistle_on,
	}

func get_nozzles() -> Array:
	return _nozzles.duplicate()

func get_nozzle_transforms() -> Array:
	var result: Array = []
	for nozzle in _nozzles:
		result.append((nozzle as Spatial).global_transform)
	return result

func is_jet_visible() -> bool:
	return not _nozzles.empty() and _nozzles[0].visible

func is_arc_visible() -> bool:
	return _arc_visible

func get_arc_color() -> Color:
	return _arc_color

func get_arc_points() -> Array:
	return _arc_points.duplicate()

func _ensure_nozzles() -> void:
	if _nozzles.size() == NOZZLE_OFFSETS.size():
		return
	for offset in NOZZLE_OFFSETS:
		var nozzle := MeshInstance.new()
		nozzle.name = "JetNozzle%d" % _nozzles.size()
		nozzle.mesh = _cone()
		nozzle.material_override = _nozzle_material()
		nozzle.visible = false
		add_child(nozzle)
		_nozzles.append(nozzle)

func _cone() -> CylinderMesh:
	var cone := CylinderMesh.new()
	cone.top_radius = CONE_RADIUS * 0.18
	cone.bottom_radius = CONE_RADIUS
	cone.height = CONE_LENGTH
	cone.radial_segments = 10
	cone.rings = 1
	return cone

func _nozzle_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _orient_nozzles(pilot_transform: Transform, thrust_dir: Vector3, burning: bool) -> void:
	var exhaust: Vector3 = -(thrust_dir.normalized() if thrust_dir.length_squared() > 1e-8 \
		else pilot_transform.basis.z)
	var back: Vector3 = pilot_transform.basis.z.normalized()
	var ref: Vector3 = back if abs(back.dot(exhaust)) < 0.99 else pilot_transform.basis.x
	var side: Vector3 = ref.cross(exhaust).normalized()
	side = side if side.length_squared() > 1e-8 else Vector3.RIGHT
	var up: Vector3 = exhaust.cross(side).normalized()
	for index in range(_nozzles.size()):
		var nozzle: MeshInstance = _nozzles[index]
		nozzle.visible = burning
		if burning:
			var muzzle: Vector3 = pilot_transform.origin \
				+ pilot_transform.basis.xform(NOZZLE_OFFSETS[index])
			nozzle.global_transform = Transform(Basis(side, exhaust, up),
				muzzle + exhaust * (CONE_LENGTH * 0.5))

# Auto-oculto en suelo al 100%; cian >= 0.30, ámbar < 0.30, rojo parpadeante vacío.
func _update_arc(
	pilot_transform: Transform, thrusting: bool, dv: float, grounded: bool,
	cam: Camera, dt: float
) -> void:
	if cam != null and is_instance_valid(cam):
		_camera = cam
	var empty: bool = thrusting and dv <= EMPTY_RATIO
	_arc_visible = not (grounded and dv >= 0.99 and not thrusting and not empty)
	_blink += dt if empty else 0.0
	_arc_color = EMPTY_COLOR if empty else (FILL_COLOR if dv >= WARN_RATIO else WARN_COLOR)
	_arc_points = _project_arc(pilot_transform, empty)
	_refresh_arc()

func _project_arc(pilot_transform: Transform, empty: bool) -> Array:
	var points: Array = []
	if _camera == null or not is_instance_valid(_camera):
		return points
	var shoulder: Vector2 = _camera.unproject_position(
		pilot_transform.origin + pilot_transform.basis.xform(SHOULDER_OFFSET))
	var center: Vector2 = shoulder + Vector2(0.0, -ARC_RADIUS * 0.55)
	var alpha: float = (1.0 if fmod(_blink, 0.32) < 0.16 else 0.25) if empty else _arc_color.a
	for index in range(ARC_JOINTS):
		var t: float = (0.5 - (float(index) / float(ARC_JOINTS - 1)) * ARC_SPAN) * PI
		points.append({"point": center + Vector2(cos(t), -sin(t)) * ARC_RADIUS,
			"color": Color(_arc_color.r, _arc_color.g, _arc_color.b, alpha)})
	return points

func _refresh_arc() -> void:
	if not is_instance_valid(_arc_line):
		return
	var baked := PoolVector2Array()
	for index in range(ARC_JOINTS if _arc_visible else 0):
		baked.append(_arc_points[index]["point"])
	_arc_line.points = baked
	_arc_line.default_color = _arc_color

# Audio procedural: silbido de gas frío mientras propulsa; nunca falla con Dummy.
func _update_audio(burning: bool, dv: float, dt: float) -> void:
	if burning and not _whistle_on:
		_whistle = RopeFeedback.make_cue("JetWhistle", MIX_RATE, -12.0)
		add_child(_whistle)
		_whistle.play()
		_playback = _whistle.get_stream_playback()
		_whistle_on = true
	elif not burning and _whistle_on:
		_whistle_on = false
		_playback = null
		_whistle.stop()
	if not _whistle_on or _playback == null:
		return
	_phase += dt
	var count: int = int(min(_playback.get_frames_available(), FILL_FRAMES))
	if count <= 0:
		return
	var buffer := PoolVector2Array()
	buffer.resize(count)
	var amplitude: float = (0.05 + 0.22 * dv) * (0.75 + 0.25 * sin(_phase * 26.0))
	for index in range(count):
		var sample: float = sin(TAU * WHISTLE_FREQ * float(index) / MIX_RATE) * amplitude
		buffer[index] = Vector2(sample, sample)
	_playback.push_buffer(buffer)
