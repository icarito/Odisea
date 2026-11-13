extends Spatial
# Sin class_name para no exigir reescritura de project.godot.

const SCENE_PATH := "res://core_v2/actors/ProgrammerHoloNPC.tscn"
const GROUP_NAME := "programmer_holo_npc"
const CAMERA_REQUEST_SOURCE := "odisea_npc"
const CAMERA_REQUEST_PRIORITY := 20
const CAMERA_CONTROL_MODE_LOCKED_VIEW := 2

signal arrived(target_pos)
signal script_finished()
signal speech_finished()

enum State { HIDDEN, FADE_IN, ACTIVE, FADE_OUT }

enum BehaviorMode {
	HIDDEN,
	APPEAR_SPEAK,
	FOLLOW,
	MOVE_TO,
	ORBIT_GUIDE,
	SCRIPTED
}

export(float) var spawn_distance := 2.8
export(float) var spawn_side_offset := 0.85
export(float) var spawn_height_offset := 0.12
export(float) var fade_in_duration := 0.4
export(float) var fade_out_duration := 0.45
export(float) var bob_amplitude := 0.08
export(float) var bob_speed := 2.1
export(float) var sway_amplitude := 0.45
export(float) var sway_speed := 0.75
export(float) var depth_sway_amplitude := 0.18
export(float) var depth_sway_speed := 0.55
export(float) var max_follow_distance := 6.5
export(float) var follow_lerp_speed := 2.5
export(float) var yaw_lerp_speed := 6.0

export(float) var follow_distance := 2.4
export(float) var follow_side_offset := 1.25
export(float) var follow_height_offset := 0.15
export(float) var follow_speed := 4.5
export(float) var follow_catchup_speed := 7.5
export(float) var arrival_threshold := 0.25
export(float) var guide_wait_distance := 7.0
export(float) var guide_resume_distance := 5.5
export(float) var walk_speed_threshold := 0.25
export(float) var jog_speed_threshold := 2.8
export(float) var sprint_speed_threshold := 5.5

var _state: int = State.HIDDEN
var _behavior_mode: int = BehaviorMode.HIDDEN
var _remaining_sec: float = 0.0
var _fade_timer: float = 0.0
var _speech_elapsed: float = 0.0
var _anchor_origin: Vector3 = Vector3.ZERO
var _anchor_right: Vector3 = Vector3.RIGHT
var _anchor_forward: Vector3 = Vector3.FORWARD
var _base_alpha_scale: float = 0.85
var _base_min_alpha: float = 0.02
var _base_emission: float = 2.4
var _base_glitch: float = 0.42
var _base_light_energy: float = 0.4
var _entrance_played: bool = false

var _target_pos: Vector3 = Vector3.ZERO
var _move_speed: float = 4.5
var _move_timeout: float = -1.0
var _follow_duration: float = -1.0
var _guide_waiting: bool = false
var _arrived_emitted: bool = false
var _horizontal_speed: float = 0.0

var _override_anim: String = ""
var _current_anim_name: String = ""

var _script_queue: Array = []
var _script_index: int = 0
var _step_submode: String = ""
var _step_timer: float = -1.0

var _camera_request_id: int = -1
var _camera_focus_timer: float = 0.0
var _camera_focus_offset: Vector3 = Vector3(0.0, 1.35, 2.2)

onready var _pivot: Spatial = get_node_or_null("Visual/Pivot")
onready var _omni_light: OmniLight = get_node_or_null("OmniLight")
onready var _cam_rig: Spatial = get_node_or_null("HoloCameraRig")
onready var _cam_node: Camera = get_node_or_null("HoloCameraRig/Camera")

var _holo_material: ShaderMaterial = null
var _anim_player: AnimationPlayer = null
var _explicit_viewer: Spatial = null


