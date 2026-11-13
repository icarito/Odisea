extends Spatial
# OdiseaHologramV2
# NPC-holograma de Odisea (v1: aparición/desaparición con movimiento vivo de
# animación y luz diegética). Cuerpo visual reutilizado: Programmer.glb con el
# material holográfico (ProgrammerHoloShader/Material). Sin física ni colisión:
# es puramente decorativo.
# Scene-agnóstico: escucha la señal "said" de los nodos MachineLevel (bahía de
# máquinas) y aparece junto al jugador mientras Odisea habla; se desvanece al
# terminar el mensaje. El fade se maneja por ticks de física (determinista), no
# con Tween.

const PROGRAMMER_PACK := preload("res://models/Programmer.glb")
const HOLO_MAT := preload("res://core_v2/visual/ProgrammerHoloMaterial.tres")
const MACHINE_LEVEL_SCRIPT := preload("res://core_v2/props/machines/MachineLevel.gd")

export(float) var fade_in_sec := 0.4
export(float) var fade_out_sec := 0.5
export(float) var anchor_distance := 2.4
export(float) var anchor_height := 0.0
export(float) var light_energy_base := 0.55
export(bool) var face_camera := true

var _visual: Spatial = null
var _holo_mat: ShaderMaterial = null
var _anim_player: AnimationPlayer = null
var _light: OmniLight = null
var _alpha := 0.0
var _target_alpha := 0.0
var _hold_ticks := 0
var _active := false
var _levels := {} # instance_id -> MachineLevel conectado


func _ready() -> void:
	set_physics_process(true)
	var root := get_tree().root
	if not root.is_connected("child_entered_tree", self, "_on_scene_root_entered"):
		root.connect("child_entered_tree", self, "_on_scene_root_entered")
	_scan_and_connect(root)


func _on_scene_root_entered(node: Node) -> void:
	_scan_and_connect(node)


func _scan_and_connect(from: Node) -> void:
	var stack := [from]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n.get_script() == MACHINE_LEVEL_SCRIPT:
			_connect_level(n)
		for c in n.get_children():
			stack.push_back(c)


func _connect_level(level: Node) -> void:
	var id := level.get_instance_id()
	if _levels.has(id):
		return
	if not level.has_signal("said"):
		return
	level.connect("said", self, "_on_level_said")
	_levels[id] = level


func _on_level_said(_text: String, duration: float) -> void:
	show_holo(duration)


func show_holo(duration: float) -> void:
	_ensure_visual()
	_active = true
	_target_alpha = 1.0
	_hold_ticks = int(round(max(0.0, duration) * Engine.iterations_per_second))
	_place_near_player()
	_start_animation()
	if _visual != null:
		_visual.visible = true


func hide_holo() -> void:
	_active = false
	_target_alpha = 0.0
	_hold_ticks = 0
	if _anim_player != null:
		_anim_player.stop()


func is_holo_active() -> bool:
	return _active


func _ensure_visual() -> void:
	if _visual != null:
		return
	var inst = PROGRAMMER_PACK.instance()
	if inst == null:
		push_warning("OdiseaHologramV2: no se pudo instanciar Programmer.glb")
		return
	_visual = inst as Spatial
	_visual.name = "ProgrammerHoloVisual"
	_holo_mat = HOLO_MAT.duplicate() as ShaderMaterial
	var stack := [_visual]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance:
			(n as GeometryInstance).cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		if n is MeshInstance:
			(n as MeshInstance).material_override = _holo_mat
		if n is AnimationPlayer and _anim_player == null:
			_anim_player = n as AnimationPlayer
		for c in n.get_children():
			stack.push_back(c)
	add_child(_visual)
	_build_holo_light()
	_apply_alpha(0.0)
	_visual.visible = false


