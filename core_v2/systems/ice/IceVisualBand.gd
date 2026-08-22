extends Spatial
class_name IceVisualBand

# FD-051: capa VISUAL del hielo. Cabalga sobre `ice_height` y nunca lo alimenta de vuelta.
#
# CPUParticles en anillo (GLES2). El MultiMesh de GasParticleManager es demasiado
# caro para una banda que casi siempre está en la pared, fuera de plano. Si queda un
# hijo GasParticleManager se apaga: no simula ni dibuja.
#
# Arranca apagado. Solo emite cuando ice_height supera start_height, el mismo umbral
# que usa IceLevel para mostrar IceSurface / disparar IceCrackSound al subir.

export(float) var ring_radius := 28.0
export(bool) var follow_dome_profile := true
export(bool) var ring_only := false
export(float) var ring_thickness := 3.0
export(float) var particles_per_second := 45.0
export(float) var visible_arc_deg := 140.0
export(float) var line_noise := 0.6
export(float) var follow_lerp := 12.0
export(float) var frost_rise_speed := 0.35
export(float) var frost_lifetime := 0.55
export(float) var frost_scale := 5.5
export(float) var frost_scale_variance := 0.5
export(float) var wave_amplitude := 0.5
export(float) var wave_frequency := 5.0
export(float) var wave_speed := 0.6
export(float) var wall_climb_height := 3.2
export(float, 0.0, 1.0) var wall_emission_ratio := 0.32
export(float) var organic_drift_strength := 0.28
export(Color) var hot_color := Color(0.82, 0.95, 1.0, 0.9)
export(Color) var cool_color := Color(0.08, 0.32, 0.72, 0.72)
export(float) var temperature_variance := 0.85
export(float) var frost_animation_speed := 0.72
export(bool) var emit_center_column := false
export(float) var center_column_radius := 2.5
export(bool) var is_smoke_crown := false
export(float) var smoke_height_offset := 1.5
export(float) var smoke_ceiling_height := 27.5
export(float) var smoke_lateral_speed := 0.9
export(String, FILE, "*.png,*.tga,*.webp,*.jpg") var frost_atlas_path := ""

var _cpu: CPUParticles = null
var _manager: Node = null
var _ice_level: Node = null
var _target_height := 0.0
var _display_height := 0.0
var _height_initialized := false
var _visuals_active := false
var _applied_ring_radius := -1.0

func _ready() -> void:
	if Engine.editor_hint:
		return
	set_process(false)
	if OS.get_name() in ["Android", "iOS"]:
		particles_per_second *= 0.6
	_manager = get_node_or_null("GasParticleManager")
	_cpu = get_node_or_null("CPUParticles") as CPUParticles
	if _cpu == null:
		_cpu = _create_cpu_particles()
	_disable_legacy_manager()
	_configure_cpu()
	if _cpu != null:
		_cpu.emitting = false
	call_deferred("_connect_ice_level")

func is_visual_active() -> bool:
	return _visuals_active

func is_using_cpu_particles() -> bool:
	return _cpu != null

func _connect_ice_level() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("ice_level")
	if systems.empty():
		return
	_ice_level = systems[0]
	if not is_instance_valid(_ice_level):
		return
	if not _ice_level.is_connected("ice_height_changed", self, "_on_ice_height_changed"):
		var _err = _ice_level.connect("ice_height_changed", self, "_on_ice_height_changed")
	if _ice_level.has_signal("ice_visuals_reset") and not _ice_level.is_connected("ice_visuals_reset", self, "reset_visuals"):
		var _err_reset = _ice_level.connect("ice_visuals_reset", self, "reset_visuals")
	_target_height = float(_ice_level.ice_height)
	if not _height_initialized:
		_display_height = _target_height
		_height_initialized = true
	_sync_activation()

func _on_ice_height_changed(height: float) -> void:
	_target_height = height
	if not _height_initialized:
		_display_height = height
		_height_initialized = true
	_sync_activation()

func reset_visuals() -> void:
	if is_instance_valid(_ice_level):
		_target_height = float(_ice_level.ice_height)
	_display_height = _target_height
	_height_initialized = true
	if _cpu != null:
		_cpu.emitting = false
	_sync_activation()

func _ice_has_risen(height: float) -> bool:
	if not is_instance_valid(_ice_level):
		return false
	return height > float(_ice_level.start_height) + 0.001

func _sync_activation() -> void:
	var should: bool = _ice_has_risen(_target_height)
	if should == _visuals_active:
		if should:
			_update_cpu_pose(false)
		return
	_visuals_active = should
	set_process(should)
	if _cpu != null:
		if should:
			_update_cpu_pose(true)
		_cpu.emitting = should

func _process(delta: float) -> void:
	if Engine.editor_hint or _cpu == null or not _visuals_active:
		return
	if not is_instance_valid(_ice_level):
		_connect_ice_level()
		return
	_display_height = lerp(_display_height, _target_height, clamp(delta * follow_lerp, 0.0, 1.0))
	_update_cpu_pose(false)

