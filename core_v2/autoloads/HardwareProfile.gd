extends Node

enum Profile {
	UNKNOWN = 0,
	LOW = 1,
	MEDIUM = 2,
	HIGH = 3,
	SUPERHIGH = 4
}

enum PlatformType {
	UNKNOWN = 0,
	SWITCH = 1,
	ANDROID = 2,
	IOS = 3,
	LINUX_ARM = 4,
	LINUX_X86 = 5,
	WINDOWS = 6,
	MACOS = 7,
	HTML5 = 8
}

const ANBERNIC_DEVICE_IDS := [
	"351",    
	"351v",   
	"351elec", 
	"rg351",
	"anbernic",
	"gameforce",
]

const RK3326_DEVICES := [
	"rk3326",
]

const S905_DEVICES := [
	"s905",
	"aml s905",
]
const LOW_END_RAM_CAP_GB := 1.0
const MEMORY_FALLBACK_TOTAL_GB := 8.0
const MEMORY_FALLBACK_AVAILABLE_GB := 4.0

var _detected_profile: int = Profile.UNKNOWN
var _detected_platform: int = PlatformType.UNKNOWN
var _detected_device_name := ""
var _processor_count := 0
var _is_weak_hardware := false
var _auto_detected := false
var _cached_memory_total_gb := MEMORY_FALLBACK_TOTAL_GB
var _profile_forced_by_env := false
var _manual_profile_override := false
var _auto_detected_profile: int = Profile.MEDIUM
var _profile_cycle_index := 0
var _web_adaptive_quality_enabled := false
var _web_runtime_sec := 0.0
var _web_fps_sample_accum := 0.0
var _web_fps_below_streak := 0
var _web_degrade_cooldown_sec := 0.0
var _fallback_sky = null
var _environment_resource_cache := {}
var _world_environment_refresh_queued := false
var _directional_lights_refresh_queued := false
var _fluorescent_lights_refresh_queued := false
var _sun_direction_sync_queued := false
var _directional_shadow_update_version := 0
var _fluorescent_shadow_update_version := 0
var _camera_range_refresh_queued := false
var _is_anbernic_target := false
var _hyper_low_mode := false

const WEB_TARGET_FPS := 30.0
const WEB_FPS_SAMPLE_INTERVAL_SEC := 1.0
const WEB_FPS_STREAK_TO_DEGRADE := 5
const WEB_FPS_WARMUP_SEC := 8.0
const WEB_DEGRADE_COOLDOWN_SEC := 12.0
const ADAPTIVE_PROFILE_ENV := "ODISEA_ADAPTIVE_PROFILE"
const ADAPTIVE_PROFILE_ENV_LEGACY := "ODISEA_WEB_ADAPTIVE_PROFILE"
const PROFILE_CYCLE_ACTION := "cycle_performance_profile"
const PROFILE_AUTO_SENTINEL := -1
const PROFILE_CYCLE_ORDER := [PROFILE_AUTO_SENTINEL, Profile.LOW, Profile.MEDIUM, Profile.HIGH]
const META_ORIGINAL_ENVIRONMENT := "__hp_original_environment"
const META_ORIGINAL_DIR_SHADOW := "__hp_original_dir_shadow_enabled"
const META_ORIGINAL_DIR_SHADOW_MODE := "__hp_original_dir_shadow_mode"
const META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE := "__hp_original_dir_shadow_max_distance"
const META_ORIGINAL_DIR_SHADOW_BLEND_SPLITS := "__hp_original_dir_shadow_blend_splits"
const META_ORIGINAL_FLUOR_SHADOW := "__hp_original_fluor_shadow_enabled"
const META_PROFILED_ENV_KEY := "__hp_profiled_env_key"
const META_PROFILED_ENV_PATH := "__hp_profiled_env_path"
const META_RUNTIME_ENV_INSTANCE := "__hp_runtime_env_instance"
const META_ORIGINAL_ENV_GLOW_ENABLED := "__hp_original_env_glow_enabled"
const META_ORIGINAL_ENV_SSAO_ENABLED := "__hp_original_env_ssao_enabled"
const META_ORIGINAL_ENV_DOF_NEAR_ENABLED := "__hp_original_env_dof_near_enabled"
const META_ORIGINAL_ENV_DOF_FAR_ENABLED := "__hp_original_env_dof_far_enabled"
const META_ORIGINAL_ENV_ADJUSTMENT_ENABLED := "__hp_original_env_adjustment_enabled"
const META_ORIGINAL_CAMERA_FAR := "__hp_original_camera_far"
const FLUORESCENT_SCRIPT_PATH := "res://core_v2/props/scifi_lights/FluorescentLight.gd"
const LOW_NO_SHADOW_ENV_BRIGHTNESS := 0.5
const FALLBACK_SPACE_COLOR := Color(0.0, 0.0, 0.01, 1.0)
const DEFAULT_WORLD_ENV_PATH := "res://scenes/common/space_environment/Environment_ExteriorSpace.tres"
const PROFILED_ENV_INTERIOR_WIDE := "interior_wide"
const INTERIOR_WIDE_ENV_HIGH_PATH := "res://scenes/common/space_environment/Environment_InteriorWide.tres"
const INTERIOR_WIDE_ENV_MEDIUM_PATH := "res://scenes/common/space_environment/Environment_InteriorWideMedium.tres"
const INTERIOR_WIDE_ENV_LOW_PATH := "res://scenes/common/space_environment/Environment_InteriorWideLow.tres"
const DIRECTIONAL_SHADOW_POLICY_OFF := 0
const DIRECTIONAL_SHADOW_POLICY_REDUCED := 1
const DIRECTIONAL_SHADOW_POLICY_RESTORE := 2
const DIRECTIONAL_SHADOW_BATCH_SIZE := 10
const FLUORESCENT_SHADOW_BATCH_SIZE := 24
const HYPER_LOW_CAMERA_FAR_CLAMP := 180.0
const HYPER_LOW_CAMERA_FAR_MIN := 35.0
const HYPER_LOW_TARGET_FPS := 30

signal profile_changed(new_profile)
signal platform_detected(platform_type, device_name)

func _ready() -> void:
	_detect_hardware()
	_apply_environment_overrides()
	_configure_web_adaptive_quality()
	_connect_runtime_signals()
	_register_profile_cycle_action()
	_sync_optional_nodes_for_profile()
	_sync_world_environment_for_profile()
	_sync_camera_ranges_for_profile()
	_sync_directional_lights_for_profile()
	_sync_fluorescent_lights_for_profile()
	_sync_procedural_sun_direction()
	_refresh_web_adaptive_process_state()
	set_process_input(true)