static func summon(tree: SceneTree, duration: float = 8.0, target_anchor: Spatial = null) -> Node:
	if tree == null:
		return null
	var existing: Array = tree.get_nodes_in_group(GROUP_NAME)
	var npc: Node = null
	for node in existing:
		if is_instance_valid(node):
			npc = node
			break
	if npc == null:
		var packed := load(SCENE_PATH) as PackedScene
		if packed == null:
			return null
		npc = packed.instance()
		var parent: Node = tree.current_scene if is_instance_valid(tree.current_scene) else tree.root
		if parent == null:
			return null
		parent.add_child(npc)
	if npc.has_method("appear_and_speak"):
		npc.call("appear_and_speak", duration, target_anchor)
	return npc


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_setup_material()
	_setup_animation()
	if is_instance_valid(_omni_light):
		_base_light_energy = _omni_light.light_energy
	if is_instance_valid(_cam_node):
		_cam_node.current = false
	_apply_holo_visibility(0.0, 0.95)
	visible = false
	_state = State.HIDDEN
	_behavior_mode = BehaviorMode.HIDDEN
	set_physics_process(false)


func _setup_material() -> void:
	var mesh_node := find_node("Mesh_0", true, false) as MeshInstance
	if mesh_node == null:
		return
	var mat := mesh_node.get_surface_material(0)
	if mat == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
		mat = mesh_node.mesh.surface_get_material(0)
	if mat is ShaderMaterial:
		_holo_material = mat.duplicate() as ShaderMaterial
		mesh_node.set_surface_material(0, _holo_material)
		_base_alpha_scale = _read_shader_float(_holo_material, "alpha_scale", _base_alpha_scale)
		_base_min_alpha = _read_shader_float(_holo_material, "min_alpha", _base_min_alpha)
		_base_emission = _read_shader_float(_holo_material, "emission_energy", _base_emission)
		_base_glitch = _read_shader_float(_holo_material, "glitch_strength", _base_glitch)


static func _read_shader_float(mat: ShaderMaterial, param_name: String, fallback: float) -> float:
	var val = mat.get_shader_param(param_name)
	if typeof(val) == TYPE_REAL or typeof(val) == TYPE_INT:
		return float(val)
	return fallback


func _setup_animation() -> void:
	_anim_player = find_node("AnimationPlayer", true, false) as AnimationPlayer
	if is_instance_valid(_anim_player):
		if not _anim_player.is_connected("animation_finished", self, "_on_animation_finished"):
			_anim_player.connect("animation_finished", self, "_on_animation_finished")


func appear_and_speak(duration: float = 8.0, target_anchor: Spatial = null) -> void:
	_behavior_mode = BehaviorMode.APPEAR_SPEAK
	_remaining_sec = max(duration, 1.5)
	_script_queue.clear()
	_step_submode = ""
	if is_instance_valid(target_anchor):
		_explicit_viewer = target_anchor
	if _state == State.HIDDEN or _state == State.FADE_OUT:
		_place_in_front_of_viewer(target_anchor)
		_speech_elapsed = 0.0
		_fade_timer = 0.0
		_entrance_played = false
		_override_anim = ""
		_state = State.FADE_IN
		visible = true
		set_physics_process(true)
		_play_entrance_or_idle()


func start_follow(target: Spatial = null, duration: float = -1.0) -> void:
	if is_instance_valid(target):
		_explicit_viewer = target
	_behavior_mode = BehaviorMode.FOLLOW
	_follow_duration = duration
	_script_queue.clear()
	_step_submode = ""
	if _state == State.HIDDEN:
		_place_in_front_of_viewer(target)
	_ensure_visible_and_active()


func move_to(target_pos: Vector3, speed: float = 4.5, timeout: float = -1.0) -> void:
	_behavior_mode = BehaviorMode.MOVE_TO
	_target_pos = target_pos
	_move_speed = max(speed, 0.1)
	_move_timeout = timeout
	_arrived_emitted = false
	_script_queue.clear()
	_step_submode = ""
	if _state == State.HIDDEN and is_inside_tree():
		_anchor_origin = global_transform.origin
	_ensure_visible_and_active()


