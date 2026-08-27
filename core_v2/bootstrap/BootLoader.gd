extends Node

export(String, FILE, "*.tscn,*.scn") var startup_scene_path := "res://scenes/Menu.tscn"
export(String) var loading_message := "ODiSEA"
export(String) var version_label := ""
export(bool) var show_progress := true
export(int, 0, 60) var scene_manager_wait_frames := 12

var _started := false
var _fallback_started := false

# Cuanto tardo el proceso en llegar hasta aca. Es lo unico que se sabe del aparato
# ANTES de dibujar el primer frame -- mide CPU, disco y el armado de los autoloads
# juntos -- y AdaptiveRenderScale lo lee para arrancar ya reducido en una maquina lenta
# en vez de esperar a que el jugador sufra la primera escena entera.
const BOOT_MS_META := "odisea_boot_ms"

func _ready() -> void:
	if Engine.editor_hint:
		return
	Engine.set_meta(BOOT_MS_META, OS.get_ticks_msec())
	
	# FD-234: Initialize version label from ProjectSettings
	var VersionLabelHelper = load("res://core_v2/ui/VersionLabel.gd")
	if VersionLabelHelper:
		version_label = VersionLabelHelper.get_formatted_version()
	_mark_trace("boot_scene_ready", {"target_scene": startup_scene_path, "boot_ms": Engine.get_meta(BOOT_MS_META)})
	# Android hotzone deep link: if the app was launched via odisea://replay,
	# route straight to the replay player instead of the normal boot flow.
	var deep_link := _get_replay_deep_link()
	if deep_link != "":
		_mark_trace("boot_replay_deep_link", {"link": deep_link})
		# Hand the signed replay URL to HotzonePlayer (change_scene can't pass
		# args, so stash it on SessionManager, which the player already reads).
		var session := get_node_or_null("/root/SessionManager")
		if session:
			session.replay_meta = {"deep_link_url": deep_link}
		var err := get_tree().change_scene("res://core_v2/tools/HotzonePlayer.tscn")
		if err != OK:
			printerr("[BootLoader] change_scene to HotzonePlayer failed (err=%d)" % err)
		return
	var skip_reason := _get_skip_reason()
	if skip_reason != "":
		_mark_trace("boot_scene_autoload_skipped", {"reason": skip_reason})
		return
	# Android GPU profiling: detect low-end GPUs and adjust rendering quality
	# before any scene is loaded.
	_apply_android_gpu_profile()
	call_deferred("_start_boot_transition")

# --- Android GPU Profiling ----------------------------------------------------
# Detects GPU vendor and adjusts rendering settings to avoid visual artifacts
# and improve performance on mobile devices.
# Tested device profiles:
#   - Mali-Gxx (high-end ARM): full quality
#   - Mali-4xx/Adreno 3xx (mid-range): reduced glow, fewer shader effects
#   - Mali-2xx/PowerVR SGX (low-end): minimum effects

func _apply_android_gpu_profile() -> void:
	if not OS.has_feature("Android"):
		return

	var gpu_name: String = VisualServer.get_video_adapter_name().to_lower()
	var gpu_vendor: String = VisualServer.get_video_adapter_vendor().to_lower()
	var profile := "default"
	var settings := {}

	# Detect GPU tier
	var is_mali := "mali" in gpu_name
	var is_adreno := "adreno" in gpu_name
	var is_powervr := "powervr" in gpu_name or "sgx" in gpu_name

	if is_mali:
		# Extract Mali generation: "Mali-G78", "Mali-450", etc.
		var mali_gen := ""
		var dash_idx := gpu_name.find("-")
		if dash_idx != -1:
			var after_dash := gpu_name.substr(dash_idx + 1)
			var gen_char := after_dash.substr(0, 1)
			mali_gen = gen_char
		if mali_gen in ["G", "T"]:
			profile = "high"
		elif mali_gen == "4":
			profile = "medium"
		else:
			profile = "low"
	elif is_adreno:
		# Adreno 5xx+ = high, 3xx-4xx = medium
		for i in range(3, 9):
			if str(i) + "xx" in gpu_name or str(i) + "00" in gpu_name:
				profile = "high" if i >= 5 else "medium"
				break
	elif is_powervr:
		profile = "low"
	# else: Unknown GPU, leave at "default" (no changes)

	match profile:
		"high":
			# Good GPU: keep environment as-is but cap some effects
			settings["prop_dither_max_transparency"] = 0.85
		"medium":
			settings["prop_dither_max_transparency"] = 0.75
			settings["disable_volumetric_lights"] = true
		"low":
			settings["prop_dither_max_transparency"] = 0.6
			settings["disable_volumetric_lights"] = true
			settings["disable_holo_effect"] = true

	if profile != "default":
		_mark_trace("android_gpu_profile", {
			"gpu": gpu_name,
			"vendor": gpu_vendor,
			"profile": profile,
			"settings": settings
		})
		print("[BootLoader] Android GPU profile: %s (%s) → %s" % [gpu_name, gpu_vendor, profile])
	_store_android_gpu_settings(settings)