func _process(delta: float) -> void:
	if not _web_adaptive_quality_enabled:
		return
	_monitor_web_runtime_performance(delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(PROFILE_CYCLE_ACTION):
		cycle_profile_mode()

func _detect_hardware() -> void:
	_processor_count = OS.get_processor_count()
	var mem_info = _get_memory_info()
	_cached_memory_total_gb = float(mem_info.total_gb)
	var os_name = OS.get_name()
	
	# Check environment variable for device override (e.g., ODISEA_DEVICE=anbernic)
	var forced_device = OS.get_environment("ODISEA_DEVICE").to_lower().strip_edges()
	if forced_device != "":
		_detected_device_name = forced_device
		if forced_device in ["anbernic", "351", "rg351", "rk3326"]:
			_apply_low_end_memory_cap()
			_detected_platform = PlatformType.LINUX_ARM
			_detected_profile = Profile.LOW
			_is_anbernic_target = _contains_any_hint(forced_device, ANBERNIC_DEVICE_IDS)
			_detected_device_name = "Anbernic " + forced_device
			_is_weak_hardware = true
			_auto_detected = true
			_refresh_hyper_low_state()
			emit_signal("platform_detected", _detected_platform, _detected_device_name)
			print("[HardwareProfile] Forced device: %s, Profile: LOW" % forced_device)
			if _hyper_low_mode:
				print("[HardwareProfile] Hyper-low mode enabled for Anbernic device override.")
			return
	
	match os_name:
		"Switch":
			_detected_platform = PlatformType.SWITCH
			_detected_device_name = "Nintendo Switch"
			_detected_profile = Profile.LOW
			_auto_detected = true
		"Android":
			_detected_platform = PlatformType.ANDROID
			_detected_device_name = _detect_android_model()
			_detected_profile = _estimate_android_profile()
			_auto_detected = true
		"iOS":
			_detected_platform = PlatformType.IOS
			_detected_device_name = OS.get_model_name()
			_detected_profile = _estimate_ios_profile()
			_auto_detected = true
		"Linux", "X11", "Server":
			_detected_platform = _detect_linux_platform()
			_auto_detected = true
		"Windows":
			_detected_platform = PlatformType.WINDOWS
			_detected_device_name = "Windows PC"
			_detected_profile = Profile.HIGH
			_auto_detected = true
		"OSX":
			_detected_platform = PlatformType.MACOS
			_detected_device_name = OS.get_model_name()
			_detected_profile = Profile.HIGH
			_auto_detected = true
		"HTML5":
			_detected_platform = PlatformType.HTML5
			_detected_device_name = "Web Browser"
			_detected_profile = _estimate_html5_profile()
			_auto_detected = true
		_:
			_detected_platform = PlatformType.UNKNOWN
			_detected_device_name = "Unknown"
			_detected_profile = Profile.MEDIUM
	
	_is_weak_hardware = _detect_weak_hardware()
	_detected_profile = _sanitize_profile(_detected_profile)
	_auto_detected_profile = _detected_profile
	_refresh_hyper_low_state()
	
	emit_signal("platform_detected", _detected_platform, _detected_device_name)
	print("[HardwareProfile] Detected: %s (%s), Profile: %s, Cores: %d, RAM: %.1fGB, Weak: %s" % [
		_detected_device_name, 
		PlatformType.keys()[_detected_platform],
		Profile.keys()[_detected_profile],
		_processor_count,
		_cached_memory_total_gb,
		_is_weak_hardware
	])
	if _hyper_low_mode:
		print("[HardwareProfile] Hyper-low mode enabled (Anbernic).")

func _detect_linux_platform() -> int:
	var device_info = _get_linux_device_info()
	_detected_device_name = device_info.model
	
	if _is_anbernic_device(device_info):
		_is_anbernic_target = true
		_apply_low_end_memory_cap()
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _is_rk3326_device(device_info):
		_apply_low_end_memory_cap()
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _is_s905_device(device_info):
		_apply_low_end_memory_cap()
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _has_mali_gpu(device_info):
		_apply_low_end_memory_cap()
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	# ARM Linux defaults to conservative profiles.
	if device_info.is_arm:
		if _processor_count <= 4:
			_detected_profile = Profile.LOW
		else:
			_detected_profile = Profile.MEDIUM
		return PlatformType.LINUX_ARM
	
	if device_info.is_arm64:
		if _processor_count <= 4:
			_detected_profile = _estimate_low_end_arm64_profile()
		elif _processor_count <= 8:
			_detected_profile = Profile.MEDIUM
		else:
			_detected_profile = Profile.HIGH
		return PlatformType.LINUX_ARM
	
	_detected_profile = _estimate_linux_x86_profile()
	return PlatformType.LINUX_X86

const MALI_GPU_IDS := [
	"mali",
	"mali-t", 
	"mali-g",
	"mali-4",
	"mali-3"
]

func _get_linux_device_info() -> Dictionary:
	var info := {
		"model": "Generic Linux",
		"cpu_model": "",
		"is_arm": false,
		"is_arm64": false,
		"board": "",
		"hardware": "",
		"gpu": ""
	}
	
	var file := File.new()
	
	if file.file_exists("/proc/cpuinfo"):
		if file.open("/proc/cpuinfo", File.READ) == OK:
			var content := file.get_as_text()
			file.close()
			
			var lines = content.split("\n")
			for line in lines:
				if line.begins_with("model name"):
					info.cpu_model = line.split(":", false, 1)[-1].strip_edges()
				elif line.begins_with("Hardware"):
					info.hardware = line.split(":", false, 1)[-1].strip_edges()
				elif line.begins_with("Board"):
					info.board = line.split(":", false, 1)[-1].strip_edges()
				elif line.begins_with("model"):
					var parts = line.split(":", false, 1)
					if parts.size() > 1:
						var model_str = parts[-1].strip_edges()
						if not " Raspberry" in model_str and not "ODROID" in model_str:
							info.model = model_str
			
			var lower_content = content.to_lower()
			info.is_arm64 = "aarch64" in lower_content or "arm64" in lower_content
			info.is_arm = ("arm" in lower_content or "tegra" in lower_content) and not info.is_arm64
			
			for line in lines:
				if line.begins_with("Features") or line.begins_with("flags"):
					var lower_line = line.to_lower()
					if "mali" in lower_line:
						info.gpu = "mali"
					break
			
			if info.cpu_model == "":
				for line in lines:
					if line.begins_with("Processor") or line.begins_with("CPU implementer"):
						info.cpu_model = line.split(":", false, 1)[-1].strip_edges()
						break
	
	if file.file_exists("/sys/firmware/devicetree/base/model"):
		if file.open("/sys/firmware/devicetree/base/model", File.READ) == OK:
			var model = file.get_line()
			file.close()
			if model != "":
				info.model = model
	
	if file.file_exists("/sys/devices/virtual/dmi/id/product_name"):
		if file.open("/sys/devices/virtual/dmi/id/product_name", File.READ) == OK:
			var product = file.get_line()
			file.close()
			if product != "":
				info.model = product
	
	if file.file_exists("/sys/class/drm/card0/device/model"):
		if file.open("/sys/class/drm/card0/device/model", File.READ) == OK:
			var gpu_model = file.get_line()
			file.close()
			if gpu_model != "":
				info.gpu = gpu_model
	
	return info

func _is_anbernic_device(info: Dictionary) -> bool:
	var model_lower = info.model.to_lower()
	var hardware_lower = info.hardware.to_lower()
	var cpu_lower = info.cpu_model.to_lower()
	
	for anbernic_id in ANBERNIC_DEVICE_IDS:
		if anbernic_id in model_lower or anbernic_id in hardware_lower:
			return true
	
	if "rockchip" in hardware_lower or "rk3326" in cpu_lower:
		if "351" in model_lower or "rg351" in model_lower:
			return true
	
	return false

func _is_rk3326_device(info: Dictionary) -> bool:
	var hardware_lower = info.hardware.to_lower()
	var cpu_lower = info.cpu_model.to_lower()
	
	for rk_id in RK3326_DEVICES:
		if rk_id in hardware_lower or rk_id in cpu_lower:
			return true
	
	return false

func _is_s905_device(info: Dictionary) -> bool:
	var hardware_lower = info.hardware.to_lower()
	var cpu_lower = info.cpu_model.to_lower()
	
	for s905_id in S905_DEVICES:
		if s905_id in hardware_lower or s905_id in cpu_lower:
			return true
	
	return false

func _has_mali_gpu(info: Dictionary) -> bool:
	var gpu_lower = info.gpu.to_lower()
	var hardware_lower = info.hardware.to_lower()
	var model_lower = info.model.to_lower()
	
	for mali_id in MALI_GPU_IDS:
		if mali_id in gpu_lower or mali_id in hardware_lower or mali_id in model_lower:
			return true
	
	return false

func _contains_any_hint(text: String, hints: Array) -> bool:
	if text == "":
		return false
	var lower = text.to_lower()
	for raw_hint in hints:
		var hint = String(raw_hint).strip_edges().to_lower()
		if hint != "" and lower.find(hint) != -1:
			return true
	return false

func _estimate_low_end_arm64_profile() -> int:
	if _processor_count <= 4:
		return Profile.LOW
	
	if _processor_count <= 6:
		return Profile.LOW
	
	var mem_info = _get_memory_info()
	if mem_info.total_gb <= 2.0:
		return Profile.LOW
	elif mem_info.total_gb <= 4.0:
		return Profile.MEDIUM
	
	return Profile.MEDIUM

func _estimate_linux_x86_profile() -> int:
	var mem_info = _get_memory_info()
	var total_gb = float(mem_info.total_gb)
	_cached_memory_total_gb = total_gb
	
	if _processor_count >= 16 and total_gb >= 24.0:
		return Profile.SUPERHIGH
	if _processor_count >= 8 and total_gb >= 12.0:
		return Profile.HIGH
	if _processor_count >= 6 and total_gb >= 8.0:
		return Profile.HIGH
	if _processor_count >= 4 and total_gb >= 4.0:
		return Profile.MEDIUM
	return Profile.LOW

func _get_memory_info() -> Dictionary:
	var info := {
		"total_gb": MEMORY_FALLBACK_TOTAL_GB,
		"available_gb": MEMORY_FALLBACK_AVAILABLE_GB
	}
	var file := File.new()
	
	if file.file_exists("/proc/meminfo"):
		if file.open("/proc/meminfo", File.READ) == OK:
				var content := file.get_as_text()
				file.close()
				
				var lines = content.split("\n")
				for line in lines:
					if line.begins_with("MemTotal"):
						var parts = line.split(":")
						if parts.size() > 1:
							var kb = _parse_first_int(parts[-1].strip_edges())
							if kb > 0:
								info.total_gb = kb / 1024.0 / 1024.0
							break
		
	return info

func _apply_low_end_memory_cap() -> void:
	if _cached_memory_total_gb <= 0.0:
		_cached_memory_total_gb = LOW_END_RAM_CAP_GB
	elif _cached_memory_total_gb > LOW_END_RAM_CAP_GB:
		_cached_memory_total_gb = LOW_END_RAM_CAP_GB

func _parse_first_int(raw: String) -> int:
	var digits := ""
	for i in range(raw.length()):
		var ch = raw.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	if digits == "":
		return 0
	return int(digits)

func _detect_android_model() -> String:
	var model = OS.get_model_name()
	if model == "GenericDevice" or model == "":
		var file := File.new()
		if file.file_exists("/sys/firmware/devicetree/base/model"):
			if file.open("/sys/firmware/devicetree/base/model", File.READ) == OK:
				model = file.get_line()
				file.close()
	return model if model != "" else "Unknown Android"

func _estimate_android_profile() -> int:
	var model = OS.get_model_name().to_lower()
	
	if "switch" in model:
		return Profile.LOW
	
	if _processor_count <= 4:
		return Profile.LOW
	
	var mem_info = _get_memory_info()
	if mem_info.total_gb <= 2.0:
		return Profile.LOW
	
	return Profile.MEDIUM

func _estimate_ios_profile() -> int:
	var device = OS.get_model_name()
	
	if device in ["iPhone", "iPad"]:
		return Profile.MEDIUM
	
	return Profile.HIGH

func _estimate_html5_profile() -> int:
	# On web we keep MEDIUM as the lowest automatic floor so assets/materials stay intact.
	if _has_strong_weak_indicators_for_html5():
		return Profile.MEDIUM
	return Profile.HIGH

func _detect_weak_hardware() -> bool:
	if _detected_platform == PlatformType.SWITCH:
		return true
	
	if _detected_platform == PlatformType.LINUX_ARM and _detected_profile == Profile.LOW:
		return true
	
	if _detected_platform == PlatformType.ANDROID and _processor_count <= 4:
		return true
	
	if _detected_platform == PlatformType.HTML5:
		# Web MEDIUM should keep full assets/materials; reserve "weak" only for explicit LOW.
		return _detected_profile <= Profile.LOW
	
	if _detected_platform == PlatformType.IOS:
		return false
	
	if _processor_count <= 2:
		return true
	
	var mem_info = _get_memory_info()
	if mem_info.total_gb <= 2.0:
		return true
	
	return false

func _apply_environment_overrides() -> void:
	var profile_env = OS.get_environment("ODISEA_GRAPHICS_PROFILE").to_lower()
	match profile_env:
		"low", "min", "1":
			_profile_forced_by_env = true
			set_profile(Profile.LOW)
		"medium", "med", "2":
			_profile_forced_by_env = true
			set_profile(Profile.MEDIUM)
		"high", "3":
			_profile_forced_by_env = true
			set_profile(Profile.HIGH)
		"superhigh", "max", "4":
			_profile_forced_by_env = true
			set_profile(Profile.SUPERHIGH)

	_apply_frame_pacing_policy()
	
	var force_optional = OS.get_environment("ODISEA_FORCE_OPTIONAL_NODES").to_lower()
	call_deferred("_apply_optional_override", force_optional)

func _apply_frame_pacing_policy() -> void:
	var vsync_env := OS.get_environment("ODISEA_VSYNC").to_lower().strip_edges()
	var target_fps_env := OS.get_environment("ODISEA_TARGET_FPS").strip_edges()

	if _hyper_low_mode:
		if vsync_env in ["off", "0", "false", "no"]:
			OS.set_use_vsync(false)
			print("[HardwareProfile] Hyper-low frame pacing: VSync forced OFF by env override.")
		else:
			OS.set_use_vsync(true)
			print("[HardwareProfile] Hyper-low frame pacing: VSync enabled.")

		var hyper_low_target_fps := HYPER_LOW_TARGET_FPS
		if target_fps_env.is_valid_integer():
			hyper_low_target_fps = max(0, int(target_fps_env))
		Engine.target_fps = hyper_low_target_fps
		print("[HardwareProfile] Hyper-low frame pacing: target_fps=%d" % hyper_low_target_fps)
		return

	if target_fps_env.is_valid_integer():
		var env_target_fps := max(0, int(target_fps_env))
		Engine.target_fps = env_target_fps
		print("[HardwareProfile] Frame pacing: target_fps set by env=%d" % env_target_fps)
	else:
		if int(Engine.target_fps) != 0:
			Engine.target_fps = 0
			print("[HardwareProfile] Frame pacing: target_fps reset to uncapped (0).")

	if vsync_env in ["on", "1", "true", "yes"]:
		OS.set_use_vsync(true)
		print("[HardwareProfile] VSync enabled by env override.")
		return

	# Legacy default: disable on LOW unless explicitly forced on.
	if vsync_env in ["off", "0", "false", "no"] or _detected_profile == Profile.LOW:
		OS.set_use_vsync(false)
		print("[HardwareProfile] VSync disabled.")

func get_frame_pacing_summary() -> Dictionary:
	return {
		"vsync": bool(OS.is_vsync_enabled()),
		"target_fps": int(Engine.target_fps)
	}

func _apply_optional_override(force_optional: String) -> void:
	var opt_manager = get_tree().root.get_node_or_null("OptionalNodeManager")
	if opt_manager:
		if force_optional in ["1", "true", "yes", "on"]:
			opt_manager.set_optional_nodes_enabled(true)
		elif force_optional in ["0", "false", "no", "off"]:
			opt_manager.set_optional_nodes_enabled(false)

func set_profile(new_profile: int) -> void:
	var normalized_profile = _sanitize_profile(new_profile)
	if normalized_profile != _detected_profile:
		_detected_profile = normalized_profile
		_is_weak_hardware = _detect_weak_hardware()
		_refresh_hyper_low_state()
		_apply_frame_pacing_policy()
		_sync_optional_nodes_for_profile()
		_sync_world_environment_for_profile()
		_sync_camera_ranges_for_profile()
		_sync_directional_lights_for_profile()
		_sync_fluorescent_lights_for_profile()
		_sync_procedural_sun_direction()
		emit_signal("profile_changed", _detected_profile)
		print("[HardwareProfile] Profile changed to: %s" % Profile.keys()[_detected_profile])

func get_profile() -> int:
	return _detected_profile

func get_platform() -> int:
	return _detected_platform

func get_device_name() -> String:
	return _detected_device_name

func get_processor_count() -> int:
	return _processor_count

func is_weak_hardware() -> bool:
	return _is_weak_hardware

func is_platform(platform: int) -> bool:
	return _detected_platform == platform

func get_profile_name() -> String:
	if _detected_profile < 0 or _detected_profile >= Profile.keys().size():
		return "UNKNOWN"
	return Profile.keys()[_detected_profile]

func get_effective_profile_name() -> String:
	if _hyper_low_mode:
		return "HYPER_LOW"
	return get_profile_name()

func is_hyper_low_mode() -> bool:
	return _hyper_low_mode

func get_platform_name() -> String:
	if _detected_platform < 0 or _detected_platform >= PlatformType.keys().size():
		return "UNKNOWN"
	return PlatformType.keys()[_detected_platform]

func get_total_memory_gb() -> float:
	return _cached_memory_total_gb

func is_switch() -> bool:
	return _detected_platform == PlatformType.SWITCH

func is_android() -> bool:
	return _detected_platform == PlatformType.ANDROID

func is_linux_arm() -> bool:
	return _detected_platform == PlatformType.LINUX_ARM

func is_linux_handheld() -> bool:
	if _detected_platform != PlatformType.LINUX_ARM:
		return false
	return _is_anbernic_device(_get_linux_device_info())

func profile_at_least(min_profile: int) -> bool:
	return _detected_profile >= min_profile

func should_use_cheap_shadows() -> bool:
	var shadow_mode = _get_shadow_mode_override()
	if shadow_mode == "cheap":
		return true
	if shadow_mode == "full":
		return false
	return _detected_profile <= Profile.LOW

func should_use_reduced_particles() -> bool:
	return _detected_profile <= Profile.LOW

func should_use_reduced_lights() -> bool:
	return _detected_profile <= Profile.MEDIUM

func get_shadow_update_interval() -> int:
	var shadow_mode = _get_shadow_mode_override()
	if shadow_mode == "cheap":
		return 6
	if shadow_mode == "full":
		return 1
	match _detected_profile:
		Profile.LOW:
			return 6
		Profile.MEDIUM:
			return 4
		Profile.HIGH:
			return 2
		Profile.SUPERHIGH:
			return 1
	return 3

func get_shadow_grid_resolution() -> int:
	var shadow_mode = _get_shadow_mode_override()
	if shadow_mode == "cheap":
		return 8
	if shadow_mode == "full":
		return 28
	match _detected_profile:
		Profile.LOW:
			return 8
		Profile.MEDIUM:
			return 12
		Profile.HIGH:
			return 20
		Profile.SUPERHIGH:
			return 28
	return 16

func get_shadow_policy_summary() -> Dictionary:
	return {
		"mode": _get_shadow_mode_override(),
		"cheap_shadows": should_use_cheap_shadows(),
		"update_interval": get_shadow_update_interval(),
		"grid_resolution": get_shadow_grid_resolution()
	}

func _get_shadow_mode_override() -> String:
	var mode_env = OS.get_environment("ODISEA_SHADOW_MODE").to_lower().strip_edges()
	match mode_env:
		"0", "off", "false", "cheap", "low":
			return "cheap"
		"1", "on", "true", "full", "high":
			return "full"
	return "auto"

func _configure_web_adaptive_quality() -> void:
	if _detected_platform == PlatformType.HTML5:
		_web_adaptive_quality_enabled = false
		print("[HardwareProfile] Adaptive quality disabled for HTML5.")
		_refresh_web_adaptive_process_state()
		return
	if _profile_forced_by_env:
		_web_adaptive_quality_enabled = false
		print("[HardwareProfile] Adaptive quality disabled (profile forced by env).")
		_refresh_web_adaptive_process_state()
		return
	var env_value = OS.get_environment(ADAPTIVE_PROFILE_ENV).to_lower().strip_edges()
	if env_value == "":
		env_value = OS.get_environment(ADAPTIVE_PROFILE_ENV_LEGACY).to_lower().strip_edges()
	if env_value in ["0", "false", "no", "off"]:
		_web_adaptive_quality_enabled = false
	elif env_value in ["1", "true", "yes", "on"]:
		_web_adaptive_quality_enabled = true
	else:
		_web_adaptive_quality_enabled = _is_adaptive_profile_supported_by_default()
	print("[HardwareProfile] Adaptive quality: %s (platform=%s)" % [
		"ENABLED" if _web_adaptive_quality_enabled else "DISABLED",
		get_platform_name()
	])
	_refresh_web_adaptive_process_state()

func _is_adaptive_profile_supported_by_default() -> bool:
	match _detected_platform:
		PlatformType.HTML5, PlatformType.LINUX_X86, PlatformType.WINDOWS, PlatformType.MACOS:
			return true
	return false

func _register_profile_cycle_action() -> void:
	if not InputMap.has_action(PROFILE_CYCLE_ACTION):
		InputMap.add_action(PROFILE_CYCLE_ACTION)
	if InputMap.get_action_list(PROFILE_CYCLE_ACTION).empty():
		push_warning("[HardwareProfile] Input action '%s' has no key bound in InputMap." % PROFILE_CYCLE_ACTION)

func _refresh_web_adaptive_process_state() -> void:
	var adaptive_active = _web_adaptive_quality_enabled and not _manual_profile_override
	set_process(adaptive_active)

func _reset_web_adaptive_counters() -> void:
	_web_runtime_sec = 0.0
	_web_fps_sample_accum = 0.0
	_web_fps_below_streak = 0
	_web_degrade_cooldown_sec = 0.0

func _resolve_auto_profile() -> int:
	if _auto_detected_profile > Profile.UNKNOWN:
		return _sanitize_profile(_auto_detected_profile)
	if _detected_profile > Profile.UNKNOWN:
		return _sanitize_profile(_detected_profile)
	return Profile.MEDIUM

func _sanitize_profile(profile: int) -> int:
	if profile <= Profile.UNKNOWN:
		return Profile.MEDIUM
	return int(clamp(profile, Profile.LOW, Profile.HIGH))

func cycle_profile_mode() -> void:
	if _profile_forced_by_env:
		_notify_profile_selection("Perfil bloqueado por ODISEA_GRAPHICS_PROFILE")
		return
	_profile_cycle_index = (_profile_cycle_index + 1) % PROFILE_CYCLE_ORDER.size()
	var selection = int(PROFILE_CYCLE_ORDER[_profile_cycle_index])
	if selection == PROFILE_AUTO_SENTINEL:
		_manual_profile_override = false
		set_profile(_resolve_auto_profile())
	else:
		_manual_profile_override = true
		set_profile(selection)
	_refresh_web_adaptive_process_state()
	_reset_web_adaptive_counters()
	_notify_profile_selection(_profile_selection_message(selection))

func _profile_selection_message(selection: int) -> String:
	if selection == PROFILE_AUTO_SENTINEL:
		return "Perfil de performance: AUTO (%s)" % Profile.keys()[_detected_profile]
	return "Perfil de performance: %s (manual)" % Profile.keys()[selection]

func _notify_profile_selection(message: String) -> void:
	print("[OYS PRINT] ", message)
	var subtitles = get_node_or_null("/root/SubtitlesOverlayManager")
	if subtitles and subtitles.has_method("show_subtitle"):
		subtitles.show_subtitle(message, Color(0.65, 0.95, 1.0), 2.6)

func _monitor_web_runtime_performance(delta: float) -> void:
	_web_runtime_sec += delta
	_web_fps_sample_accum += delta
	if _web_degrade_cooldown_sec > 0.0:
		_web_degrade_cooldown_sec = max(0.0, _web_degrade_cooldown_sec - delta)
	if _web_runtime_sec < WEB_FPS_WARMUP_SEC:
		return
	if _web_fps_sample_accum < WEB_FPS_SAMPLE_INTERVAL_SEC:
		return
	_web_fps_sample_accum = 0.0
	var fps = float(Performance.get_monitor(Performance.TIME_FPS))
	if fps < WEB_TARGET_FPS:
		_web_fps_below_streak += 1
	else:
		_web_fps_below_streak = 0
	if _web_fps_below_streak >= WEB_FPS_STREAK_TO_DEGRADE and _web_degrade_cooldown_sec <= 0.0:
		_degrade_web_profile_due_to_fps(fps)

func _degrade_web_profile_due_to_fps(observed_fps: float) -> void:
	if _detected_platform == PlatformType.HTML5:
		_web_fps_below_streak = 0
		_web_degrade_cooldown_sec = 0.0
		return
	var min_profile = Profile.MEDIUM if _detected_platform == PlatformType.HTML5 else Profile.LOW
	if _detected_profile <= min_profile:
		_web_fps_below_streak = 0
		_web_degrade_cooldown_sec = WEB_DEGRADE_COOLDOWN_SEC
		return
	var prev_profile = _detected_profile
	var next_profile = max(min_profile, prev_profile - 1)
	print("[HardwareProfile] Web FPS %.1f < %.1f sustained. Lowering profile: %s -> %s" % [
		observed_fps,
		WEB_TARGET_FPS,
		Profile.keys()[prev_profile],
		Profile.keys()[next_profile]
	])
	set_profile(next_profile)
	_web_fps_below_streak = 0
	_web_degrade_cooldown_sec = WEB_DEGRADE_COOLDOWN_SEC

func _has_strong_weak_indicators_for_html5() -> bool:
	var weak_env = OS.get_environment("ODISEA_WEB_WEAK_DEVICE").to_lower().strip_edges()
	if weak_env in ["1", "true", "yes", "on"]:
		return true
	if _processor_count <= 2:
		return true
	if _cached_memory_total_gb > 0.0 and _cached_memory_total_gb <= 2.0:
		return true
	# Touch device + low core count is a strong weak-signal for mobile browsers.
	if OS.has_touchscreen_ui_hint() and _processor_count <= 4:
		return true
	return false

func _connect_runtime_signals() -> void:
	if not get_tree():
		return
	if not get_tree().is_connected("node_added", self, "_on_tree_node_added"):
		get_tree().connect("node_added", self, "_on_tree_node_added")

func _on_tree_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_sync_world_environment_for_profile()
		_sync_procedural_sun_direction()
	elif node is Camera:
		_sync_camera_ranges_for_profile()
	elif node is DirectionalLight:
		_sync_directional_lights_for_profile()
		_sync_procedural_sun_direction()
	else:
		var parent = node.get_parent()
		if _is_fluorescent_light_host(node) or (parent and _is_fluorescent_light_host(parent)):
			_sync_fluorescent_lights_for_profile()

func _sync_world_environment_for_profile() -> void:
	if _world_environment_refresh_queued:
		return
	_world_environment_refresh_queued = true
	call_deferred("_sync_world_environment_for_profile_deferred")

func _sync_world_environment_for_profile_deferred() -> void:
	_world_environment_refresh_queued = false
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var world_environments := []
	_collect_world_environments(get_tree().root, world_environments)
	if world_environments.empty():
		return
	# Keep procedural sky in LOW profiles; fallback sky is only for missing-sky environments.
	var use_low_spec_sky = false
	var fallback_sky = _get_or_create_fallback_sky()
	if fallback_sky == null:
		return
	for world_env in world_environments:
		if not is_instance_valid(world_env):
			continue
		if not _ensure_world_environment_resource(world_env, fallback_sky):
			continue
		var has_profiled_override = _try_apply_profiled_environment_override(world_env)
		if not has_profiled_override:
			_apply_world_environment_sky_fallback(world_env, use_low_spec_sky, fallback_sky)
		_apply_world_environment_postfx_policy(world_env)

func _ensure_world_environment_resource(world_env: WorldEnvironment, fallback_sky) -> bool:
	if world_env == null:
		return false
	if world_env.environment != null:
		return true
	var default_env = _load_environment_resource_cached(DEFAULT_WORLD_ENV_PATH)
	if default_env != null:
		world_env.environment = default_env.duplicate(true)
		return true
	var fallback_env := Environment.new()
	fallback_env.background_mode = Environment.BG_SKY
	fallback_env.background_sky = fallback_sky
	fallback_env.ambient_light_color = Color(0.04, 0.08, 0.18, 1.0)
	fallback_env.ambient_light_energy = 1.0
	world_env.environment = fallback_env
	push_warning("[HardwareProfile] WorldEnvironment had null environment; assigned fallback runtime environment.")
	return true

func _collect_world_environments(node: Node, into: Array) -> void:
	if node is WorldEnvironment:
		into.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_world_environments(child, into)

func _try_apply_profiled_environment_override(world_env: WorldEnvironment) -> bool:
	var env_key = _resolve_profiled_environment_key(world_env)
	if env_key == "":
		return false
	var target_path = _get_profiled_environment_path(env_key)
	if target_path == "":
		return false
	var current_path = _get_profiled_environment_current_path(world_env)
	if current_path == target_path:
		return true
	var env_resource = _load_environment_resource_cached(target_path)
	if env_resource == null:
		push_warning("[HardwareProfile] Failed to load profiled environment: %s" % target_path)
		return false
	world_env.environment = env_resource.duplicate(true)
	world_env.set_meta(META_PROFILED_ENV_KEY, env_key)
	world_env.set_meta(META_PROFILED_ENV_PATH, target_path)
	return true

func _resolve_profiled_environment_key(world_env: WorldEnvironment) -> String:
	if world_env.has_meta(META_PROFILED_ENV_KEY):
		return String(world_env.get_meta(META_PROFILED_ENV_KEY))
	if world_env.environment == null:
		return ""
	var resource_path = String(world_env.environment.resource_path)
	if resource_path in [INTERIOR_WIDE_ENV_HIGH_PATH, INTERIOR_WIDE_ENV_MEDIUM_PATH, INTERIOR_WIDE_ENV_LOW_PATH]:
		world_env.set_meta(META_PROFILED_ENV_KEY, PROFILED_ENV_INTERIOR_WIDE)
		if resource_path != "":
			world_env.set_meta(META_PROFILED_ENV_PATH, resource_path)
		return PROFILED_ENV_INTERIOR_WIDE
	return ""

func _get_profiled_environment_path(env_key: String) -> String:
	if env_key == PROFILED_ENV_INTERIOR_WIDE:
		if _detected_profile <= Profile.LOW:
			return INTERIOR_WIDE_ENV_LOW_PATH
		if _detected_profile == Profile.MEDIUM:
			return INTERIOR_WIDE_ENV_MEDIUM_PATH
		return INTERIOR_WIDE_ENV_HIGH_PATH
	return ""

func _get_profiled_environment_current_path(world_env: WorldEnvironment) -> String:
	if world_env.has_meta(META_PROFILED_ENV_PATH):
		return String(world_env.get_meta(META_PROFILED_ENV_PATH))
	if world_env.environment == null:
		return ""
	return String(world_env.environment.resource_path)

func _load_environment_resource_cached(path: String) -> Environment:
	if _environment_resource_cache.has(path):
		return _environment_resource_cache[path]
	var loaded = load(path)
	if loaded and loaded is Environment:
		_environment_resource_cache[path] = loaded
		return loaded
	return null

func _sync_procedural_sun_direction() -> void:
	if _sun_direction_sync_queued:
		return
	_sun_direction_sync_queued = true
	call_deferred("_sync_procedural_sun_direction_deferred")

func _sync_procedural_sun_direction_deferred() -> void:
	_sun_direction_sync_queued = false
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var sun_direction = _get_sun_direction_from_primary_directional()
	if sun_direction == Vector3.ZERO:
		return
	var latitude = rad2deg(asin(clamp(sun_direction.y, -1.0, 1.0)))
	var longitude = rad2deg(atan2(sun_direction.x, sun_direction.z))
	var world_environments := []
	_collect_world_environments(get_tree().root, world_environments)
	for world_env in world_environments:
		var sky = _get_runtime_procedural_sky(world_env)
		if sky == null:
			continue
		sky.sun_latitude = latitude
		sky.sun_longitude = longitude

func _get_sun_direction_from_primary_directional() -> Vector3:
	var directional_lights := []
	_collect_directional_lights(get_tree().root, directional_lights)
	if directional_lights.empty():
		return Vector3.ZERO
	var primary = null
	for light in directional_lights:
		if is_instance_valid(light) and light.visible:
			primary = light
			break
	if primary == null:
		primary = directional_lights[0]
	if not is_instance_valid(primary):
		return Vector3.ZERO
	# DirectionalLight shines along local -Z, so sun position is inverse (local +Z).
	return primary.global_transform.basis.z.normalized()

func _get_runtime_procedural_sky(world_env: WorldEnvironment) -> ProceduralSky:
	if world_env == null or world_env.environment == null:
		return null
	_ensure_runtime_environment_instance(world_env)
	if world_env.environment == null:
		return null
	var sky = world_env.environment.background_sky
	if sky == null or not (sky is ProceduralSky):
		return null
	return sky as ProceduralSky

func _ensure_runtime_environment_instance(world_env: WorldEnvironment) -> void:
	if world_env.has_meta(META_RUNTIME_ENV_INSTANCE):
		return
	if world_env.environment == null:
		return
	world_env.environment = world_env.environment.duplicate(true)
	world_env.set_meta(META_RUNTIME_ENV_INSTANCE, true)

func _get_or_create_fallback_sky():
	if _fallback_sky:
		return _fallback_sky
	var sky = ProceduralSky.new()
	# Keep the fallback sky horizonless for deep-space look.
	sky.sky_top_color = FALLBACK_SPACE_COLOR
	sky.sky_horizon_color = FALLBACK_SPACE_COLOR
	sky.sky_curve = 0.25
	sky.ground_horizon_color = FALLBACK_SPACE_COLOR
	sky.ground_bottom_color = FALLBACK_SPACE_COLOR
	sky.ground_curve = 0.25
	_fallback_sky = sky
	return _fallback_sky

func _apply_world_environment_sky_fallback(world_env: WorldEnvironment, force_low_spec: bool, fallback_sky) -> void:
	if world_env.environment == null:
		return
	if not world_env.has_meta(META_ORIGINAL_ENVIRONMENT):
		world_env.set_meta(META_ORIGINAL_ENVIRONMENT, world_env.environment.duplicate(true))
	var needs_fallback = force_low_spec
	var has_sky_mode = world_env.environment.background_mode == Environment.BG_SKY
	var current_has_no_sky = has_sky_mode and world_env.environment.background_sky == null
	if current_has_no_sky:
		needs_fallback = true
	if not needs_fallback:
		var current_is_fallback = has_sky_mode and world_env.environment.background_sky == fallback_sky
		if (current_is_fallback or current_has_no_sky) and world_env.has_meta(META_ORIGINAL_ENVIRONMENT):
			var original_env = world_env.get_meta(META_ORIGINAL_ENVIRONMENT)
			if original_env:
				world_env.environment = original_env.duplicate(true)
		return
	if world_env.environment.background_mode == Environment.BG_SKY and world_env.environment.background_sky == fallback_sky:
		return
	var baseline_env = world_env.get_meta(META_ORIGINAL_ENVIRONMENT)
	var env_copy = baseline_env.duplicate(true) if baseline_env else world_env.environment.duplicate(true)
	env_copy.background_mode = Environment.BG_SKY
	env_copy.background_sky = fallback_sky
	if force_low_spec:
		env_copy.ambient_light_sky_contribution = min(env_copy.ambient_light_sky_contribution, 0.25)
		# With low profile shadows disabled, lower brightness to preserve scene contrast.
		env_copy.adjustment_enabled = true
		env_copy.adjustment_brightness = LOW_NO_SHADOW_ENV_BRIGHTNESS
	world_env.environment = env_copy

func _apply_world_environment_postfx_policy(world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return
	_ensure_runtime_environment_instance(world_env)
	var env = world_env.environment
	if env == null:
		return
	if not world_env.has_meta(META_ORIGINAL_ENV_GLOW_ENABLED):
		world_env.set_meta(META_ORIGINAL_ENV_GLOW_ENABLED, bool(env.glow_enabled))
	if not world_env.has_meta(META_ORIGINAL_ENV_SSAO_ENABLED):
		world_env.set_meta(META_ORIGINAL_ENV_SSAO_ENABLED, bool(env.ssao_enabled))
	if _has_property(env, "dof_blur_near_enabled") and not world_env.has_meta(META_ORIGINAL_ENV_DOF_NEAR_ENABLED):
		world_env.set_meta(META_ORIGINAL_ENV_DOF_NEAR_ENABLED, bool(env.dof_blur_near_enabled))
	if _has_property(env, "dof_blur_far_enabled") and not world_env.has_meta(META_ORIGINAL_ENV_DOF_FAR_ENABLED):
		world_env.set_meta(META_ORIGINAL_ENV_DOF_FAR_ENABLED, bool(env.dof_blur_far_enabled))
	if _has_property(env, "adjustment_enabled") and not world_env.has_meta(META_ORIGINAL_ENV_ADJUSTMENT_ENABLED):
		world_env.set_meta(META_ORIGINAL_ENV_ADJUSTMENT_ENABLED, bool(env.adjustment_enabled))

	if _hyper_low_mode:
		env.glow_enabled = false
		env.ssao_enabled = false
		if _has_property(env, "dof_blur_near_enabled"):
			env.dof_blur_near_enabled = false
		if _has_property(env, "dof_blur_far_enabled"):
			env.dof_blur_far_enabled = false
		if _has_property(env, "adjustment_enabled"):
			env.adjustment_enabled = false
		return

	if world_env.has_meta(META_ORIGINAL_ENV_GLOW_ENABLED):
		env.glow_enabled = bool(world_env.get_meta(META_ORIGINAL_ENV_GLOW_ENABLED))
	if world_env.has_meta(META_ORIGINAL_ENV_SSAO_ENABLED):
		env.ssao_enabled = bool(world_env.get_meta(META_ORIGINAL_ENV_SSAO_ENABLED))
	if _has_property(env, "dof_blur_near_enabled") and world_env.has_meta(META_ORIGINAL_ENV_DOF_NEAR_ENABLED):
		env.dof_blur_near_enabled = bool(world_env.get_meta(META_ORIGINAL_ENV_DOF_NEAR_ENABLED))
	if _has_property(env, "dof_blur_far_enabled") and world_env.has_meta(META_ORIGINAL_ENV_DOF_FAR_ENABLED):
		env.dof_blur_far_enabled = bool(world_env.get_meta(META_ORIGINAL_ENV_DOF_FAR_ENABLED))
	if _has_property(env, "adjustment_enabled") and world_env.has_meta(META_ORIGINAL_ENV_ADJUSTMENT_ENABLED):
		env.adjustment_enabled = bool(world_env.get_meta(META_ORIGINAL_ENV_ADJUSTMENT_ENABLED))

func _sync_camera_ranges_for_profile() -> void:
	if _camera_range_refresh_queued:
		return
	_camera_range_refresh_queued = true
	call_deferred("_sync_camera_ranges_for_profile_deferred")

func _sync_camera_ranges_for_profile_deferred() -> void:
	_camera_range_refresh_queued = false
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var cameras := []
	_collect_cameras(get_tree().root, cameras)
	for camera in cameras:
		_apply_camera_range_policy(camera)

func _collect_cameras(node: Node, into: Array) -> void:
	if node is Camera:
		into.append(node as Camera)
	for child in node.get_children():
		if child is Node:
			_collect_cameras(child, into)

func _apply_camera_range_policy(camera: Camera) -> void:
	if not is_instance_valid(camera):
		return
	if not camera.has_meta(META_ORIGINAL_CAMERA_FAR):
		camera.set_meta(META_ORIGINAL_CAMERA_FAR, float(camera.far))
	var original_far = float(camera.get_meta(META_ORIGINAL_CAMERA_FAR))
	if _hyper_low_mode:
		var capped_far = min(original_far, HYPER_LOW_CAMERA_FAR_CLAMP)
		if original_far > HYPER_LOW_CAMERA_FAR_MIN:
			capped_far = max(HYPER_LOW_CAMERA_FAR_MIN, capped_far)
		if not is_equal_approx(camera.far, capped_far):
			camera.far = capped_far
		return
	if not is_equal_approx(camera.far, original_far):
		camera.far = original_far

func _refresh_hyper_low_state() -> void:
	var next_state = _detected_profile <= Profile.LOW and _is_anbernic_target
	_hyper_low_mode = bool(next_state)

func _sync_directional_lights_for_profile() -> void:
	if _directional_lights_refresh_queued:
		return
	_directional_lights_refresh_queued = true
	call_deferred("_sync_directional_lights_for_profile_deferred")

func _sync_directional_lights_for_profile_deferred() -> void:
	_directional_lights_refresh_queued = false
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var directional_lights := []
	_collect_directional_lights(get_tree().root, directional_lights)
	var shadow_policy = DIRECTIONAL_SHADOW_POLICY_RESTORE
	if _detected_profile <= Profile.LOW:
		shadow_policy = DIRECTIONAL_SHADOW_POLICY_OFF
	elif _detected_profile == Profile.MEDIUM:
		shadow_policy = DIRECTIONAL_SHADOW_POLICY_REDUCED
	_directional_shadow_update_version += 1
	var version = _directional_shadow_update_version
	if shadow_policy == DIRECTIONAL_SHADOW_POLICY_RESTORE:
		for light in directional_lights:
			_apply_directional_light_shadow_policy(light, shadow_policy)
	else:
		_apply_directional_shadow_policy_batch(directional_lights, shadow_policy, version, 0)

func _collect_directional_lights(node: Node, into: Array) -> void:
	if node is DirectionalLight:
		into.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_directional_lights(child, into)

func _apply_directional_light_shadow_policy(light: DirectionalLight, shadow_policy: int) -> void:
	if not is_instance_valid(light):
		return
	_capture_directional_light_shadow_defaults(light)
	var original_shadow_enabled = bool(light.get_meta(META_ORIGINAL_DIR_SHADOW))
	if _has_property(light, "directional_shadow_blend_splits"):
		light.directional_shadow_blend_splits = false
	if shadow_policy == DIRECTIONAL_SHADOW_POLICY_OFF:
		light.shadow_enabled = false
		return
	if shadow_policy == DIRECTIONAL_SHADOW_POLICY_REDUCED:
		light.shadow_enabled = original_shadow_enabled
		if not original_shadow_enabled:
			return
		if _has_property(light, "directional_shadow_mode"):
			light.directional_shadow_mode = DirectionalLight.SHADOW_PARALLEL_2_SPLITS
		if _has_property(light, "directional_shadow_blend_splits"):
			light.directional_shadow_blend_splits = false
		if _has_property(light, "directional_shadow_max_distance") and light.has_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE):
			light.directional_shadow_max_distance = float(light.get_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE))
		return
	light.shadow_enabled = original_shadow_enabled
	if _has_property(light, "directional_shadow_mode") and light.has_meta(META_ORIGINAL_DIR_SHADOW_MODE):
		light.directional_shadow_mode = int(light.get_meta(META_ORIGINAL_DIR_SHADOW_MODE))
	if _has_property(light, "directional_shadow_max_distance") and light.has_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE):
		light.directional_shadow_max_distance = float(light.get_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE))