func guide_to(target_pos: Vector3, speed: float = 4.0) -> void:
	_behavior_mode = BehaviorMode.ORBIT_GUIDE
	_target_pos = target_pos
	_move_speed = max(speed, 0.1)
	_guide_waiting = false
	_arrived_emitted = false
	_script_queue.clear()
	_step_submode = ""
	if _state == State.HIDDEN and is_inside_tree():
		_anchor_origin = global_transform.origin
	_ensure_visible_and_active()


func run_script(steps: Array) -> void:
	_script_queue = steps.duplicate(true)
	_script_index = 0
	_step_submode = ""
	_step_timer = -1.0
	_behavior_mode = BehaviorMode.SCRIPTED
	if _state == State.HIDDEN:
		if is_inside_tree():
			_anchor_origin = global_transform.origin
		var viewer := _resolve_viewer()
		if is_instance_valid(viewer) and _anchor_origin == Vector3.ZERO:
			_place_in_front_of_viewer(viewer)
	_ensure_visible_and_active()
	_start_next_script_step()


func stop_script() -> void:
	_script_queue.clear()
	_script_index = 0
	_step_submode = ""
	_step_timer = -1.0


func disappear(immediate: bool = false) -> void:
	release_camera()
	stop_script()
	_override_anim = ""
	if immediate:
		_state = State.HIDDEN
		_behavior_mode = BehaviorMode.HIDDEN
		_remaining_sec = 0.0
		_fade_timer = 0.0
		_horizontal_speed = 0.0
		visible = false
		_apply_holo_visibility(0.0, 0.95)
		set_physics_process(false)
		return
	if _state == State.HIDDEN or _state == State.FADE_OUT:
		return
	_state = State.FADE_OUT
	_fade_timer = 0.0


func play_animation(anim_name: String, blend: float = 0.25) -> bool:
	if anim_name == "" or not is_instance_valid(_anim_player):
		return false
	if not _anim_player.has_animation(anim_name):
		return false
	_override_anim = anim_name
	_current_anim_name = anim_name
	_anim_player.play(anim_name, blend)
	return true


func get_current_animation() -> String:
	if is_instance_valid(_anim_player) and _anim_player.current_animation != "":
		return _anim_player.current_animation
	return _current_anim_name


func focus_camera(duration: float = 3.0, offset: Vector3 = Vector3(0.0, 1.35, 2.2)) -> void:
	_camera_focus_offset = offset
	_camera_focus_timer = duration
	if is_inside_tree():
		_update_camera_rig_transform()
	if _camera_request_id == -1:
		var cm: Node = get_node_or_null("/root/CinematicManager")
		if cm != null and cm.has_method("request_camera_mode") and is_instance_valid(_cam_rig):
			_camera_request_id = int(cm.request_camera_mode(
				CAMERA_CONTROL_MODE_LOCKED_VIEW,
				{
					"rig": _cam_rig,
					"transition_time": 0.6,
					"restore_view_on_exit": true,
					"latch_on_enter": true,
					"latch_on_exit": true
				},
				CAMERA_REQUEST_SOURCE,
				CAMERA_REQUEST_PRIORITY
			))


func release_camera() -> void:
	_camera_focus_timer = 0.0
	if _camera_request_id != -1:
		var cm: Node = get_node_or_null("/root/CinematicManager")
		if cm != null and cm.has_method("release_camera_request"):
			cm.release_camera_request(_camera_request_id)
		_camera_request_id = -1
	if is_instance_valid(_cam_node):
		_cam_node.current = false


func is_speaking() -> bool:
	return _state == State.FADE_IN or _state == State.ACTIVE


func get_state() -> int:
	return _state


func get_behavior_mode() -> int:
	return _behavior_mode


func get_camera_request_id() -> int:
	return _camera_request_id