func _start_boot_transition() -> void:
	if _started:
		return
	_started = true
	if startup_scene_path.strip_edges() == "":
		printerr("[BootLoader] startup_scene_path is empty.")
		return

	var scene_manager = get_node_or_null("/root/SceneManager")
	var wait_frames := max(0, scene_manager_wait_frames)
	while (scene_manager == null or not scene_manager.has_method("goto_scene")) and wait_frames > 0:
		wait_frames -= 1
		yield(get_tree(), "idle_frame")
		scene_manager = get_node_or_null("/root/SceneManager")
	_mark_trace("boot_loader_scene_request", {"path": startup_scene_path})
	if scene_manager and scene_manager.has_method("goto_scene"):
		if not scene_manager.is_connected("transition_failed", self, "_on_transition_failed"):
			scene_manager.connect("transition_failed", self, "_on_transition_failed")
		var state = scene_manager.goto_scene(startup_scene_path, {
			"transition": "loading",
			"show_loading": true,
			"show_progress": show_progress,
			"loading_message": loading_message,
			"loading_subtitle": version_label,
			"fade_out": 0.0,
			"fade_in": 0.0,
			"audio_fade_out": 0.0,
			"audio_fade_in": 0.0,
			"preserve_player_state": false
		})
		if state is GDScriptFunctionState:
			yield(state, "completed")
		_notify_player_released()
		return

	_mark_trace("boot_loader_scene_request_fallback", {"path": startup_scene_path})
	_start_direct_scene_fallback("scene_manager_missing")

func _on_transition_failed(path: String, reason: String) -> void:
	if String(path) != startup_scene_path:
		return
	if _fallback_started:
		return
	printerr("[BootLoader] Interactive startup transition failed (%s). Falling back to direct change_scene." % reason)
	_mark_trace("boot_loader_transition_failed", {
		"path": path,
		"reason": reason
	})
	call_deferred("_start_direct_scene_fallback", reason)

func _start_direct_scene_fallback(reason: String = "") -> void:
	if _fallback_started:
		return
	_fallback_started = true
	_mark_trace("boot_loader_direct_fallback", {
		"path": startup_scene_path,
		"reason": reason
	})
	var err := get_tree().change_scene(startup_scene_path)
	if err != OK:
		printerr("[BootLoader] change_scene failed for %s (err=%d)" % [startup_scene_path, err])
	else:
		_notify_player_released()

# Tell the HTML shell (web exports) that the boot transition finished and
# the player is in control, so it can report total load time to the bridge.
func _notify_player_released() -> void:
	if not OS.has_feature("JavaScript"):
		return
	JavaScript.eval("window.OdiseaShell && window.OdiseaShell.playerReleased && window.OdiseaShell.playerReleased();", true)

func _get_skip_reason() -> String:
	if _is_test_suite():
		return "test_suite"
	if OS.get_environment("OYS_AUTO_RUN") != "":
		return "auto_run_script"

	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = String(args[i])
		if arg == "--replay":
			return "cli_replay"
		if arg == "--run-script":
			return "cli_script"
		if arg == "--video-export" or arg == "--export-video":
			if i + 1 < args.size():
				var next = String(args[i + 1])
				if not next.begins_with("--") and (next.ends_with(".json") or next.ends_with(".oys")):
					return "video_export_replay"
	return ""

# Returns the signed hotzone replay URL from an odisea://replay?url=<signed>
# Android deep link, or "" when there is none. The OdiseaDeepLink plugin is
# only present on Android custom builds; absent everywhere else.
func _get_replay_deep_link() -> String:
	if not Engine.has_singleton("OdiseaDeepLink"):
		return ""
	var plugin = Engine.get_singleton("OdiseaDeepLink")
	var link := String(plugin.consume_deep_link())
	if link == "" or not link.begins_with("odisea://replay"):
		return ""
	# Extract the url query param: odisea://replay?url=<percent-encoded signed url>
	var q_idx := link.find("?")
	if q_idx == -1:
		return ""
	var query = link.substr(q_idx + 1)
	for pair in query.split("&"):
		var kv = String(pair).split("=")
		if kv.size() == 2 and kv[0] == "url":
			return String(kv[1]).percent_decode()
	return ""

func _mark_trace(name: String, data: Dictionary = {}) -> void:
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace and startup_trace.has_method("mark"):
		startup_trace.mark(name, data)

func _is_test_suite() -> bool:
	if Engine.has_singleton("GdUnit3"):
		return Engine.get_singleton("GdUnit3").is_test_suite()
	return false

func _store_android_gpu_settings(settings: Dictionary) -> void:
	# Store GPU profile settings where other systems can read them.
	# PropDitherManager reads dither params, SceneLighting reads env hints.
	if settings.empty():
		return
	# Use a singleton-friendly approach: store on SessionManager if available,
	# or use ProjectSettings metadata keys.
	var session := get_node_or_null("/root/SessionManager")
	if session:
		if "gpu_profile" in session:
			session.gpu_profile = settings
	if "prop_dither_max_transparency" in settings:
		var t: float = float(settings["prop_dither_max_transparency"])
		var dither_mgr := get_node_or_null("/root/PropDitherManager")
		if dither_mgr and dither_mgr.has_method("set_occlusion_params"):
			dither_mgr.set_occlusion_params(dither_mgr._hole_radius, {
				"transparency_max": t,
				"transparency_min": t * 0.3
			})