func _capture_directional_light_shadow_defaults(light: DirectionalLight) -> void:
	if not light.has_meta(META_ORIGINAL_DIR_SHADOW):
		light.set_meta(META_ORIGINAL_DIR_SHADOW, light.shadow_enabled)
	if _has_property(light, "directional_shadow_mode") and not light.has_meta(META_ORIGINAL_DIR_SHADOW_MODE):
		light.set_meta(META_ORIGINAL_DIR_SHADOW_MODE, light.directional_shadow_mode)
	if _has_property(light, "directional_shadow_blend_splits") and not light.has_meta(META_ORIGINAL_DIR_SHADOW_BLEND_SPLITS):
		light.set_meta(META_ORIGINAL_DIR_SHADOW_BLEND_SPLITS, light.directional_shadow_blend_splits)
	if _has_property(light, "directional_shadow_max_distance") and not light.has_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE):
		light.set_meta(META_ORIGINAL_DIR_SHADOW_MAX_DISTANCE, light.directional_shadow_max_distance)

func _has_property(obj: Object, property_name: String) -> bool:
	for data in obj.get_property_list():
		if String(data.get("name", "")) == property_name:
			return true
	return false

func _sync_fluorescent_lights_for_profile() -> void:
	if _fluorescent_lights_refresh_queued:
		return
	_fluorescent_lights_refresh_queued = true
	call_deferred("_sync_fluorescent_lights_for_profile_deferred")