func _ensure_visible_and_active() -> void:
	if _state == State.HIDDEN or _state == State.FADE_OUT:
		_fade_timer = 0.0
		_state = State.FADE_IN
		visible = true
		set_physics_process(true)
		if _override_anim == "":
			_update_locomotion_animation()
	else:
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _state == State.HIDDEN:
		set_physics_process(false)
		return

	_speech_elapsed += delta
	_update_behavior(delta)
	_update_locomotion_animation()
	_update_camera_focus(delta)
	_update_fade_state(delta)


func _update_behavior(delta: float) -> void:
	match _behavior_mode:
		BehaviorMode.APPEAR_SPEAK:
			_update_appear_speak_motion(delta)
		BehaviorMode.FOLLOW:
			_update_follow_motion(delta)
			if _follow_duration > 0.0:
				_follow_duration -= delta
				if _follow_duration <= 0.0:
					_follow_duration = -1.0
					disappear(false)
		BehaviorMode.MOVE_TO:
			_update_move_to_motion(delta, false)
		BehaviorMode.ORBIT_GUIDE:
			_update_orbit_guide_motion(delta, false)
		BehaviorMode.SCRIPTED:
			_update_scripted_behavior(delta)
		_:
			_horizontal_speed = 0.0


func _update_fade_state(delta: float) -> void:
	match _state:
		State.FADE_IN:
			_fade_timer += delta
			var t: float = clamp(_fade_timer / max(fade_in_duration, 0.01), 0.0, 1.0)
			var glitch: float = lerp(0.95, _base_glitch, t)
			_apply_holo_visibility(t, glitch)
			if t >= 1.0:
				_state = State.ACTIVE
		State.ACTIVE:
			_apply_holo_visibility(1.0, _base_glitch)
			if _behavior_mode == BehaviorMode.APPEAR_SPEAK:
				_remaining_sec -= delta
				if _remaining_sec <= 0.0:
					_state = State.FADE_OUT
					_fade_timer = 0.0
					emit_signal("speech_finished")
		State.FADE_OUT:
			_fade_timer += delta
			var t_out: float = clamp(_fade_timer / max(fade_out_duration, 0.01), 0.0, 1.0)
			var inv: float = 1.0 - t_out
			var glitch_out: float = lerp(_base_glitch, 0.95, t_out)
			_apply_holo_visibility(inv, glitch_out)
			if t_out >= 1.0:
				disappear(true)


func _update_appear_speak_motion(delta: float) -> void:
	_horizontal_speed = 0.0
	var viewer := _resolve_viewer()
	if is_instance_valid(viewer):
		var viewer_pos: Vector3 = viewer.global_transform.origin
		var flat_dist: float = Vector2(viewer_pos.x - _anchor_origin.x, viewer_pos.z - _anchor_origin.z).length()
		if flat_dist > max_follow_distance:
			var target_anchor := _compute_anchor_for_viewer(viewer)
			_anchor_origin = _anchor_origin.linear_interpolate(target_anchor, clamp(delta * follow_lerp_speed, 0.0, 1.0))

	_apply_hover_transform(delta, true)
	if is_instance_valid(viewer):
		_face_position(viewer.global_transform.origin, delta)


func _update_follow_motion(delta: float) -> void:
	var viewer := _resolve_viewer()
	if not is_instance_valid(viewer):
		_horizontal_speed = 0.0
		_apply_hover_transform(delta, true)
		return

	var target := _compute_follow_target_for_viewer(viewer)
	var dist: float = _anchor_origin.distance_to(target)
	if dist > 0.35:
		var spd: float = follow_catchup_speed if dist > max_follow_distance else follow_speed
		_horizontal_speed = _move_anchor_towards(target, spd, delta)
		_apply_hover_transform(delta, false)
	else:
		_horizontal_speed = 0.0
		_apply_hover_transform(delta, true)
		_face_position(viewer.global_transform.origin, delta)