func _build_holo_light() -> void:
	_light = OmniLight.new()
	_light.name = "HoloLight"
	_light.light_color = Color(0.3, 0.9, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.translation = Vector3(0.0, 1.2, 0.0)
	_visual.add_child(_light)


func _place_near_player() -> void:
	if _visual == null:
		return
	# Preferir la cámara activa: el holograma aparece delante de lo que el jugador
	# está mirando. La Y usa la del jugador (o piso lógico) + anchor_height para no
	# quedar hundido/flotando en plataformas elevadas; el origen del mesh está en los pies.
	var players := get_tree().get_nodes_in_group("player")
	var ground_y := 0.0
	if not players.empty():
		var p = players[0]
		if is_instance_valid(p) and p is Spatial:
			ground_y = (p as Spatial).global_transform.origin.y
	var cam: Camera = get_viewport().get_camera()
	if cam != null:
		var fwd: Vector3 = -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = Vector3(0.0, 0.0, -1.0)
		else:
			fwd = fwd.normalized()
		var target: Vector3 = cam.global_transform.origin + fwd * anchor_distance
		target.y = ground_y + anchor_height
		_visual.global_transform = Transform(Basis.IDENTITY, target)
		_orient_to(face_camera, cam.global_transform.origin, target)
		return
	# Fallback sin cámara: junto al jugador, o punto fijo si no hay jugador.
	var pivot := Vector3(0.0, 0.6, -2.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	if not players.empty():
		var p2 = players[0]
		if is_instance_valid(p2) and p2 is Spatial:
			var p_sp: Spatial = p2
			pivot = p_sp.global_transform.origin
			var b := p_sp.global_transform.basis
			forward = -b.z
			forward.y = 0.0
			if forward.length() < 0.001:
				forward = Vector3(0.0, 0.0, -1.0)
			else:
				forward = forward.normalized()
	_visual.global_transform = Transform(Basis.IDENTITY, pivot + forward * anchor_distance + Vector3(0.0, anchor_height, 0.0))


func _orient_to(face: bool, camera_global_pos: Vector3, holo_pos: Vector3) -> void:
	if not face or _visual == null:
		return
	var dir := camera_global_pos - holo_pos
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_visual.look_at(holo_pos + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _hold_ticks > 0:
		_hold_ticks -= 1
		if _hold_ticks == 0 and _active:
			_active = false
			_target_alpha = 0.0
	if _alpha == _target_alpha:
		return
	var fade_sec := fade_in_sec if _target_alpha > _alpha else fade_out_sec
	var stepv := delta / max(0.01, fade_sec)
	if _target_alpha > _alpha:
		_alpha = min(_target_alpha, _alpha + stepv)
	else:
		_alpha = max(_target_alpha, _alpha - stepv)
	_apply_alpha(_alpha)


func _apply_alpha(a: float) -> void:
	if _holo_mat != null:
		_holo_mat.set_shader_param("fade_alpha", a)
	if _visual != null:
		_visual.visible = a > 0.001
	if _light != null:
		_light.light_energy = light_energy_base * a
		_light.visible = a > 0.001


func _start_animation() -> void:
	if _anim_player == null:
		return
	var names := _anim_player.get_animation_list()
	if names.has("Levitate Entrance"):
		if not _anim_player.is_connected("animation_finished", self, "_on_holo_anim_finished"):
			_anim_player.connect("animation_finished", self, "_on_holo_anim_finished")
		_anim_player.play("Levitate Entrance")
	else:
		_play_holo_idle()


func _play_holo_idle() -> void:
	if _anim_player == null:
		return
	var names := _anim_player.get_animation_list()
	if names.has("Levitate Idle"):
		_anim_player.play("Levitate Idle")
	elif names.has("Idle_Loop"):
		_anim_player.play("Idle_Loop")
	elif names.has("Swim_Idle_Loop"):
		_anim_player.play("Swim_Idle_Loop")


func _on_holo_anim_finished(anim_name: String) -> void:
	if anim_name == "Levitate Entrance":
		_play_holo_idle()
