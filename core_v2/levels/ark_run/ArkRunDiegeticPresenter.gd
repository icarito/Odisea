extends Node

# FD-325 T4 — presentación diegética del Ark-Run en un módulo <200: monta las líneas 2D
# reutilizadas (arco Δv del jet y retículo de cuerda), alimenta ArkRunDiegeticJetV2 /
# ArkRunDiegeticRopeV2 con la cámara activa y el dispositivo real, y aplica el offset
# de FOV de catapulta como término aditivo sobre el CameraRig existente (nunca uno nuevo).

const JetScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticJetV2.gd")
const RopeScript = preload("res://core_v2/levels/ark_run/ArkRunDiegeticRopeV2.gd")
const SwingScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const TOUCH_SCREEN_FALLBACK := Vector2(1280.0, 720.0)
const FOV_EPSILON := 0.01

var loop = null
var wiring = null
var slice = null
var jet = null
var rope = null
var _fov_offset := 0.0
var _rig_base_fov := -1.0
var _crosshair = null
# Crosshair central (mismo lenguaje que el láser/gloo): cruz cortada en el centro.
const CROSS_ARM := 6.0; const CROSS_GAP := 3.0; const CROSS_COLOR := Color(0.75, 0.95, 1.0, 0.55)

func setup(loop_node, wiring_node) -> void:
	loop = loop_node
	wiring = wiring_node
	slice = wiring.slice if wiring != null else null
	jet = JetScript.new(); jet.name = "ArkRunDiegeticJet"; add_child(jet)
	rope = RopeScript.new(); rope.name = "ArkRunDiegeticRope"; add_child(rope)
	_build_lines()

# Líneas 2D del HUD reutilizadas (sin draw calls propios adicionales).
func _build_lines() -> void:
	var root: Control = Control.new()
	root.name = "DiegeticOverlay"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var arc := Line2D.new(); arc.name = "JetArc"; arc.width = 3.0
	var cross := Line2D.new(); cross.name = "Crosshair"; cross.width = 1.5
	var reticle := Line2D.new(); reticle.name = "RopeReticle"; reticle.width = 2.0
	root.add_child(arc); root.add_child(cross); root.add_child(reticle)
	jet.attach_hud_line(arc)
	rope.attach_hud_lines(reticle)
	_crosshair = cross

func camera() -> Camera:
	return get_viewport().get_camera() if get_viewport() != null else null

func screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size if get_viewport() != null else TOUCH_SCREEN_FALLBACK

# Anclaje listo visible: delante de la cámara y dentro del viewport.
func anchor_in_viewport(anchor: Vector3, cam: Camera) -> bool:
	if cam == null or not is_instance_valid(cam) or cam.is_position_behind(anchor):
		return false
	return Rect2(Vector2.ZERO, screen_size()).has_point(cam.unproject_position(anchor))

func best_anchor(aim: Vector3) -> Dictionary:
	var pilot = slice.pilot
	var rope_in = slice.rope_input
	# Misma lista que puede engancharse: anclajes con línea de visión del último tick.
	var candidates: Array = wiring.anchors
	if wiring.feedback != null and wiring.feedback.has_method("visible_anchors"):
		candidates = wiring.feedback.visible_anchors(pilot)
	return SwingScript.select_best_anchor(pilot.global_transform.origin, aim, candidates,
		float(rope_in.max_range) if rope_in != null else 55.0,
		float(rope_in.cone_deg) if rope_in != null else 24.0)

# Un tick de presentación: jet (con Δv/suelo), retícula/tether y FOV de catapulta.
func present(dt: float, tick: Dictionary, pos: Vector3) -> void:
	var pilot = slice.pilot
	var cam: Camera = camera()
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	var dv: float = float(tick.get("dv_ratio", _dv_of(physics)))
	var grounded: bool = bool(physics._was_grounded) if physics != null else pilot.is_on_floor()
	var thrust_dir: Vector3 = tick.get("thrust_dir", -pilot.global_transform.basis.z)
	_draw_crosshair(cam)
	jet.update_jet(pilot.global_transform, thrust_dir, bool(tick.get("thrusting", false)), dv,
		grounded, cam, dt)
	var attached: bool = slice.rope_input != null and slice.rope_input.is_attached()
	var anchor_state: Dictionary = _anchor_state(attached)
	var anchor: Vector3 = anchor_state["anchor"]
	var distance: float = float(anchor_state["distance"])
	var reeling: bool = bool(tick.get("reeling", false))
	var feed: Dictionary = rope.update_rope_feedback(pos, anchor, distance,
		bool(anchor_state["hit"]), attached, reeling, String(tick.get("device", "keyboard")), cam, dt)
	_apply_fov(pilot, float(feed.get("fov_offset", _fov_offset)))

# Crosshair central minimalista: cruz cortada en el centro exacto del viewport.
func _draw_crosshair(cam: Camera) -> void:
	if not is_instance_valid(_crosshair):
		return
	if cam == null or not is_instance_valid(cam):
		_crosshair.points = PoolVector2Array()
		return
	var viewport = cam.get_viewport()
	var center: Vector2 = viewport.get_visible_rect().size * 0.5 \
		if viewport != null else Vector2(640.0, 360.0)
	var pts := PoolVector2Array()
	for axis in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		pts.append(center + axis * CROSS_GAP)
		pts.append(center + axis * (CROSS_GAP + CROSS_ARM))
	_crosshair.points = pts
	_crosshair.default_color = CROSS_COLOR

func _anchor_state(attached: bool) -> Dictionary:
	if attached:
		var rope_body = slice.rope_input.get_rope()
		var point: Vector3 = rope_body.get_anchor() if rope_body != null else slice.pilot.global_transform.origin
		return {"anchor": point, "hit": true,
			"distance": slice.pilot.global_transform.origin.distance_to(point)}
	if not wiring.is_live_loop_running():
		return {"anchor": Vector3.ZERO, "hit": false, "distance": 0.0}
	var best: Dictionary = best_anchor(loop.rope_aim_dir(slice.pilot))
	return {"anchor": best.get("anchor_position", Vector3.ZERO),
		"hit": bool(best.get("hit", false)), "distance": float(best.get("distance", 0.0))}

# Offset aditivo suave SOBRE EL RIG EXISTENTE: el jugador ya mira su FOV hacia pilot.base_fov,
# así que escribimos la suma ahí (nunca creamos otro rig ni un nuevo escritor de cámara). El
# snapshot/replay del player elimina este término para no ensuciar el estado guardado.
func _apply_fov(pilot, offset: float) -> void:
	_fov_offset = offset
	if not ("base_fov" in pilot):
		return
	if _rig_base_fov < 0.0:
		_rig_base_fov = float(pilot.base_fov)
	pilot.base_fov = clamp(_rig_base_fov + _fov_offset, 20.0, 110.0)

# Devuelve el FOV del rig a su base limpia (reinicio o salida).
func reset_fov() -> void:
	_fov_offset = 0.0
	if _rig_base_fov >= 0.0 and slice.pilot != null and "base_fov" in slice.pilot:
		slice.pilot.base_fov = _rig_base_fov
	_rig_base_fov = -1.0

func _dv_of(physics) -> float:
	if physics != null and float(physics.spin_thruster_dv_max) > 0.0:
		return float(physics.spin_thruster_dv_remaining) / float(physics.spin_thruster_dv_max)
	return 0.0