func _update_move_to_motion(delta: float, from_script: bool) -> void:
	if _move_timeout > 0.0:
		_move_timeout -= delta
		if _move_timeout <= 0.0:
			_move_timeout = -1.0
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)
			if from_script:
				_start_next_script_step()
			return

	var dist: float = _anchor_origin.distance_to(_target_pos)
	if dist <= arrival_threshold:
		_anchor_origin = _target_pos
		_horizontal_speed = 0.0
		_apply_hover_transform(delta, true)
		if not _arrived_emitted:
			_arrived_emitted = true
			emit_signal("arrived", _target_pos)
		if from_script:
			_start_next_script_step()
		return

	_horizontal_speed = _move_anchor_towards(_target_pos, _move_speed, delta)
	_apply_hover_transform(delta, false)

	if _anchor_origin.distance_to(_target_pos) <= arrival_threshold:
		_anchor_origin = _target_pos
		_horizontal_speed = 0.0
		if not _arrived_emitted:
			_arrived_emitted = true
			emit_signal("arrived", _target_pos)
		if from_script:
			_start_next_script_step()


func _update_orbit_guide_motion(delta: float, from_script: bool) -> void:
	var viewer := _resolve_viewer()
	if is_instance_valid(viewer):
		var viewer_pos: Vector3 = viewer.global_transform.origin
		var flat_dist: float = Vector2(viewer_pos.x - _anchor_origin.x, viewer_pos.z - _anchor_origin.z).length()
		if not _guide_waiting and flat_dist > guide_wait_distance:
			_guide_waiting = true
		elif _guide_waiting and flat_dist <= guide_resume_distance:
			_guide_waiting = false

		if _guide_waiting:
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)
			_face_position(viewer_pos, delta)
			return
	else:
		_guide_waiting = false

	var dist: float = _anchor_origin.distance_to(_target_pos)
	if dist <= arrival_threshold:
		_anchor_origin = _target_pos
		_horizontal_speed = 0.0
		_apply_hover_transform(delta, true)
		if is_instance_valid(viewer):
			_face_position(viewer.global_transform.origin, delta)
		if not _arrived_emitted:
			_arrived_emitted = true
			emit_signal("arrived", _target_pos)
		if from_script:
			_start_next_script_step()
		return

	_horizontal_speed = _move_anchor_towards(_target_pos, _move_speed, delta)
	_apply_hover_transform(delta, false)

	if _anchor_origin.distance_to(_target_pos) <= arrival_threshold:
		_anchor_origin = _target_pos
		_horizontal_speed = 0.0
		if not _arrived_emitted:
			_arrived_emitted = true
			emit_signal("arrived", _target_pos)
		if from_script:
			_start_next_script_step()


func _update_scripted_behavior(delta: float) -> void:
	match _step_submode:
		"move_to":
			_update_move_to_motion(delta, true)
		"guide_to":
			_update_orbit_guide_motion(delta, true)
		"follow":
			_update_follow_motion(delta)
			if _step_timer > 0.0:
				_step_timer -= delta
				if _step_timer <= 0.0:
					_start_next_script_step()
		"anim":
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)
			if _step_timer > 0.0:
				_step_timer -= delta
				if _step_timer <= 0.0:
					_override_anim = ""
					_start_next_script_step()
		"say":
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)
			var viewer := _resolve_viewer()
			if is_instance_valid(viewer):
				_face_position(viewer.global_transform.origin, delta)
			if _step_timer > 0.0:
				_step_timer -= delta
				if _step_timer <= 0.0:
					emit_signal("speech_finished")
					_start_next_script_step()
		"wait":
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)
			if _step_timer > 0.0:
				_step_timer -= delta
				if _step_timer <= 0.0:
					_start_next_script_step()
		_:
			_horizontal_speed = 0.0
			_apply_hover_transform(delta, true)


