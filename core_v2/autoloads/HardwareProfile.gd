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

var _detected_profile: int = Profile.UNKNOWN
var _detected_platform: int = PlatformType.UNKNOWN
var _detected_device_name := ""
var _processor_count := 0
var _is_weak_hardware := false
var _auto_detected := false
var _cached_memory_total_gb := 8.0

signal profile_changed(new_profile)
signal platform_detected(platform_type, device_name)

func _ready() -> void:
	_detect_hardware()
	_apply_environment_overrides()

func _detect_hardware() -> void:
	_processor_count = OS.get_processor_count()
	var mem_info = _get_memory_info()
	_cached_memory_total_gb = float(mem_info.total_gb)
	var os_name = OS.get_name()
	
	# Check environment variable for device override (e.g., ODISEA_DEVICE=anbernic)
	var forced_device = OS.get_environment("ODISEA_DEVICE").to_lower()
	if forced_device != "":
		_detected_device_name = forced_device
		if forced_device in ["anbernic", "351", "rg351", "rk3326"]:
			_detected_platform = PlatformType.LINUX_ARM
			_detected_profile = Profile.LOW
			_detected_device_name = "Anbernic " + forced_device
			_is_weak_hardware = true
			_auto_detected = true
			emit_signal("platform_detected", _detected_platform, _detected_device_name)
			print("[HardwareProfile] Forced device: %s, Profile: LOW" % forced_device)
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
	
	emit_signal("platform_detected", _detected_platform, _detected_device_name)
	print("[HardwareProfile] Detected: %s (%s), Profile: %s, Cores: %d, RAM: %.1fGB, Weak: %s" % [
		_detected_device_name, 
		PlatformType.keys()[_detected_platform],
		Profile.keys()[_detected_profile],
		_processor_count,
		_cached_memory_total_gb,
		_is_weak_hardware
	])

func _detect_linux_platform() -> int:
	var device_info = _get_linux_device_info()
	_detected_device_name = device_info.model
	
	if _is_anbernic_device(device_info):
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _is_rk3326_device(device_info):
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _is_s905_device(device_info):
		_detected_profile = Profile.LOW
		return PlatformType.LINUX_ARM
	
	if _has_mali_gpu(device_info):
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
	var info := { "total_gb": 8.0, "available_gb": 4.0 }
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
	return Profile.LOW

func _detect_weak_hardware() -> bool:
	if _detected_platform == PlatformType.SWITCH:
		return true
	
	if _detected_platform == PlatformType.LINUX_ARM and _detected_profile == Profile.LOW:
		return true
	
	if _detected_platform == PlatformType.ANDROID and _processor_count <= 4:
		return true
	
	if _detected_platform == PlatformType.HTML5:
		return true
	
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
			set_profile(Profile.LOW)
		"medium", "med", "2":
			set_profile(Profile.MEDIUM)
		"high", "3":
			set_profile(Profile.HIGH)
		"superhigh", "max", "4":
			set_profile(Profile.SUPERHIGH)
	
	# VSync control - disable for weak hardware or via env
	var vsync_env = OS.get_environment("ODISEA_VSYNC").to_lower()
	if vsync_env == "off" or vsync_env == "0" or _detected_profile == Profile.LOW:
		OS.set_use_vsync(false)
		print("[HardwareProfile] VSync disabled")
	
	var force_optional = OS.get_environment("ODISEA_FORCE_OPTIONAL_NODES").to_lower()
	call_deferred("_apply_optional_override", force_optional)

func _apply_optional_override(force_optional: String) -> void:
	var opt_manager = get_tree().root.get_node_or_null("OptionalNodeManager")
	if opt_manager:
		if force_optional in ["1", "true", "yes", "on"]:
			opt_manager.set_optional_nodes_enabled(true)
		elif force_optional in ["0", "false", "no", "off"]:
			opt_manager.set_optional_nodes_enabled(false)

func set_profile(new_profile: int) -> void:
	if new_profile != _detected_profile:
		_detected_profile = new_profile
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