func _sync_fluorescent_lights_for_profile_deferred() -> void:
	_fluorescent_lights_refresh_queued = false
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var fluorescent_hosts := []
	_collect_fluorescent_hosts(get_tree().root, fluorescent_hosts)
	var disable_shadows = _detected_profile <= Profile.MEDIUM
	_fluorescent_shadow_update_version += 1
	var version = _fluorescent_shadow_update_version
	if disable_shadows:
		_apply_fluorescent_shadow_policy_batch(fluorescent_hosts, disable_shadows, version, 0)
	else:
		for host in fluorescent_hosts:
			_apply_fluorescent_shadow_policy(host, disable_shadows)

func _apply_directional_shadow_policy_batch(lights: Array, shadow_policy: int, version: int, start_index: int) -> void:
	if version != _directional_shadow_update_version:
		return
	var end_index = min(start_index + DIRECTIONAL_SHADOW_BATCH_SIZE, lights.size())
	for i in range(start_index, end_index):
		_apply_directional_light_shadow_policy(lights[i], shadow_policy)
	if end_index < lights.size() and version == _directional_shadow_update_version:
		yield(get_tree(), "idle_frame")
		if version == _directional_shadow_update_version:
			_apply_directional_shadow_policy_batch(lights, shadow_policy, version, end_index)