func _start_next_script_step() -> void:
	while _script_index < _script_queue.size():
		var raw_step = _script_queue[_script_index]
		_script_index += 1
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		var action: String = str(step.get("action", ""))
		match action:
			"move_to":
				_target_pos = _parse_vec3(step.get("pos", _anchor_origin), _anchor_origin)
				_move_speed = max(float(step.get("speed", 4.5)), 0.1)
				_move_timeout = float(step.get("timeout", -1.0))
				_arrived_emitted = false
				_step_submode = "move_to"
				return
			"guide_to":
				_target_pos = _parse_vec3(step.get("pos", _anchor_origin), _anchor_origin)
				_move_speed = max(float(step.get("speed", 4.0)), 0.1)
				_guide_waiting = false
				_arrived_emitted = false
				_step_submode = "guide_to"
				return
			"follow":
				_step_timer = max(float(step.get("duration", 5.0)), 0.05)
				_step_submode = "follow"
				return
			"anim":
				var anim_name: String = str(step.get("name", ""))
				var blend: float = float(step.get("blend", 0.25))
				var dur: float = float(step.get("duration", -1.0))
				var played: bool = play_animation(anim_name, blend)
				if not played and dur <= 0.0:
					continue
				_step_timer = dur
				_step_submode = "anim"
				return
			"say":
				var text: String = str(step.get("text", ""))
				var dur_say: float = max(float(step.get("duration", 6.0)), 0.1)
				_show_subtitle(text, dur_say)
				_step_timer = dur_say
				_step_submode = "say"
				return
			"camera_focus":
				var dur_cam: float = float(step.get("duration", 3.0))
				var off_cam: Vector3 = _parse_vec3(step.get("offset", [0.0, 1.35, 2.2]), Vector3(0.0, 1.35, 2.2))
				focus_camera(dur_cam, off_cam)
				if bool(step.get("blocking", false)) and dur_cam > 0.0:
					_step_timer = dur_cam
					_step_submode = "wait"
					return
			"wait":
				var sec: float = float(step.get("sec", step.get("duration", 1.0)))
				if sec > 0.0:
					_step_timer = sec
					_step_submode = "wait"
					return
			"disappear":
				var imm: bool = bool(step.get("immediate", false))
				_script_queue.clear()
				_step_submode = ""
				_step_timer = -1.0
				disappear(imm)
				emit_signal("script_finished")
				return

	_script_queue.clear()
	_step_submode = ""
	_step_timer = -1.0
	emit_signal("script_finished")


func _show_subtitle(text: String, duration: float) -> void:
	if text == "" or not is_inside_tree():
		return
	var subtitles: Node = get_node_or_null("/root/SubtitlesOverlayManager")
	if subtitles != null and subtitles.has_method("show_subtitle"):
		subtitles.show_subtitle(tr(text), Color(0.55, 0.95, 1.0), duration)


static func _parse_vec3(raw_val, fallback: Vector3) -> Vector3:
	if typeof(raw_val) == TYPE_VECTOR3:
		return raw_val
	if typeof(raw_val) == TYPE_ARRAY:
		var arr: Array = raw_val
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback


func _move_anchor_towards(target: Vector3, speed: float, delta: float) -> float:
	var to_target: Vector3 = target - _anchor_origin
	var dist: float = to_target.length()
	if dist <= 0.0001:
		return 0.0
	var step: float = min(dist, speed * delta)
	var move_vec: Vector3 = to_target / dist * step
	_anchor_origin += move_vec
	var flat_dir: Vector3 = Vector3(move_vec.x, 0.0, move_vec.z)
	if flat_dir.length_squared() > 0.00001:
		_face_direction(flat_dir, delta)
	return Vector2(move_vec.x, move_vec.z).length() / max(delta, 0.0001)