func _effective_ring_radius() -> float:
	if follow_dome_profile and is_instance_valid(_ice_level) and _ice_level.has_method("get_surface_radius_at"):
		return _ice_level.get_surface_radius_at(_display_height)
	return ring_radius

func _update_cpu_pose(force_radius: bool) -> void:
	if _cpu == null:
		return
	var local_y: float = to_local(Vector3(0.0, _display_height, 0.0)).y
	if is_smoke_crown:
		local_y += smoke_height_offset
	_cpu.translation.y = local_y
	var radius: float = max(_effective_ring_radius(), 1.0)
	if force_radius or abs(radius - _applied_ring_radius) >= 0.75:
		_applied_ring_radius = radius
		_cpu.emission_shape = CPUParticles.EMISSION_SHAPE_RING
		_cpu.emission_ring_axis = Vector3.UP
		_cpu.emission_ring_radius = radius
		if is_smoke_crown:
			_cpu.emission_ring_inner_radius = 0.0
			_cpu.emission_ring_height = max(line_noise * 2.0, 1.2)
		elif ring_only:
			_cpu.emission_ring_inner_radius = max(radius - max(ring_thickness, 0.4), 0.0)
			_cpu.emission_ring_height = max(line_noise * 2.0, 0.4)
		else:
			var inner_ratio: float = lerp(0.72, 0.9, clamp(wall_emission_ratio, 0.0, 1.0))
			_cpu.emission_ring_inner_radius = radius * inner_ratio
			_cpu.emission_ring_height = max(wall_climb_height * 0.35, line_noise * 2.0)

func _disable_legacy_manager() -> void:
	if _manager == null:
		return
	_manager.set_physics_process(false)
	_manager.set_process(false)
	_manager.visible = false
	if _manager.has_method("clear_all"):
		_manager.clear_all()
	if _manager.get("distance_lod_enabled") != null:
		_manager.distance_lod_enabled = false
	if _manager.get("force_cpu_lod") != null:
		_manager.force_cpu_lod = false

func _atlas_path() -> String:
	if frost_atlas_path != "":
		return frost_atlas_path
	if _manager != null:
		var manager_atlas = _manager.get("default_atlas_path")
		if manager_atlas != null and String(manager_atlas) != "":
			return String(manager_atlas)
	if is_smoke_crown:
		return "res://assets/flipbook_particles/assets/smokes/smoke_01/textures/smoke_01.tga"
	return "res://assets/flipbook_particles/assets/smokes/smoke_02/textures/smoke_02.tga"

func _create_cpu_particles() -> CPUParticles:
	var cpu := CPUParticles.new()
	cpu.name = "CPUParticles"
	cpu.emitting = false
	add_child(cpu)
	return cpu

func _configure_cpu() -> void:
	if _cpu == null:
		return
	var amount: int = int(clamp(round(particles_per_second * max(frost_lifetime, 0.2)), 6, 48))
	_cpu.emitting = false
	_cpu.amount = amount
	_cpu.lifetime = max(frost_lifetime, 0.2)
	_cpu.lifetime_randomness = 0.3
	_cpu.explosiveness = 0.0
	_cpu.local_coords = not is_smoke_crown
	_cpu.cast_shadow = 0
	_cpu.flag_align_y = false
	_cpu.spread = 50.0 if is_smoke_crown else 16.0
	if is_smoke_crown:
		_cpu.direction = Vector3(0.0, 0.15, 0.0)
		_cpu.initial_velocity = max(smoke_lateral_speed, 0.08)
		_cpu.gravity = Vector3(0.0, -0.15, 0.0)
	else:
		_cpu.direction = Vector3.UP
		_cpu.initial_velocity = max(frost_rise_speed, 0.08)
		_cpu.gravity = Vector3(0.0, 0.12, 0.0)
	_cpu.initial_velocity_random = 0.4
	_cpu.scale_amount = max(frost_scale * 0.35, 0.4)
	_cpu.scale_amount_random = clamp(frost_scale_variance, 0.0, 1.0)
	_cpu.color = cool_color.linear_interpolate(hot_color, clamp(temperature_variance, 0.0, 1.0) * 0.5)
	_cpu.extra_cull_margin = 40.0
	if _cpu.mesh == null:
		var mat := SpatialMaterial.new()
		mat.flags_transparent = true
		mat.flags_unshaded = true
		mat.flags_do_not_receive_shadows = true
		mat.vertex_color_use_as_albedo = true
		mat.params_billboard_mode = SpatialMaterial.BILLBOARD_PARTICLES
		mat.particles_anim_h_frames = 8
		mat.particles_anim_v_frames = 8
		mat.particles_anim_loop = true
		var atlas = load(_atlas_path())
		if atlas:
			mat.albedo_texture = atlas
		mat.albedo_color = Color(1, 1, 1, 0.82)
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		quad.material = mat
		_cpu.mesh = quad