func _apply_fluorescent_shadow_policy_batch(hosts: Array, disable_shadows: bool, version: int, start_index: int) -> void:
	if version != _fluorescent_shadow_update_version:
		return
	var end_index = min(start_index + FLUORESCENT_SHADOW_BATCH_SIZE, hosts.size())
	for i in range(start_index, end_index):
		_apply_fluorescent_shadow_policy(hosts[i], disable_shadows)
	if end_index < hosts.size() and version == _fluorescent_shadow_update_version:
		yield(get_tree(), "idle_frame")
		if version == _fluorescent_shadow_update_version:
			_apply_fluorescent_shadow_policy_batch(hosts, disable_shadows, version, end_index)

func _collect_fluorescent_hosts(node: Node, into: Array) -> void:
	if _is_fluorescent_light_host(node):
		into.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_fluorescent_hosts(child, into)

func _is_fluorescent_light_host(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var script = node.get_script()
	if script == null:
		return false
	if not (script is Script):
		return false
	return String(script.resource_path) == FLUORESCENT_SCRIPT_PATH

func _apply_fluorescent_shadow_policy(host: Node, disable_shadows: bool) -> void:
	for child in host.get_children():
		if not (child is Light):
			continue
		if not (child is OmniLight or child is SpotLight):
			continue
		if not child.has_meta(META_ORIGINAL_FLUOR_SHADOW):
			child.set_meta(META_ORIGINAL_FLUOR_SHADOW, child.shadow_enabled)
		if disable_shadows:
			child.shadow_enabled = false
		else:
			child.shadow_enabled = bool(child.get_meta(META_ORIGINAL_FLUOR_SHADOW))

func _sync_optional_nodes_for_profile() -> void:
	call_deferred("_sync_optional_nodes_for_profile_deferred")

func _sync_optional_nodes_for_profile_deferred() -> void:
	if not get_tree() or not is_instance_valid(get_tree().root):
		return
	var opt_manager = get_tree().root.get_node_or_null("OptionalNodeManager")
	if not opt_manager or not opt_manager.has_method("set_optional_nodes_enabled"):
		return
	if _is_weak_hardware:
		opt_manager.set_optional_nodes_enabled(false)