func _apply_hover_transform(delta: float, with_sway: bool) -> void:
	if not is_inside_tree():
		return
	var bob_y: float = sin(_speech_elapsed * bob_speed) * bob_amplitude
	var desired_pos: Vector3 = _anchor_origin + Vector3.UP * bob_y
	if with_sway:
		var sway_x: float = sin(_speech_elapsed * sway_speed) * sway_amplitude
		var sway_z: float = cos(_speech_elapsed * depth_sway_speed) * depth_sway_amplitude
		desired_pos += _anchor_right * sway_x + _anchor_forward * sway_z
		global_transform.origin = global_transform.origin.linear_interpolate(desired_pos, clamp(delta * 8.0, 0.0, 1.0))
	else:
		global_transform.origin = global_transform.origin.linear_interpolate(desired_pos, clamp(delta * 16.0, 0.0, 1.0))


func _face_position(target_pos: Vector3, delta: float) -> void:
	if not is_inside_tree():
		return
	var to_target: Vector3 = target_pos - global_transform.origin
	to_target.y = 0.0
	_face_direction(to_target, delta)


func _face_direction(dir: Vector3, delta: float) -> void:
	if not is_instance_valid(_pivot):
		return
	var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 0.0005:
		var target_yaw: float = atan2(flat.x, flat.z)
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, target_yaw, clamp(delta * yaw_lerp_speed, 0.0, 1.0))


func _place_in_front_of_viewer(target_anchor: Spatial) -> void:
	var viewer: Spatial = target_anchor if is_instance_valid(target_anchor) else _resolve_viewer()
	if not is_instance_valid(viewer):
		_anchor_origin = global_transform.origin if is_inside_tree() else Vector3.ZERO
		_anchor_right = Vector3.RIGHT
		_anchor_forward = Vector3.FORWARD
		return

	_anchor_origin = _compute_anchor_for_viewer(viewer)
	if is_inside_tree():
		global_transform.origin = _anchor_origin
		if is_instance_valid(_pivot):
			var to_viewer: Vector3 = viewer.global_transform.origin - global_transform.origin
			to_viewer.y = 0.0
			if to_viewer.length_squared() > 0.001:
				_pivot.rotation.y = atan2(to_viewer.x, to_viewer.z)


func _compute_anchor_for_viewer(viewer: Spatial) -> Vector3:
	var cam: Camera = get_viewport().get_camera() if get_viewport() != null else null
	var basis_ref: Basis = cam.global_transform.basis if is_instance_valid(cam) else viewer.global_transform.basis
	var fwd: Vector3 = -basis_ref.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()
	var right: Vector3 = Vector3.UP.cross(-fwd).normalized()
	_anchor_forward = fwd
	_anchor_right = right
	var base_y: float = viewer.global_transform.origin.y + spawn_height_offset
	return Vector3(viewer.global_transform.origin.x, base_y, viewer.global_transform.origin.z) + fwd * spawn_distance + right * spawn_side_offset


func _compute_follow_target_for_viewer(viewer: Spatial) -> Vector3:
	var basis_ref: Basis = viewer.global_transform.basis
	var back: Vector3 = basis_ref.z
	back.y = 0.0
	if back.length_squared() < 0.001:
		back = Vector3.BACK
	else:
		back = back.normalized()
	var right: Vector3 = basis_ref.x
	right.y = 0.0
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	_anchor_forward = -back
	_anchor_right = right
	var base_y: float = viewer.global_transform.origin.y + follow_height_offset
	return Vector3(viewer.global_transform.origin.x, base_y, viewer.global_transform.origin.z) + back * follow_distance + right * follow_side_offset


func _resolve_viewer() -> Spatial:
	if is_instance_valid(_explicit_viewer):
		return _explicit_viewer
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		if node is Spatial and is_instance_valid(node):
			return node as Spatial
	var cam: Camera = get_viewport().get_camera() if get_viewport() != null else null
	if is_instance_valid(cam):
		return cam
	return null


func _play_entrance_or_idle() -> void:
	if not is_instance_valid(_anim_player):
		return
	if _anim_player.has_animation("Levitate Entrance") and not _entrance_played:
		_entrance_played = true
		_override_anim = "Levitate Entrance"
		_current_anim_name = "Levitate Entrance"
		_anim_player.play("Levitate Entrance")
		return
	_play_idle_loop()


func _play_idle_loop() -> void:
	var candidates: Array = ["Swim_Idle_Loop", "Idle_Loop", "Walk_Loop"] if _behavior_mode == BehaviorMode.APPEAR_SPEAK else ["Idle_Loop", "Swim_Idle_Loop", "Walk_Loop"]
	_play_first_available(candidates, 0.35)


func _update_locomotion_animation() -> void:
	if _override_anim != "" or not is_instance_valid(_anim_player):
		return
	var candidates: Array
	if _horizontal_speed >= sprint_speed_threshold:
		candidates = ["Sprint_Loop", "Jog_Fwd_Loop", "Walk_Loop"]
	elif _horizontal_speed >= jog_speed_threshold:
		candidates = ["Jog_Fwd_Loop", "Walk_Loop", "Sprint_Loop"]
	elif _horizontal_speed >= walk_speed_threshold:
		candidates = ["Walk_Loop", "Jog_Fwd_Loop", "Idle_Loop"]
	elif _behavior_mode == BehaviorMode.APPEAR_SPEAK:
		candidates = ["Swim_Idle_Loop", "Idle_Loop", "Walk_Loop"]
	else:
		candidates = ["Idle_Loop", "Swim_Idle_Loop", "Walk_Loop"]
	_play_first_available(candidates, 0.2)


func _play_first_available(candidates: Array, blend: float) -> void:
	if not is_instance_valid(_anim_player):
		return
	for anim_name in candidates:
		if _anim_player.has_animation(anim_name):
			if _anim_player.current_animation != anim_name or not _anim_player.is_playing():
				_current_anim_name = anim_name
				_anim_player.play(anim_name, blend)
			return


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == _override_anim:
		_override_anim = ""
	if _behavior_mode == BehaviorMode.SCRIPTED and _step_submode == "anim" and _step_timer <= 0.0:
		_start_next_script_step()
		return
	if _state != State.HIDDEN:
		_update_locomotion_animation()


func _update_camera_focus(delta: float) -> void:
	if _camera_focus_timer > 0.0:
		_camera_focus_timer -= delta
		if _camera_focus_timer <= 0.0:
			release_camera()
			return
	if _camera_request_id != -1 and is_inside_tree():
		_update_camera_rig_transform()


func _update_camera_rig_transform() -> void:
	if not is_instance_valid(_cam_rig) or not is_inside_tree():
		return
	var pivot_pos: Vector3 = _pivot.global_transform.origin if is_instance_valid(_pivot) else global_transform.origin
	var pivot_basis: Basis = _pivot.global_transform.basis if is_instance_valid(_pivot) else global_transform.basis
	var cam_pos: Vector3 = pivot_pos + pivot_basis.xform(_camera_focus_offset)
	var look_target: Vector3 = pivot_pos + Vector3(0.0, 1.35, 0.0)
	_cam_rig.global_transform.origin = cam_pos
	var dir: Vector3 = look_target - cam_pos
	if dir.length_squared() > 0.001:
		var dir_norm: Vector3 = dir.normalized()
		if abs(dir_norm.dot(Vector3.UP)) < 0.999:
			_cam_rig.look_at(look_target, Vector3.UP)


func _apply_holo_visibility(factor: float, glitch: float) -> void:
	var f: float = clamp(factor, 0.0, 1.0)
	if is_instance_valid(_holo_material):
		_holo_material.set_shader_param("alpha_scale", _base_alpha_scale * f)
		_holo_material.set_shader_param("min_alpha", _base_min_alpha * f)
		_holo_material.set_shader_param("emission_energy", _base_emission * f)
		_holo_material.set_shader_param("glitch_strength", glitch)
	if is_instance_valid(_omni_light):
		_omni_light.light_energy = _base_light_energy * f
