# core_v2/systems/OYS_Interpreter.gd
# Runtime interpreter: executes OYS scripts with coroutines and signal support
# Used for in-game scripting, cutscenes, and interactive tests with ASSERT_SIGNAL
extends Reference

class_name OYS_Interpreter

const OYS_Parser = preload("res://core_v2/systems/OYS_Parser.gd")

var instructions: Array = []
var pc: int = 0
var variables: Dictionary = {}
var sections: Dictionary = {}
var section_names: Array = []
var host_node: Node
var _node_cache: Dictionary = {}
var _vcam_scene_defaults: Dictionary = {}
var is_running: bool = false
var stop_requested: bool = false
var fast_forward: bool = false
var execution_id: int = 0
var test_failed: bool = false # Global flag to track test failure
var loop_runtime_stack: Array = [] # Runtime stack for loops
var _system_launch_counter: int = 1000
signal instruction_executed(inst, variables)
signal instruction_completed(inst, variables)

func _init(host: Node):
	host_node = host
	if not host_node:
		printerr("[OYS_Interpreter] Initialized with NULL host node!")
	else:
		print("[OYS_Interpreter] Initialized with host: ", host.name)

func parse(script_content: String):
	instructions.clear()
	sections.clear()
	section_names.clear()
	_node_cache.clear()
	_vcam_scene_defaults.clear()
	pc = 0

	var lines = OYS_Parser.preprocess(script_content)
	var loop_stack = [] # Stack of indices for open loops
	
	for i in range(lines.size()):
		var line = lines[i]
		var inst = OYS_Parser.parse_instruction(line)
		if inst.empty():
			continue

		if inst.command == "SECTION":
			var section_name = inst.get("name", "")
			sections[section_name] = instructions.size()
			section_names.append(section_name)

		# Loop linking logic
		if inst.command == "FOR" or inst.command == "WHILE":
			loop_stack.push_back(instructions.size())

		elif inst.command == "ENDFOR":
			if loop_stack.empty():
				printerr("[OYS_Interpreter] ENDFOR without matching FOR at line ", i)
			else:
				var start_idx = loop_stack.pop_back()
				var start_inst = instructions[start_idx]
				if start_inst.command != "FOR":
					printerr("[OYS_Interpreter] Mismatched loop: ENDFOR matched with ", start_inst.command)
				else:
					start_inst["end_index"] = instructions.size()
					inst["start_index"] = start_idx

		elif inst.command == "ENDWHILE":
			if loop_stack.empty():
				printerr("[OYS_Interpreter] ENDWHILE without matching WHILE at line ", i)
			else:
				var start_idx = loop_stack.pop_back()
				var start_inst = instructions[start_idx]
				if start_inst.command != "WHILE":
					printerr("[OYS_Interpreter] Mismatched loop: ENDWHILE matched with ", start_inst.command)
				else:
					start_inst["end_index"] = instructions.size()
					inst["start_index"] = start_idx

		elif inst.command == "BLEND":
			loop_stack.push_back(instructions.size())
		
		elif inst.command == "END":
			if not loop_stack.empty():
				var start_idx = loop_stack.back()
				var start_inst = instructions[start_idx]
				if start_inst.command == "BLEND":
					loop_stack.pop_back()
					start_inst["end_index"] = instructions.size()

		instructions.append(inst)

	if not loop_stack.empty():
		var unclosed_non_blend := []
		while not loop_stack.empty():
			var start_idx = loop_stack.pop_back()
			if start_idx < 0 or start_idx >= instructions.size():
				continue
			var start_inst = instructions[start_idx]
			if start_inst.command == "BLEND":
				# Auto-close trailing BLEND blocks at EOF so scripts don't require a final END marker.
				start_inst["end_index"] = instructions.size()
			else:
				unclosed_non_blend.append(start_inst.command)
		if not unclosed_non_blend.empty():
			printerr("[OYS_Interpreter] Unclosed loops at end of script: ", unclosed_non_blend.size(), " -> ", unclosed_non_blend)

func run(start_section: String = ""):
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		if host_node and is_instance_valid(host_node) and host_node.is_inside_tree():
			yield (host_node.get_tree(), "physics_frame")

	is_running = true
	stop_requested = false
	loop_runtime_stack.clear()

	if start_section != "" and sections.has(start_section):
		pc = sections[start_section]
	else:
		pc = 0

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield (result, "completed")
		emit_signal("instruction_completed", inst, variables)

	if my_id == execution_id:
		is_running = false
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and is_instance_valid(session):
			session.set("_oys_input_override", {})

# Ejecutar desde un program counter específico (para hot-reload con checkpoints)
func request_fast_forward():
	fast_forward = true
	_interrupt_running_animation()
func run_from_pc(from_pc: int):
	var _from_pc = from_pc
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		if host_node and is_instance_valid(host_node) and host_node.is_inside_tree():
			yield (host_node.get_tree(), "physics_frame")

	is_running = true
	stop_requested = false
	if my_id == execution_id:
		is_running = false
		var session = null
		if is_instance_valid(host_node) and host_node.is_inside_tree():
			session = host_node.get_node_or_null("/root/SessionManager")
		
		if session:
			if session.has_method("set"):
				session.set("_oys_input_override", {})

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield (result, "completed")
		emit_signal("instruction_completed", inst, variables)

	if my_id == execution_id:
		is_running = false
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and is_instance_valid(session):
			session.set("_oys_input_override", {})

func _execute_instruction(inst: Dictionary, my_id: int):
	var cmd = inst.command
	emit_signal("instruction_executed", inst, variables)
	
	match cmd:
		"BLEND":
			var duration = inst.get("duration", 1.0)
			var end_index = inst.get("end_index", -1)
			
			if end_index != -1:
				# Skip the block in the main loop
				var start_pc = pc # Next instruction
				pc = end_index + 1
				
				# Launch sub-instructions in parallel
				var running_states = []
				for i in range(start_pc, end_index):
					var sub_inst = instructions[i]
					# Recurse or execute directly
					# Note: sub-instructions like WAIT or GOTO might be problematic in parallel
					# For now we assume only movement/action commands
					var state = _execute_instruction(sub_inst, my_id)
					if state is GDScriptFunctionState:
						running_states.append(state)
				
				# Wait for duration or completion
				# Strategy: Run for 'duration' seconds. Stop if all done.
				var elapsed = 0.0
				while elapsed < duration:
					if stop_requested or my_id != execution_id:
						break
					
					var all_done = true
					for s in running_states:
						if s.is_valid():
							all_done = false
							break
					
					if all_done:
						break
					
					elapsed += host_node.get_physics_process_delta_time()
					yield (host_node.get_tree(), "physics_frame")
					
					# Important: Manually resume sub-coroutines if they are valid
					# This is typically not needed if they yield on the same signal,
					# but if they yield on OTHER signals, we just wait.
					# If they yield on physics_frame of the SAME tree, they should auto-resume.
					# But if they depend on `resume()` being called (unlikely for yield(tree, signal)),
					# we are fine.
					# Debug print to see progress
					# print("Blend running: ", elapsed, "/", duration)
		
		"SECTION":
			pass # Already indexed
		
		"GOTO":
			var target = inst.get("target", "")
			if sections.has(target):
				pc = sections[target]
			else:
				printerr("[OYS] GOTO target not found: ", target)
		
		"IF":
			var left = _resolve_value(inst.get("left", ""))
			var right = _resolve_value(inst.get("right", ""))
			var op = inst.get("op", "==")
			var target = inst.get("target", "")
			if _compare(left, op, right):
				if sections.has(target):
					pc = sections[target]
				else:
					printerr("[OYS] IF GOTO target not found: ", target)
		
		"PLAY_ANIM":
			if fast_forward:
				_interrupt_running_animation()
				return
			# 1. Try to find a high-level handler (play_anim) on the Player first
			# This is crucial because PlayerAnimator needs to disable AnimationTree
			var player = _find_player()
			var handled = false
			
			if inst.get("path", "") == "" and player and player.has_method("play_anim"):
				player.play_anim(inst.get("anim", ""))
				handled = true
			
			if not handled:
				# 2. Fallback: Resolve node path directly (e.g. for props or direct anim player access)
				var node = _resolve_node(inst.get("path", ""))
				
				# 3. Last Resort: If no path and player didn't handle it (maybe no play_anim method), 
				# try finding AnimationPlayer on player manually
				if not (node and node is AnimationPlayer) and inst.get("path", "") == "":
					if player:
						var anim = _find_first_animation_player(player)
						if anim: node = anim

				if node and node is AnimationPlayer:
					var blend = inst.get("blend", -1.0)
					node.play(inst.get("anim", ""), blend)
				else:
					var p = inst.get("path", "")
					var n_name = node.name if node else "null"
					printerr("[OYS WARNING] PLAY_ANIM: Target is not an AnimationPlayer. Path='%s', Resolved='%s'" % [p, n_name])

		"PLAY_SOUND":
			var played = false
			var sfx_ref = String(inst.get("sfx", "")).strip_edges()
			var sound_name = String(inst.get("sound", "")).strip_edges()

			if sfx_ref != "":
				var sfx_node = _resolve_node(sfx_ref)
				if sfx_node and sfx_node.has_method("play_sfx"):
					sfx_node.play_sfx()
					played = true
				elif sfx_node and sfx_node.has_method("play"):
					sfx_node.play()
					played = true

			if not played:
				var audio = host_node.get_node_or_null("/root/AudioManager")
				if audio and audio.has_method("play_sound"):
					var resolved_sound = sound_name if sound_name != "" else sfx_ref
					if resolved_sound != "":
						audio.play_sound(resolved_sound, Vector3.ZERO)
						played = true

			if not played:
				printerr("[OYS WARNING] PLAY_SOUND failed: no SFX node or AudioManager sound found. sfx='%s' sound='%s'" % [sfx_ref, sound_name])
		
		"WAIT_ANIM":
			var node = _resolve_node(inst.get("path", ""))
			
			# Fallback: If no path specified, try to find the Player's AnimationPlayer
			if not (node and node is AnimationPlayer) and inst.get("path", "") == "":
				var player = _find_player()
				if player:
					var anim = _find_first_animation_player(player)
					if anim: node = anim
			
			if node and node is AnimationPlayer:
				while node.is_playing():
					if stop_requested or my_id != execution_id:
						break
					if fast_forward:
						_interrupt_animation_player(node)
						_interrupt_running_animation()
						break
					yield (host_node.get_tree(), "physics_frame")
			elif fast_forward:
				# WAIT_ANIM can be authored with animation names (e.g. "Confused")
				# rather than node paths; when skipping, still force-stop active player anims.
				_interrupt_running_animation()
		
		"ASSERT_SIGNAL":
			var target_path = inst.get("path", "")
			var target = host_node
			if target_path != "":
				target = _resolve_node(target_path)

			if target:
				var timeout = inst.get("timeout", 5.0)
				var signal_name = inst.get("signal", "")
				var success = yield (_wait_signal(target, signal_name, timeout, my_id), "completed")
				if not success:
					printerr("[OYS] ASSERT_SIGNAL failed: ", signal_name, " on ", target.name)
					test_failed = true
					stop_requested = true
					return

		"LOAD_PROP":
			var path = inst.get("path", "")
			# Resolve variable if path starts with $
			if path.begins_with("$"):
				var resolved = _resolve_value(path)
				if typeof(resolved) == TYPE_STRING:
					path = resolved
				else:
					printerr("[OYS ERROR] LOAD_PROP path variable resolved to non-string: ", resolved)
			
			var result = null
			if host_node.has_method("load_prop"):
				result = host_node.load_prop(path)
			elif host_node.is_inside_tree():
				var stage = host_node.get_tree().current_scene
				if not stage or not stage.has_method("load_prop"):
					# Fallback search for PropStage
					var root = host_node.get_tree().root
					for i in range(root.get_child_count()):
						var c = root.get_child(i)
						if (c.name == "PropStage" or c.name == "PropStage.tscn") and c.has_method("load_prop"):
							stage = c
							break
				
				if stage and stage.has_method("load_prop"):
					result = stage.load_prop(path)
				else:
					printerr("[OYS_Interpreter] Could not find valid stage with load_prop")
			else:
				printerr("[OYS] LOAD_PROP called but host_node '%s' lacks 'load_prop' method and current_scene doesn't support it either." % host_node.name)
			
			if result is GDScriptFunctionState:
				yield (result, "completed")

		"OPEN":
			var scene_path = _resolve_value(inst.get("path", ""))
			if typeof(scene_path) != TYPE_STRING or String(scene_path).strip_edges() == "":
				printerr("[OYS] OPEN failed: invalid path: ", scene_path)
			else:
				var open_params = {}
				if inst.has("transition"):
					open_params["transition"] = String(_resolve_value(inst.get("transition", "")))
				if inst.has("spawn_id"):
					open_params["spawn_id"] = String(_resolve_value(inst.get("spawn_id", "")))
				var open_state = _change_scene(String(scene_path), open_params)
				if open_state is GDScriptFunctionState:
					yield (open_state, "completed")
				_sync_host_after_scene_change()

		"CHANGE_SCENE":
			var target_scene = _resolve_value(inst.get("path", ""))
			if typeof(target_scene) != TYPE_STRING or String(target_scene).strip_edges() == "":
				printerr("[OYS] CHANGE_SCENE failed: invalid path: ", target_scene)
			else:
				var scene_params = {}
				if inst.has("transition"):
					scene_params["transition"] = String(_resolve_value(inst.get("transition", "")))
				if inst.has("spawn_id"):
					scene_params["spawn_id"] = String(_resolve_value(inst.get("spawn_id", "")))
				var change_state = _change_scene(String(target_scene), scene_params)
				if change_state is GDScriptFunctionState:
					yield (change_state, "completed")
				_sync_host_after_scene_change()

		"CLICK":
			var selector = String(_resolve_value(inst.get("selector", "")))
			if not _click_selector(selector):
				printerr("[OYS] CLICK failed for selector: ", selector)

		"FILL":
			var fill_selector = String(_resolve_value(inst.get("selector", "")))
			var fill_value = String(_resolve_value(inst.get("value", "")))
			if not _fill_selector(fill_selector, fill_value, false):
				printerr("[OYS] FILL failed for selector: ", fill_selector)

		"TYPE":
			var type_selector = String(_resolve_value(inst.get("selector", "")))
			var type_value = String(_resolve_value(inst.get("value", "")))
			if not _fill_selector(type_selector, type_value, true):
				printerr("[OYS] TYPE failed for selector: ", type_selector)

		"PRESS":
			var press_selector = String(_resolve_value(inst.get("selector", "")))
			var press_value = String(_resolve_value(inst.get("value", "")))
			if not _press_selector(press_selector, press_value):
				printerr("[OYS] PRESS failed for selector=%s key=%s" % [press_selector, press_value])

		"ASSERT_TEXT":
			var text_selector = String(_resolve_value(inst.get("selector", "")))
			var expected_text = String(_resolve_value(inst.get("value", "")))
			var node = _resolve_selector_node(text_selector)
			var actual = _extract_control_text(node)
			if actual.find(expected_text) == -1:
				printerr("[OYS ASSERT_TEXT] FAILED selector=%s expected~=\"%s\" actual=\"%s\"" % [text_selector, expected_text, actual])
				test_failed = true
				stop_requested = true
				return

		"CALL":
			var method = inst.get("method", "")
			var args = inst.get("args", [])
			
			# Check for Registered OYS Actor in SessionManager (Global)
			var sm = _find_session_manager()
			var actor = null
			if sm and sm.has_method("get_oys_actor"):
				actor = sm.get_oys_actor(method)
			
			if actor:
				# ACTOR CALL: The first argument is the method name, the rest are arguments
				# CALL CargolDrone "move_to" [10, 20, 30]
				# -> method="CargolDrone", args=["move_to", "[10,", "20,", "30]"]
				if args.size() > 0:
					var real_method = _resolve_value(args[0]) # Resolve method name from var if needed
					var call_args_raw = []
					if args.size() > 1:
						call_args_raw = args.duplicate()
						call_args_raw.pop_front() # Remove method name

					var resolved_call_args = _resolve_complex_args(call_args_raw)

					if actor.has_method(real_method):
						var result = actor.callv(real_method, resolved_call_args)
						if result is GDScriptFunctionState:
							yield (result, "completed")
					else:
						printerr("[OYS] CALL Actor Error: Actor '%s' has no method '%s'" % [method, real_method])
				else:
					printerr("[OYS] CALL Actor Error: Missing method name for actor '%s'" % method)
			else:
				# STANDARD CALL (Legacy/Host/Prop)
				# Use generic complex arg resolution for standard calls too, improving flexibility
				var resolved_args = _resolve_complex_args(args)

				var target = _resolve_prop() # Try prop first
				if not target or not target.has_method(method):
					# Try PropStage / Current Scene
					var stage = _resolve_stage()
					if stage and stage != target and stage.has_method(method):
						target = stage
					else:
						target = host_node # Fallback to host

				if target and target.has_method(method):
					var result = target.callv(method, resolved_args)
					if result is GDScriptFunctionState:
						yield (result, "completed")
				else:
					printerr("[OYS] CALL failed: Method '%s' not found on %s" % [method, target.name])

		"SPAWN":
			# Route SPAWN through SessionManager/host so deterministic bookkeeping,
			# replay_sync registration and cleanup use a single code path.
			var sm = null
			if host_node and host_node.has_method("get_node_or_null"):
				sm = host_node.get_node_or_null("/root/SessionManager")
			if sm and sm.has_method("_handle_spawn_command"):
				sm.call("_handle_spawn_command", inst)
			elif host_node and host_node.has_method("_handle_spawn_command"):
				host_node.call("_handle_spawn_command", inst)
			else:
				var scene_path = inst.get("scene", "")
				var scene = load(scene_path)
				if scene:
					var obj = scene.instance()
					var parent = host_node.get_tree().current_scene
					if not parent:
						parent = host_node
					parent.add_child(obj)
					if inst.has("pos") and obj is Spatial:
						obj.global_transform.origin = OYS_Parser.parse_vector3(inst.pos)
		
		"SET_TIME_SCALE":
			Engine.time_scale = inst.get("value", 1.0)
		
		"WAIT", "WAIT_FRAMES":
			var wait_frames = _wait_frame_count_from_instruction(inst)
			# Fast forward still advances one frame at most, preserving coroutine sequencing.
			if fast_forward and wait_frames > 0:
				wait_frames = 1
			for _i in range(wait_frames):
				if stop_requested or my_id != execution_id:
					break
				if fast_forward and _i > 0:
					break
				yield (host_node.get_tree(), "physics_frame")
		
		"PRINT":
			var message = inst.get("message", "")
			message = _substitute_variables(message)
			print("[OYS PRINT] ", message)
			_log_to_console("OYS", message)
			_show_subtitle(message, Color.white, 2.5)

		"LOG":
			var tag = inst.get("tag", "OYS")
			var message = inst.get("message", "")
			var color = inst.get("color", "")
			message = _substitute_variables(message)
			_log_to_console(tag, message, color)


		"CLS":
			_clear_subtitles(false)
			
		"SCREENSHOT":
			var label = inst.get("label", "screenshot")
			var prop_name = "unknown"
			var prop = _resolve_prop()
			if prop:
				prop_name = prop.name

			# Hook for custom screenshot logic (e.g. Editor PropStage)
			var path = ""
			var stage = _resolve_stage()
			var screenshot_target = host_node
			
			# Priority: if a specialized PropStage exists, use its logic (it knows how to frame props)
			if stage and stage.has_method("take_oys_screenshot"):
				screenshot_target = stage
			elif not screenshot_target.has_method("take_oys_screenshot"):
				# Fallback is handled below
				pass

			if screenshot_target.has_method("take_oys_screenshot"):
				var result = yield (screenshot_target.take_oys_screenshot(label, prop_name), "completed")
				if result and result is String:
					path = result
			else:
				# Default Runtime Logic
				yield (VisualServer, "frame_post_draw")
				var img = host_node.get_viewport().get_texture().get_data()
				img.flip_y()
				
				var dir = Directory.new()
				var base_dir = "res://test_output/props/"
				if not prop:
					base_dir = "res://test_output/ui/"
				if not dir.dir_exists(base_dir):
					dir.make_dir_recursive(base_dir)
				if not prop:
					var cs = host_node.get_tree().current_scene
					if cs and cs.filename != "":
						prop_name = cs.filename.get_file().get_basename().to_lower()
					else:
						prop_name = "ui"
				path = base_dir + "%s_%s.png" % [prop_name, label]
				img.save_png(path)
				print("[OYS] Screenshot saved to: ", path)
		
		"CINEMATIC_START":
			var rig_id = inst.get("rig_id", "")
			var mode_str = inst.get("mode", "FREE")
			var mode = 0 # FREE
			match mode_str:
				"FREE": mode = 0
				"SIDESCROLL": mode = 1
				"LOCKED_VIEW": mode = 2
				"FIXED_AXIS": mode = 3

			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if manager:
				manager.activate_rig(rig_id, mode)

		"CINEMATIC_STOP":
			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if manager:
				manager.deactivate_rig()

		"CAMERA_SHAKE":
			_apply_camera_shake(inst)

		"CAMERA_SHAKE_STOP":
			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if manager and manager.has_method("stop_camera_shake"):
				manager.stop_camera_shake()

		"VCAMERA":
			var vcam_name = inst.get("name", "")
			var duration = _fast_forwarded_duration_seconds(float(inst.get("duration", 1.0)))
			var ease_type = inst.get("ease", -2.0)
			
			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if not manager:
				printerr("[OYS] VCAMERA: CinematicManager not found")
				return
			
			var vcam = manager.find_vcamera(vcam_name)
			if not vcam:
				printerr("[OYS] VCAMERA: VCamera '%s' not found" % vcam_name)
				return

			_configure_vcamera_targets(vcam, inst)
			_log_vcamera_debug(manager, "before_vcamera_%s" % vcam_name, vcam)
			manager.activate_vcamera(vcam, duration, ease_type)
			if float(duration) <= 0.0 and manager.has_method("step"):
				manager.step(0.0)
			else:
				yield (host_node.get_tree(), "physics_frame")
			_log_vcamera_debug(manager, "after_vcamera_%s" % vcam_name, vcam)

			for _i in range(_duration_to_wait_frames(duration)):
				if stop_requested: break
				if fast_forward and _i > 0:
					if manager and manager.has_method("force_finish_transition"):
						manager.force_finish_transition()
					break
				yield (host_node.get_tree(), "physics_frame")

		"VCAMERA_BLEND":
			var vcam_name = inst.get("name", "")
			var duration = _fast_forwarded_duration_seconds(float(inst.get("duration", 1.0)))
			
			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if not manager:
				printerr("[OYS] VCAMERA_BLEND: CinematicManager not found")
				return
			
			var vcam = manager.find_vcamera(vcam_name)
			if not vcam:
				printerr("[OYS] VCAMERA_BLEND: VCamera '%s' not found" % vcam_name)
				return

			_configure_vcamera_targets(vcam, inst)
			_log_vcamera_debug(manager, "before_blend_%s" % vcam_name, vcam)
			manager.blend_to_vcamera(vcam, duration)
			if float(duration) <= 0.0 and manager.has_method("step"):
				manager.step(0.0)
			else:
				yield (host_node.get_tree(), "physics_frame")
			_log_vcamera_debug(manager, "after_blend_%s" % vcam_name, vcam)

			for _i in range(_duration_to_wait_frames(duration)):
				if stop_requested: break
				if fast_forward and _i > 0:
					if manager and manager.has_method("force_finish_transition"):
						manager.force_finish_transition()
					break
				yield (host_node.get_tree(), "physics_frame")

		"VCAMERA_RETURN":
			var duration = _fast_forwarded_duration_seconds(float(inst.get("duration", 1.0)))
			
			var manager = host_node.get_node_or_null("/root/CinematicManager")
			if manager:
				_log_vcamera_debug(manager, "before_return")
				manager.deactivate_vcamera(duration)
				if float(duration) <= 0.0 and manager.has_method("step"):
					manager.step(0.0)
				else:
					yield (host_node.get_tree(), "physics_frame")
				_log_vcamera_debug(manager, "after_return")
			
			for _i in range(_duration_to_wait_frames(duration)):
				if stop_requested: break
				if fast_forward and _i > 0:
					if manager and manager.has_method("force_finish_transition"):
						manager.force_finish_transition()
					break
				yield (host_node.get_tree(), "physics_frame")

		"VCAMERA_SHAKE":
			# Kept for backwards compatibility; routed to the unified camera shake path.
			_apply_camera_shake(inst)

		"CINEMATIC":
			# Disable player input
			var player = _find_player()
			if player and "input_provider" in player and player.input_provider:
				player.input_provider.hardware_input_enabled = false
				
		"INTERACTIVE":
			# Enable player input and stop fast forward
			var player = _find_player()
			if player and "input_provider" in player and player.input_provider:
				player.input_provider.hardware_input_enabled = true
			fast_forward = false

		"RECORD_START":
			var recorder = _find_recorder()
			if recorder:
				recorder.start_recording()
			else:
				# Instantiate one if not found
				var FrameRecorder = load("res://core_v2/systems/FrameRecorder.gd")
				var new_recorder = FrameRecorder.new()
				new_recorder.name = "FrameRecorder"
				host_node.get_tree().root.add_child(new_recorder)
				new_recorder.start_recording()

		"RECORD_STOP":
			var recorder = _find_recorder()
			if recorder:
				recorder.stop_recording()

		"ASSERT":
			var assert_result = _execute_assert(inst.get("condition", ""))
			if assert_result.get("evaluated", false):
				var msg = String(assert_result.get("message", "Assertion"))
				if bool(assert_result.get("passed", false)):
					print("[OYS ASSERT] OK: %s" % msg)
					_log_to_console("ASSERT_OK", msg)
					_show_subtitle("ASSERT OK: %s" % msg, Color(0.35, 1.0, 0.35), 2.5)
				else:
					var fail_text = "ASSERT FAIL: %s (%s %s %s)" % [
						msg,
						str(assert_result.get("left")),
						str(assert_result.get("op")),
						str(assert_result.get("right"))
					]
					_log_to_console("ASSERT_FAIL", fail_text)
					_show_subtitle(fail_text, Color(1.0, 0.35, 0.35), 3.0)
			if not bool(assert_result.get("passed", true)):
				test_failed = true
				stop_requested = true
				is_running = false
				return
				
		"ASSERT_NO_HAND_CLIPPING":
			var box_name = inst.get("box", "")
			var _max_pen = inst.get("max_penetration", 0.05)
			var monitor_duration = inst.get("monitor_duration", 0.0)
			var is_monitoring = (monitor_duration > 0.0)
			var consecutive_frames = int(inst.get("consecutive_frames", 0))
			# In monitored mode, require sustained clipping to avoid 1-frame physics jitter false positives.
			if consecutive_frames <= 0:
				consecutive_frames = 5 if is_monitoring else 1
			var clipping_streak = 0
			
			var box = host_node.find_node(box_name, true, false)
			var player = _find_player()
			
			if not box:
				printerr("[OYS] ASSERT_NO_HAND_CLIPPING failed: Box '%s' not found" % box_name)
				test_failed = true
				stop_requested = true
				return
				
			if not player:
				printerr("[OYS] ASSERT_NO_HAND_CLIPPING failed: Player not found")
				test_failed = true
				stop_requested = true
				return

			# Find Skeleton and Bones
			var skeleton = player.find_node("Skeleton", true, false)
			if not skeleton:
				printerr("[OYS] ASSERT_NO_HAND_CLIPPING failed: Skeleton node not found on player")
				test_failed = true
				stop_requested = true
				return
			
			if not (skeleton is Skeleton):
				var real_skeleton = null
				for c in skeleton.get_children():
					if c is Skeleton:
						real_skeleton = c
						break
				if not real_skeleton:
					real_skeleton = _find_node_by_type(player, Skeleton)
				if real_skeleton:
					skeleton = real_skeleton
				else:
					printerr("[OYS] ASSERT_NO_HAND_CLIPPING failed: Node 'Skeleton' not a Skeleton instance.")
					test_failed = true
					stop_requested = true
					return
				
			var left_hand_idx = 1
			var right_hand_idx = 2
			
			var lh_bone = skeleton.find_bone("Hand.L")
			var rh_bone = skeleton.find_bone("Hand.R")
			if lh_bone != -1: left_hand_idx = lh_bone
			else: left_hand_idx = 12
			if rh_bone != -1: right_hand_idx = rh_bone
			else: right_hand_idx = 22
			
			# Monitor Loop
			var time_monitored = 0.0
			# If monitor_duration > 0, we loop. If 0, we run once.
			# But to simplify structure, we can treat 0 as "run once loop" or just a single pass.
			# BLEND usually expects a yieldable function state or return null if done immediately.
			# If monitor_duration > 0, we MUST yield.
			
			var _iterations = 1
			
			while true:
				if not is_instance_valid(skeleton) or not is_instance_valid(box):
					break

				var lh_transform = skeleton.get_bone_global_pose(left_hand_idx)
				var rh_transform = skeleton.get_bone_global_pose(right_hand_idx)
				
				var lh_world_pos = skeleton.global_transform.xform(lh_transform.origin)
				var rh_world_pos = skeleton.global_transform.xform(rh_transform.origin)
				
				# Box Check
				var _box_shape_owner = box.shape_find_owner(0)
				var col_shape = box.find_node("CollisionShape", true, false)
				if col_shape and col_shape.shape:
					var shape = col_shape.shape
					var lh_local = box.global_transform.xform_inv(lh_world_pos)
					var rh_local = box.global_transform.xform_inv(rh_world_pos)
					
					var is_clipping = false
					
					if shape is BoxShape:
						var extents = shape.extents
						# Shrink bounds by max_penetration to allow some leeway
						# If point is inside the ORIGINAL box but outside the SHRUNK box, it is within tolerance.
						# We only fail if it is inside the SHRUNK box (too deep).
						var safe_extents = extents - Vector3(_max_pen, _max_pen, _max_pen)
						# Ensure we don't invert shapes if they are thinner than tolerance
						safe_extents.x = max(0.0, safe_extents.x)
						safe_extents.y = max(0.0, safe_extents.y)
						safe_extents.z = max(0.0, safe_extents.z)
						
						var bounds = AABB(-safe_extents, safe_extents * 2.0)
						
						if bounds.has_point(lh_local):
							print("[OYS FAILURE] Left Hand Clipping! LocalPos: ", lh_local)
							is_clipping = true
						if bounds.has_point(rh_local):
							print("[OYS FAILURE] Right Hand Clipping! LocalPos: ", rh_local)
							is_clipping = true
						
					if is_clipping:
						clipping_streak += 1
						if clipping_streak >= consecutive_frames:
							test_failed = true
							stop_requested = true
							printerr("[OYS] ASSERT_NO_HAND_CLIPPING Failed: Hands are inside the box for %d consecutive frames." % clipping_streak)
							return
					else:
						clipping_streak = 0
				
				if not is_monitoring:
					break
				
				time_monitored += host_node.get_physics_process_delta_time()
				if time_monitored >= monitor_duration:
					break
				
				yield (host_node.get_tree(), "physics_frame")
			
			print("[OYS] ASSERT_NO_HAND_CLIPPING PASSED (Duration: %.2fs)" % time_monitored)

		"SET":
			var var_name = inst.get("var", "")
			var value = null
			if inst.has("func"):
				var func_name = str(inst.get("func", ""))
				var raw_args = inst.get("args", [])
				var resolved_args = _resolve_complex_args(raw_args if raw_args is Array else [])
				value = _call_func(func_name, resolved_args)
			else:
				var val_raw = inst.get("value", null)
				value = _resolve_value(val_raw)
			variables[var_name] = value

			# If it's a world property (like 'pos'), tell the host to handle it
			if not var_name.begins_with("$"):
				var handled = false
				if host_node and host_node.has_method("_handle_set_command"):
					host_node._handle_set_command(inst)
					handled = true
				
				if not handled:
					var sm = _find_session_manager()
					if sm and sm != host_node and sm.has_method("_handle_set_command"):
						sm._handle_set_command(inst)
		
		"GET_NODES_IN_GROUP":
			var group = inst.get("group", "")
			var target_var = inst.get("target", "")
			variables[target_var] = host_node.get_tree().get_nodes_in_group(group).size()
		
		# Movement commands - apply to player's input provider
		"FW", "BW", "LEFT", "RIGHT", "JUMP", "INTERACT":
			var __state = _execute_movement(inst, my_id)
			if __state is GDScriptFunctionState:
				yield (__state, "completed")
		
		"LOOK":
			var __state_look = _execute_look(inst, my_id)
			if __state_look is GDScriptFunctionState:
				yield (__state_look, "completed")
		
		"ZOOM":
			var __state_zoom = _execute_zoom(inst, my_id)
			if __state_zoom is GDScriptFunctionState:
				yield (__state_zoom, "completed")
		
		"FOV":
			var __state_fov = _execute_fov(inst, my_id)
			if __state_fov is GDScriptFunctionState:
				yield (__state_fov, "completed")
				
		"TELEPORT":
			var pos_val = inst.get("pos", "")
			var pos_vec = _resolve_value(pos_val)
			
			# If resolved value is a string (e.g. "(1,2,3)"), parse it as Vector3
			if typeof(pos_vec) == TYPE_STRING:
				pos_vec = OYS_Parser.parse_vector3(pos_vec)
			
			var sm = _find_session_manager()
			var player = _find_player()
			
			if typeof(pos_vec) == TYPE_VECTOR3 and player:
				print("[OYS TELEPORT] Teleporting player to: ", pos_vec)
				if player.has_method("teleport_to"):
					var tf = player.global_transform
					tf.origin = pos_vec
					player.teleport_to(tf)
				else:
					player.global_transform.origin = pos_vec
					if "velocity" in player: player.velocity = Vector3.ZERO
				
				# Update SessionManager tracking if possible
				if sm and sm.has_method("force_initial_spawn"):
					# Note: teleport_to usually handles this internally via TeleportSystem
					pass
			else:
				printerr("[OYS TELEPORT] Failed: Invalid position or no player found. Pos: ", pos_vec)
		
		# Markers - no action needed
		"LEVEL", "END":
			pass
		
		"MATH":
			var var_name = inst.get("var", "")
			var expression = inst.get("expression", "")
			var result = 0.0
			
			var expr_parts = Array(expression.split(" ", false))
			
			# Handle optional "=" assignment prefix (e.g. MATH $x = 5)
			if expr_parts.size() > 0 and expr_parts[0] == "=":
				expr_parts.pop_front()
			
			if expr_parts.size() == 1:
				# Simple assignment: MATH $x 5  OR  MATH $x = 5
				result = _resolve_value(expr_parts[0])
			
			elif expr_parts.size() == 2:
				# In-place modification: MATH $x + 1
				var op = expr_parts[0]
				var right_val = _resolve_value(expr_parts[1])
				
				if op in ["+", "-", "*", "/"]:
					var left_val = variables.get(var_name, 0.0)
					match op:
						"+": result = _to_number(left_val) + _to_number(right_val)
						"-": result = _to_number(left_val) - _to_number(right_val)
						"*": result = _to_number(left_val) * _to_number(right_val)
						"/":
							var right_num = _to_number(right_val)
							if right_num != 0.0:
								result = _to_number(left_val) / right_num
			
			elif expr_parts.size() == 3:
				# Full expression: MATH $z = $x + $y
				var left = _resolve_value(expr_parts[0])
				var inner_op = expr_parts[1]
				var right = _resolve_value(expr_parts[2])
				match inner_op:
					"+": result = _to_number(left) + _to_number(right)
					"-": result = _to_number(left) - _to_number(right)
					"*": result = _to_number(left) * _to_number(right)
					"/":
						var right_num = _to_number(right)
						if right_num != 0.0:
							result = _to_number(left) / right_num
			
			variables[var_name] = result
		
		"GET_POS":
			var player = _find_player()
			if player and is_instance_valid(player):
				var pos = Vector3.ZERO
				if player is Spatial:
					pos = player.global_transform.origin
				elif player is Node2D:
					pos = Vector3(player.position.x, player.position.y, 0)
				
				if inst.has("x"): variables[inst.x] = pos.x
				if inst.has("y"): variables[inst.y] = pos.y
				if inst.has("z"): variables[inst.z] = pos.z

		"FOR":
			var current_pc = pc - 1
			var iterations = int(inst.get("iterations", 1))

			if loop_runtime_stack.empty() or loop_runtime_stack.back().get("start_pc") != current_pc:
				# Start new loop
				if iterations > 0:
					loop_runtime_stack.push_back({
						"type": "FOR",
						"start_pc": current_pc,
						"remaining": iterations - 1
					})
				else:
					# Skip loop entirely
					var end_index = inst.get("end_index", -1)
					if end_index != -1:
						pc = end_index + 1
			else:
				# Continue existing loop
				var context = loop_runtime_stack.back()
				if context.remaining > 0:
					context.remaining -= 1
				else:
					# Finished
					loop_runtime_stack.pop_back()
					var end_index = inst.get("end_index", -1)
					if end_index != -1:
						pc = end_index + 1

		"ENDFOR":
			# Jump back to start
			var start_index = inst.get("start_index", -1)
			if start_index != -1:
				pc = start_index

		"WHILE":
			# Check condition
			var condition_met = false

			if inst.has("prop_type") and inst.prop_type == "PROP":
				# WHILE PROP "Door" is_active == false
				var target_name = inst.get("target", "")
				var prop_name = inst.get("property", "")
				var op = inst.get("op", "==")
				var expected_val = _resolve_value(inst.get("value", ""))

				# Find prop
				var prop = null
				if target_name == "current_prop":
					prop = _resolve_prop()
				else:
					prop = _resolve_node(target_name)

				if prop:
					var actual_val = null
					if prop_name in prop:
						actual_val = prop.get(prop_name)
					elif prop.has_method("get_" + prop_name):
						actual_val = prop.call("get_" + prop_name)

					condition_met = _compare(actual_val, op, expected_val)
				else:
					printerr("[OYS_Interpreter] WHILE PROP: Target not found: ", target_name)
					condition_met = false
			else:
				# Generic condition
				var left = _resolve_value(inst.get("left", ""))
				var right = _resolve_value(inst.get("right", ""))
				var op = inst.get("op", "==")
				condition_met = _compare(left, op, right)

			if not condition_met:
				# Jump to end
				var end_index = inst.get("end_index", -1)
				if end_index != -1:
					pc = end_index + 1
				else:
					printerr("[OYS_Interpreter] WHILE without ENDWHILE linked")

		"ENDWHILE":
			# Jump back to start
			var start_index = inst.get("start_index", -1)
			if start_index != -1:
				pc = start_index
	
	return null

func _wait_frame_count_from_instruction(inst: Dictionary) -> int:
	var unit = String(inst.get("unit", "s")).to_lower()
	var value = max(0.0, float(inst.get("value", 0.0)))
	if unit in ["frames", "frame", "f"]:
		var frame_count = int(round(value))
		return frame_count if frame_count > 0 else 0
	# Deterministic conversion: seconds -> fixed 60 Hz frames.
	var wait_frames = int(ceil(value * OYS_Parser.FPS))
	return wait_frames if wait_frames > 0 else 0

func _duration_to_wait_frames(duration_sec: float) -> int:
	var duration = max(0.0, duration_sec)
	var frames = int(ceil(duration * OYS_Parser.FPS))
	return frames if frames > 0 else 0

func _fast_forwarded_duration_seconds(duration_sec: float) -> float:
	var duration = max(0.0, duration_sec)
	if not fast_forward:
		return duration
	# For skip flow we want hard cuts (no transitional camera pose lingering).
	return 0.0

func _execute_movement(inst: Dictionary, my_id: int):
	var cmd = inst.command
	var player = _find_player()
	if not player:
		return
	
	var duration_sec = 0.0
	var move_vec = Vector2.ZERO
	var is_sprint = inst.get("is_running", true)
	var is_jump = false

	
	var is_interact = false
	
	match cmd:
		"FW", "BW":
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			duration_sec = value
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(value, is_sprint)
			# Standard Godot Convention: -1 is Forward, 1 is Backward
			move_vec = Vector2(0, -1) if cmd == "FW" else Vector2(0, 1)
			print("[OYS_Interpreter] Executing ", cmd, ". Move Vec: ", move_vec)
		
		"LEFT", "RIGHT":
			if inst.get("is_turning", false):
				# For turning, we'll handle it separately
				var __state_turn = _execute_turn(inst, my_id)
				if __state_turn is GDScriptFunctionState:
					yield (__state_turn, "completed")
				return
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			duration_sec = value
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(value, is_sprint)
			# Standard Godot Convention: -1 is Left, 1 is Right
			move_vec = Vector2(-1, 0) if cmd == "LEFT" else Vector2(1, 0)
		
		"JUMP":
			duration_sec = inst.get("duration", 0.1)
			is_jump = true
		
		"INTERACT":
			var target_name = inst.get("target", "")
			var target_node = null
			
			if target_name != "":
				# Priority 1: Check if "target_name" is a path relative to the current prop
				var prop = _resolve_prop()
				if prop and is_instance_valid(prop):
					target_node = prop.get_node_or_null(target_name)
				
				# Priority 2: Keywords
				if not target_node:
					if target_name == "prop" or target_name == "current_prop":
						target_node = prop
					else:
						# Priority 3: Global/Scene search via improved _resolve_node
						target_node = _resolve_node(target_name)
				
				if target_node:
					if target_node.has_method("interact"):
						print("[OYS] Direct INTERACT with ", target_node.name)
						target_node.interact()
					else:
						print("[OYS WARNING] Target ", target_node.name, " has no interact() method.")
				else:
					print("[OYS WARNING] Could not find target '", target_name, "' for INTERACT.")
				
				# Wait one frame and return (no large-scale input injection)
				yield (host_node.get_tree(), "physics_frame")
				return
			else:
				# Default: No target. In PropStage, target the prop itself.
				var stage = _resolve_stage()
				var prop = _resolve_prop()
				if stage and prop and is_instance_valid(prop) and prop.has_method("interact"):
					print("[OYS] No INTERACT target specified in PropStage. Interacting with current_prop: ", prop.name)
					prop.interact()
					yield (host_node.get_tree(), "physics_frame")
					return
				
				# Default Fallback: Inject Input to Player
				duration_sec = 1.0 / 60.0
				is_interact = true
	
	# Scale duration by TimeScale so movements are slower in slow-mo
	var time_scale = Engine.time_scale
	if time_scale <= 0.001: time_scale = 1.0 # Avoid divide by zero
	
	# Real duration = Game Duration / Scale (e.g. 0.5s / 0.1 = 5.0s real time)
	var real_duration = duration_sec / time_scale
	
	var num_frames = OYS_Parser.duration_to_frames(real_duration)
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		if not is_instance_valid(player):
			break
		_post_oys_input({
			"move_vec": [move_vec.x, move_vec.y],
			"sprint": is_sprint,
			"jump": is_jump,
			"interact": is_interact
		})
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

	_post_oys_input({
		"move_vec": [0.0, 0.0],
		"sprint": false,
		"jump": false,
		"interact": false
	})

func _execute_turn(inst: Dictionary, my_id: int):
	var value = inst.get("value", 0.0)
	var direction = inst.get("direction", "LEFT")
	var duration_sec = inst.get("duration", 0.5)
	
	# Scale duration by TimeScale
	var time_scale = Engine.time_scale
	if time_scale <= 0.001: time_scale = 1.0
	var real_duration = duration_sec / time_scale
	
	var num_frames = OYS_Parser.duration_to_frames(real_duration)
	
	var sensitivity = 0.005
	var pixels_total = (value * PI / 180.0) / sensitivity
	var mouse_dx = - pixels_total / num_frames if direction == "LEFT" else pixels_total / num_frames
	
	var player = _find_player()
	if not player:
		return
	
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		
		# Verify player is still valid
		if not is_instance_valid(player):
			break
		
		_post_oys_input({"mouse_delta": [mouse_dx, 0]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")
	
	# Clear turn input after finishing
	_post_oys_input({
		"mouse_delta": [0.0, 0.0]
	})

func _execute_look(inst: Dictionary, my_id: int):
	var pitch = inst.get("pitch", 0.0)
	var duration_sec = inst.get("duration", 0.5)
	
	# Scale by TimeScale
	var time_scale = Engine.time_scale
	if time_scale <= 0.001: time_scale = 1.0
	var real_duration = duration_sec / time_scale
	
	var num_frames = OYS_Parser.duration_to_frames(real_duration)
	var sensitivity = 0.005
	var pixels_total = (pitch * PI / 180.0) / sensitivity
	var mouse_dy = - pixels_total / num_frames
	
	var player = _find_player()
	if not player:
		return
	
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		
		# Verify player is still valid
		if not is_instance_valid(player):
			break
		
		_post_oys_input({"mouse_delta": [0, mouse_dy]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")
	
	# Clear look input after finishing
	_post_oys_input({
		"mouse_delta": [0.0, 0.0]
	})

func _execute_zoom(inst: Dictionary, my_id: int):
	var amount = inst.get("amount", 0.0)
	var duration_sec = inst.get("duration", 0.5)
	
	# Scale by TimeScale
	var time_scale = Engine.time_scale
	if time_scale <= 0.001: time_scale = 1.0
	var real_duration = duration_sec / time_scale
	
	var num_frames = OYS_Parser.duration_to_frames(real_duration)
	if num_frames <= 0: num_frames = 1
	var delta_per_frame = amount / num_frames
	
	var player = _find_player()
	if not player:
		return
	
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		if not is_instance_valid(player):
			break
		_post_oys_input({"zoom_delta": delta_per_frame})
		
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

	_post_oys_input({"zoom_delta": 0.0})

func _execute_fov(inst: Dictionary, my_id: int):
	var target_fov = inst.get("fov", 75.0)
	var duration_sec = inst.get("duration", 0.5)
	
	# Scale by TimeScale
	var time_scale = Engine.time_scale
	if time_scale <= 0.001: time_scale = 1.0
	var real_duration = duration_sec / time_scale
	
	var num_frames = OYS_Parser.duration_to_frames(real_duration)
	if num_frames <= 0: num_frames = 1
	
	var player = _find_player()
	if not player:
		return
	
	var start_fov = 75.0
	if "base_fov" in player:
		start_fov = player.base_fov
	
	for i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		if not is_instance_valid(player):
			break
		
		var t = (i + 1.0) / (num_frames + 0.0)
		var current_fov = lerp(start_fov, target_fov, t)
		_post_oys_input({"fov_override": current_fov})
		
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")
	
	_post_oys_input({"fov_override": target_fov})

func _find_recorder() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	return host_node.get_tree().root.find_node("FrameRecorder", true, false)

func _find_session_manager() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	return host_node.get_node_or_null("/root/SessionManager")

func _resolve_complex_args(raw_args: Array) -> Array:
	var final_args = []
	var i = 0
	while i < raw_args.size():
		var val = raw_args[i]

		# Resolve variables first if needed, but Vector construction needs strings
		var resolved_val = _resolve_value(val)

		# If it resolved to a non-string (e.g. number from variable), use it directly
		if typeof(resolved_val) != TYPE_STRING:
			final_args.append(resolved_val)
			i += 1
			continue

		val = resolved_val # It's a string

		# Detect split vector "[x, y, z]" start
		if val.begins_with("[") and not val.ends_with("]"):
			var built = val
			var j = i + 1
			var completed = false
			while j < raw_args.size():
				var next_val = raw_args[j]
				# Resolve next parts too if they are variables? usually vectors are literal in OYS
				# But let's assume literal for vector components for now to keep simple
				built += "" + str(next_val)
				if str(next_val).ends_with("]"):
					completed = true
					i = j
					break
				j += 1

			if completed:
				final_args.append(_parse_vector3_flexible(built))
			else:
				final_args.append(val)

		# Detect single string vector "[x,y,z]"
		elif val.begins_with("[") and val.ends_with("]"):
			final_args.append(_parse_vector3_flexible(val))
		else:
			# It's a regular string value
			final_args.append(val)

		i += 1
	return final_args

func _parse_vector3_flexible(s: String) -> Vector3:
	var cleaned = s.replace("[", "").replace("]", "").replace("(", "").replace(")", "").strip_edges()
	var parts = cleaned.split(",")
	if parts.size() >= 3:
		return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	return Vector3.ZERO

func _find_player() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return _find_player_under_node(host_node)
	
	# Priority 1: Prefer SessionManager.player (primary source of truth)
	var session = host_node.get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session):
		if session.has_method("get"):
			var p = session.get("player")
			if p and is_instance_valid(p):
				return p
		# Fallback for older SessionManager versions using property directly
		elif "player" in session and is_instance_valid(session.player):
			return session.player

	# Priority 2: Host-local player lookup (more deterministic for tests and local scenes)
	var local_player = _find_player_under_node(host_node)
	if local_player:
		return local_player

	# Priority 3: Standard group lookup
	var players = host_node.get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			return p

	# Priority 4: Global name lookup
	var player = host_node.get_tree().root.find_node("Pilot", true, false)
	return player

func _find_player_under_node(root: Node) -> Node:
	if not root or not is_instance_valid(root):
		return null

	var pending: Array = [root]
	while not pending.empty():
		var current = pending.pop_front()
		if not current or not is_instance_valid(current):
			continue
		if current.is_in_group("player") and not current.is_queued_for_deletion():
			return current
		for child in current.get_children():
			pending.push_back(child)

	var by_name = root.find_node("Pilot", true, false)
	if by_name and is_instance_valid(by_name) and not by_name.is_queued_for_deletion():
		return by_name
	return null

func _find_first_animation_player(root: Node) -> AnimationPlayer:
	if not root or not is_instance_valid(root):
		return null
	var pending: Array = [root]
	while not pending.empty():
		var current = pending.pop_front()
		if not current or not is_instance_valid(current):
			continue
		if current is AnimationPlayer:
			return current as AnimationPlayer
		for child in current.get_children():
			pending.push_back(child)
	return null

func _apply_camera_shake(inst: Dictionary) -> void:
	var manager = host_node.get_node_or_null("/root/CinematicManager")
	if not manager or not manager.has_method("trigger_camera_shake"):
		return

	var duration := float(inst.get("duration", 0.35))
	var frequency := float(inst.get("frequency", 28.0))

	if inst.has("translation") or inst.has("rotation"):
		var trans := OYS_Parser.parse_vector3(String(inst.get("translation", "(0, 0, 0)")))
		var rot := OYS_Parser.parse_vector3(String(inst.get("rotation", "(0, 0, 0)")))
		var intensity := float(inst.get("intensity", 1.0))
		var amplitude := max(abs(trans.x), max(abs(trans.y), abs(trans.z))) * intensity
		var roll_deg := max(abs(rot.x), max(abs(rot.y), abs(rot.z))) * intensity
		manager.trigger_camera_shake(duration, amplitude, frequency, roll_deg)
		return

	manager.trigger_camera_shake(
		duration,
		float(inst.get("amplitude", 0.08)),
		frequency,
		float(inst.get("roll", 1.0))
	)

func _is_vcamera_target_clear_token(raw: String) -> bool:
	var key := raw.strip_edges().to_lower()
	return key in ["", "none", "off", "null", "false", "0"]

func _resolve_vcamera_target(raw: String) -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	var token := raw.strip_edges().replace("\"", "")
	if token == "":
		return null
	var lower := token.to_lower()
	if lower in ["player", "pilot"]:
		return _find_player()

	var tree := host_node.get_tree()
	if token.begins_with("/"):
		return tree.root.get_node_or_null(token)

	var current_scene := tree.current_scene
	if is_instance_valid(current_scene):
		var node := current_scene.get_node_or_null(token)
		if node:
			return node
		node = current_scene.find_node(token, true, false)
		if node:
			return node

	return tree.root.find_node(token, true, false)

func _configure_vcamera_targets(vcam: Node, inst: Dictionary) -> void:
	if not is_instance_valid(vcam):
		return

	_cache_vcamera_scene_defaults(vcam)
	var mode := String(inst.get("mode", "script")).to_lower()
	if mode == "scene":
		_restore_vcamera_scene_defaults(vcam)
		return

	if inst.has("follow"):
		var follow_raw := String(inst.get("follow", ""))
		var follow_mod = vcam.get_node_or_null("Follow")
		if follow_mod and "target" in follow_mod:
			if _is_vcamera_target_clear_token(follow_raw):
				follow_mod.target = null
			else:
				var follow_target = _resolve_vcamera_target(follow_raw)
				if follow_target and follow_target is Spatial:
					follow_mod.target = follow_target
				else:
					printerr("[OYS] VCAMERA: follow target '%s' not found or not Spatial" % follow_raw)

	if inst.has("look_at"):
		var look_raw := String(inst.get("look_at", ""))
		var look_mod = vcam.get_node_or_null("LookAt")
		if look_mod and "look_at_target" in look_mod:
			if _is_vcamera_target_clear_token(look_raw):
				look_mod.look_at_target = NodePath("")
			else:
				var look_target = _resolve_vcamera_target(look_raw)
				if look_target and look_target.is_inside_tree():
					look_mod.look_at_target = look_target.get_path()
				else:
					printerr("[OYS] VCAMERA: look_at target '%s' not found" % look_raw)

func _cache_vcamera_scene_defaults(vcam: Node) -> void:
	if not is_instance_valid(vcam):
		return
	var key := vcam.get_instance_id()
	var has_existing := _vcam_scene_defaults.has(key)
	var data: Dictionary = _vcam_scene_defaults.get(key, {
		"follow_target_path": NodePath(""),
		"look_at_target": NodePath(""),
		"vcam_transform": null,
		"follow_transform": null,
		"look_at_transform": null
	})

	var has_scene_follow_meta := vcam.has_meta("scene_follow_target_path")
	if has_scene_follow_meta:
		data["follow_target_path"] = vcam.get_meta("scene_follow_target_path")

	var follow_mod = vcam.get_node_or_null("Follow")
	if follow_mod and "target_path" in follow_mod:
		# Strictly preserve the editor scene value (target_path), never infer from runtime target.
		if not has_scene_follow_meta and not has_existing:
			data["follow_target_path"] = follow_mod.target_path
	if vcam.has_meta("scene_follow_transform"):
		data["follow_transform"] = vcam.get_meta("scene_follow_transform")
	elif follow_mod and follow_mod is Spatial and not has_existing:
		data["follow_transform"] = (follow_mod as Spatial).transform

	var has_scene_look_meta := vcam.has_meta("scene_look_at_target")
	if has_scene_look_meta:
		data["look_at_target"] = vcam.get_meta("scene_look_at_target")

	var look_mod = vcam.get_node_or_null("LookAt")
	if look_mod and "look_at_target" in look_mod:
		if not has_scene_look_meta and not has_existing:
			data["look_at_target"] = look_mod.look_at_target
	if vcam.has_meta("scene_look_at_transform"):
		data["look_at_transform"] = vcam.get_meta("scene_look_at_transform")
	elif look_mod and look_mod is Spatial and not has_existing:
		data["look_at_transform"] = (look_mod as Spatial).transform

	if vcam is Spatial:
		if vcam.has_meta("scene_vcam_transform"):
			data["vcam_transform"] = vcam.get_meta("scene_vcam_transform")
		elif not has_existing:
			data["vcam_transform"] = (vcam as Spatial).global_transform

	_vcam_scene_defaults[key] = data

func _restore_vcamera_scene_defaults(vcam: Node) -> void:
	if not is_instance_valid(vcam):
		return
	var key := vcam.get_instance_id()
	if not _vcam_scene_defaults.has(key):
		return
	var data: Dictionary = _vcam_scene_defaults[key]

	var follow_mod = vcam.get_node_or_null("Follow")
	if follow_mod and "target" in follow_mod:
		var follow_path: NodePath = data.get("follow_target_path", NodePath(""))
		if "target_path" in follow_mod:
			follow_mod.target_path = follow_path
		var restored_follow_target: Node = null
		if String(follow_path) != "":
			restored_follow_target = follow_mod.get_node_or_null(follow_path)
		follow_mod.target = restored_follow_target
		if follow_mod is Spatial and data.get("follow_transform", null) != null:
			(follow_mod as Spatial).transform = data["follow_transform"]

	var look_mod = vcam.get_node_or_null("LookAt")
	if look_mod and "look_at_target" in look_mod:
		look_mod.look_at_target = data.get("look_at_target", NodePath(""))
		if look_mod is Spatial and data.get("look_at_transform", null) != null:
			(look_mod as Spatial).transform = data["look_at_transform"]
		if look_mod is Spatial and "rotation_internal" in look_mod:
			look_mod.rotation_internal = Quat((look_mod as Spatial).global_transform.basis)

	if vcam is Spatial and data.has("vcam_transform") and data["vcam_transform"] != null:
		(vcam as Spatial).global_transform = data["vcam_transform"]

func _node_pos_dbg(node: Node) -> String:
	if not is_instance_valid(node):
		return "<null>"
	if node is Spatial:
		var p: Vector3 = (node as Spatial).global_transform.origin
		return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]
	return "<non-spatial>"

func _vcam_follow_dbg(vcam: Node) -> String:
	if not is_instance_valid(vcam):
		return "<none>"
	var follow = vcam.get_node_or_null("Follow")
	if not follow:
		return "<no_follow>"
	if "target" in follow:
		var t = follow.target
		if is_instance_valid(t):
			return t.name
	if "target_path" in follow:
		return String(follow.target_path)
	return "<empty>"

func _vcam_look_dbg(vcam: Node) -> String:
	if not is_instance_valid(vcam):
		return "<none>"
	var look_mod = vcam.get_node_or_null("LookAt")
	if not look_mod:
		return "<no_lookat>"
	if "look_at_target" in look_mod:
		return String(look_mod.look_at_target)
	return "<empty>"

func _log_vcamera_debug(manager: Node, label: String, requested_vcam: Node = null) -> void:
	if not manager or not is_instance_valid(manager):
		return
	if OS.get_environment("ODISEA_VCAM_DEBUG").to_lower() != "1":
		return
	var player = _find_player()
	var active_vcam: Node = null
	if manager.has_method("get_active_vcamera"):
		active_vcam = manager.get_active_vcamera()
	var active_cam: Node = null
	if manager.has_method("get_active_camera"):
		active_cam = manager.get_active_camera()
	var state := -1
	if manager.has_method("get"):
		state = int(manager.get("_current_state"))
	print("[OYS][VCAM_DEBUG] %s state=%d player=%s requested=%s req_pos=%s req_follow=%s req_look=%s active_vcam=%s active_vcam_pos=%s active_follow=%s active_look=%s active_cam=%s active_cam_pos=%s" % [
		label,
		state,
		_node_pos_dbg(player),
		requested_vcam.name if is_instance_valid(requested_vcam) else "<none>",
		_node_pos_dbg(requested_vcam),
		_vcam_follow_dbg(requested_vcam),
		_vcam_look_dbg(requested_vcam),
		active_vcam.name if is_instance_valid(active_vcam) else "<none>",
		_node_pos_dbg(active_vcam),
		_vcam_follow_dbg(active_vcam),
		_vcam_look_dbg(active_vcam),
		active_cam.name if is_instance_valid(active_cam) else "<none>",
		_node_pos_dbg(active_cam)
	])

func _interrupt_animation_player(anim_player_node: AnimationPlayer) -> void:
	if not anim_player_node or not is_instance_valid(anim_player_node):
		return
	if anim_player_node.is_playing():
		anim_player_node.stop(false)

func _interrupt_running_animation() -> void:
	var player = _find_player()
	if not player or not is_instance_valid(player):
		return

	# Prefer animator-level interruption so AnimationTree state gets restored.
	var pivot = player.get_node_or_null("Visual/Pivot")
	if pivot and is_instance_valid(pivot) and pivot.has_method("stop_override_animation"):
		pivot.call("stop_override_animation")
		return

	# Fallback for scenes without PilotAnimatorV2 API.
	var anim = _find_first_animation_player(player)
	if anim:
		_interrupt_animation_player(anim)

func _post_oys_input(data: Dictionary):
	if not host_node: return
	var session = host_node.get_node_or_null("/root/SessionManager")
	if not session: return
	
	if session.get("is_recording"):
		if not session.get("_oys_input_override"):
			session.set("_oys_input_override", {})
		var override = session.get("_oys_input_override")
		for key in data:
			var val = data[key]
			if key == "mouse_delta":
				# BLEND can run turn + look in parallel; combine both axes instead of overwriting.
				var current = override.get("mouse_delta", [0.0, 0.0])
				var cur_x = 0.0
				var cur_y = 0.0
				if typeof(current) == TYPE_ARRAY and current.size() >= 2:
					cur_x = float(current[0])
					cur_y = float(current[1])
				var inc_x = 0.0
				var inc_y = 0.0
				if typeof(val) == TYPE_ARRAY and val.size() >= 2:
					inc_x = float(val[0])
					inc_y = float(val[1])
				override[key] = [cur_x + inc_x, cur_y + inc_y]
			else:
				# Overwrite for non-vector fields.
				override[key] = val
	else:
		# Compatibility logic for other host types if any
		var player = _find_player()
		if player and is_instance_valid(player) and player.has_method("inject_input"):
			player.inject_input(data)
		else:
			print("[OYS WARNING] Could not find player to inject input: ", data)

func _resolve_node(path: String) -> Node:
	if _node_cache.has(path):
		var cached = _node_cache[path]
		if is_instance_valid(cached) and cached.is_inside_tree():
			return cached
		else:
			_node_cache.erase(path)

	# 1. Try resolving relative to host
	var node = host_node.get_node_or_null(path)
	
	# 2. Try resolving relative to current prop (for props validation)
	if not is_instance_valid(node):
		var prop = _resolve_prop()
		if prop and is_instance_valid(prop):
			node = prop.get_node_or_null(path)
			
	# 3. Try resolving relative to stage
	if not is_instance_valid(node):
		var stage = _resolve_stage()
		if stage and is_instance_valid(stage):
			node = stage.get_node_or_null(path)

	# 4. Global scene search (recursive by name if it doesn't look like a path, otherwise relative to scene root)
	if not is_instance_valid(node) and host_node.is_inside_tree():
		var scene = host_node.get_tree().current_scene
		if is_instance_valid(scene):
			node = scene.get_node_or_null(path)
			if not is_instance_valid(node) and path.find("/") == -1:
				node = scene.find_node(path, true, false)
	
	# 5. Root search (last resort)
	if not is_instance_valid(node) and host_node.is_inside_tree():
		node = host_node.get_tree().root.get_node_or_null(path)
		if not is_instance_valid(node) and path.find("/") == -1:
			node = host_node.get_tree().root.find_node(path, true, false)

	if is_instance_valid(node):
		_node_cache[path] = node

	return node

func _wait_signal(target: Node, signal_name: String, timeout: float, my_id: int):
	var observer = SignalObserver.new()
	target.connect(signal_name, observer, "on_signal")

	var timer = host_node.get_tree().create_timer(timeout)
	while not observer.triggered and timer.time_left > 0:
		if stop_requested or my_id != execution_id:
			break
		yield (host_node.get_tree(), "physics_frame")

	var success = observer.triggered
	if is_instance_valid(target) and target.is_connected(signal_name, observer, "on_signal"):
		target.disconnect(signal_name, observer, "on_signal")

	observer.free()
	return success

func _execute_assert(condition: String) -> Dictionary:
	var parts = condition.split(" ", false)
	if parts.size() < 3:
		return {"evaluated": false, "passed": true, "message": "Malformed assertion"}

	var left = _resolve_value(parts[0])
	var op = parts[1]
	var right = _resolve_value(parts[2])
	var msg = "Assertion failed"
	if condition.find("\"") != -1:
		msg = condition.substr(condition.find("\"")).replace("\"", "")

	var passed = _compare(left, op, right)
	if not passed:
		printerr("[OYS ASSERT] FAILED: ", msg, " (", left, " ", op, " ", right, ")")

	return {
		"evaluated": true,
		"passed": passed,
		"message": msg,
		"left": left,
		"op": op,
		"right": right
	}

func _get_subtitles_manager() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	return host_node.get_node_or_null("/root/SubtitlesOverlayManager")

func _show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	var manager = _get_subtitles_manager()
	if manager and manager.has_method("show_subtitle"):
		manager.show_subtitle(text, color, duration)

func _log_to_console(tag: String, message: String, color_override: String = "") -> void:
	var root = _find_root()
	if not root: return
	var console = root.get_node_or_null("OYS_Console")
	if console and console.has_method("add_log"):
		console.add_log(tag, message, color_override)

func _find_root() -> Node:
	if not host_node: return null
	return host_node.get_tree().root

func _clear_subtitles(immediate: bool = false) -> void:
	var manager = _get_subtitles_manager()
	if manager and manager.has_method("clear_subtitles"):
		manager.clear_subtitles(immediate)

class SignalObserver extends Object:
	var triggered = false
	func on_signal(_a = null, _b = null, _c = null, _d = null, _e = null):
		triggered = true

func _resolve_stage() -> Node:
	var tree = host_node.get_tree()
	if is_instance_valid(tree.current_scene):
		var stage = tree.current_scene
		if stage.name == "PropStage" or stage.has_method("load_prop"):
			return stage
		
		stage = tree.current_scene.find_node("PropStage", true, false)
		if stage:
			return stage

	var root = tree.root
	var stage = root.find_node("PropStage", true, false)
	if stage:
		return stage

	if host_node.has_method("load_prop") and host_node.name != "SessionManager":
		return host_node
		
	return null

func _resolve_prop() -> Node:
	var stage = _resolve_stage()
	if stage and "current_prop" in stage:
		if is_instance_valid(stage.current_prop):
			return stage.current_prop
		
	return null
func _resolve_value(val):
	if val == null:
		return null

	if typeof(val) != TYPE_STRING:
		return val

	if val.begins_with("$"):
		return variables.get(val, 0)
	if val.is_valid_float():
		return val.to_float()
	if val in ["pos.y", "pos.x", "pos.z"]:
		var player = _find_player()
		if not is_instance_valid(player):
			printerr("[OYS ERROR] Player instance is invalid or freed when resolving ", val)
			test_failed = true
			stop_requested = true
			return null
		
		if player is Spatial:
			match val:
				"pos.x": return player.global_transform.origin.x
				"pos.y": return player.global_transform.origin.y
				"pos.z": return player.global_transform.origin.z
		elif player is Node2D:
			match val:
				"pos.x": return player.position.x
				"pos.y": return player.position.y
				"pos.z": return 0.0
		return 0.0

	if val == "yaw_deg" or val == "pitch_deg":
		var player = _find_player()
		if not is_instance_valid(player):
			printerr("[OYS ERROR] Player instance is invalid or freed when resolving ", val)
			test_failed = true
			stop_requested = true
			return null
		
		# Priority 1: Direct property (synced in PlayerControllerV2)
		if val in player:
			return player.get(val)
		
		# Priority 2: Method-based access
		var method = "get_" + val
		if player.has_method(method):
			return player.call(method)
			
		# Fallback: Legacy/Calculation for yaw
		if val == "yaw_deg":
			if "yaw" in player: # rads
				return rad2deg(player.yaw)
			
			if player.has_node("CameraRig"):
				return rad2deg(player.get_node("CameraRig").rotation.y)
			elif player.has_node("CameraPivot"):
				return rad2deg(player.get_node("CameraPivot").rotation.y)
		
		# Fallback: Legacy/Calculation for pitch
		if val == "pitch_deg":
			if "pitch" in player: # rads
				return rad2deg(player.pitch)
				
			if player.has_node("CameraRig"):
				return rad2deg(player.get_node("CameraRig").rotation.x)
			elif player.has_node("CameraPivot"):
				return rad2deg(player.get_node("CameraPivot").rotation.x)

		return 0.0
	if val == "true": return true
	if val == "false": return false
	return val.replace("\"", "")

func _call_func(func_name: String, args: Array):
	match func_name:
		"GET_NODE_POS_X":
			var node = host_node.get_tree().root.find_node(args[0], true, false)
			if node:
				return node.global_transform.origin.x
			return 0.0
		"GET_NODE_POS_Y":
			var path = args[0].replace("\"", "")
			var node = _resolve_node(path)
			if node and node is Spatial:
				return node.global_transform.origin.y
			elif node and node is Node2D:
				return node.position.y
			return 0.0
		"GET_NODE_Z", "GET_NODE_POS_Z":
			var path = args[0].replace("\"", "")
			# Prefer SessionManager.player when path is the Pilot alias to ensure we
			# query the active player instance rather than a stale or name-colliding node.
			var node = null
			if path == "Pilot":
				var session_pref = host_node.get_node_or_null("/root/SessionManager")
				if session_pref and is_instance_valid(session_pref) and session_pref.has_method("get"):
					var p_pref = session_pref.get("player")
					if p_pref and is_instance_valid(p_pref):
						node = p_pref
			# Fallback to regular resolution
			if not node:
				node = _resolve_node(path)
			if not node:
				# Fallback: try SessionManager.player if available
				var session = host_node.get_node_or_null("/root/SessionManager")
				if session and is_instance_valid(session):
					if session.has_method("_find_player"):
						session._find_player()
					var p = session.get("player")
					if p and is_instance_valid(p):
						node = p
			if node and node is Spatial:
				return node.global_transform.origin.z
			return 0.0
		"SYSTEM":
			var parsed = _parse_system_args(args)
			if not bool(parsed.get("ok", false)):
				printerr("[OYS SYSTEM] Invalid args: ", parsed.get("error", "unknown"))
				return -1
			var result = _run_system_command(
				str(parsed.get("exec", "")),
				parsed.get("args", []),
				bool(parsed.get("blocking", false))
			)
			if not bool(result.get("ok", false)):
				printerr("[OYS SYSTEM] Command failed: ", result.get("error", "unknown"))
				return -1
			return int(result.get("value", -1))
		_:
			printerr("[OYS] Unknown function called: ", func_name)
			test_failed = true
			stop_requested = true
			return null

func _parse_system_args(args: Array) -> Dictionary:
	var tokens := []
	for raw in args:
		tokens.append(str(raw).strip_edges())

	if tokens.empty():
		return {"ok": false, "error": "missing command"}

	var blocking := false
	var mode = tokens[0].to_lower()
	if mode == "sync":
		blocking = true
		tokens.pop_front()
	elif mode == "async":
		blocking = false
		tokens.pop_front()

	if tokens.empty():
		return {"ok": false, "error": "missing executable"}

	var exec_path = String(tokens[0]).strip_edges()
	if exec_path == "":
		return {"ok": false, "error": "empty executable"}
	tokens.pop_front()

	return {
		"ok": true,
		"exec": exec_path,
		"args": tokens,
		"blocking": blocking
	}

func _run_system_command(exec_path: String, exec_args: Array, blocking: bool) -> Dictionary:
	if exec_path.strip_edges() == "":
		return {"ok": false, "error": "empty executable", "value": - 1, "blocking": blocking}

	var output := []
	var ret = OS.execute(exec_path, exec_args, blocking, output, true)

	if blocking:
		# In blocking mode OS.execute returns the child exit code.
		return {"ok": true, "value": int(ret), "blocking": true}

	# In Godot 3.x non-blocking execute may return 0 on success depending on platform.
	if int(ret) >= 0:
		var pid = int(ret)
		if pid <= 0:
			_system_launch_counter += 1
			pid = _system_launch_counter
		return {"ok": true, "value": pid, "blocking": false}
	return {"ok": false, "error": "could not start process", "value": - 1, "blocking": false}

func _compare(left, op, right) -> bool:
	var l = left
	var r = right
	var l_is_float = str(l).is_valid_float()
	var r_is_float = str(r).is_valid_float()
	
	if l_is_float and r_is_float:
		var fl = _to_number(l)
		var fr = _to_number(r)
		match op:
			"==": return fl == fr
			"!=": return fl != fr
			">": return fl > fr
			"<": return fl < fr
			">=": return fl >= fr
			"<=": return fl <= fr
			
	# String comparison fallback
	var sl = str(l)
	var sr = str(r)
	match op:
		"==": return sl == sr
		"!=": return sl != sr
	return false

func _to_number(value) -> float:
	match typeof(value):
		TYPE_REAL:
			return value
		TYPE_INT:
			return value
		TYPE_BOOL:
			return 1.0 if value else 0.0
		TYPE_STRING:
			return value.to_float() if value.is_valid_float() else 0.0
		_:
			return str(value).to_float() if str(value).is_valid_float() else 0.0

func _find_node_by_type(root: Node, type) -> Node:
	if is_instance_valid(root) and root is type:
		return root
	for i in range(root.get_child_count()):
		var res = _find_node_by_type(root.get_child(i), type)
		if res: return res
	return null

func _change_scene(path: String, params: Dictionary = {}):
	if host_node and is_instance_valid(host_node):
		var scene_manager = host_node.get_node_or_null("/root/SceneManager")
		if scene_manager and scene_manager.has_method("goto_scene"):
			var state = scene_manager.goto_scene(path, params)
			if state is GDScriptFunctionState:
				yield (state, "completed")
			return null
	return _open_scene(path)

func _sync_host_after_scene_change() -> void:
	var tree = Engine.get_main_loop()
	if tree and tree is SceneTree:
		var st = tree as SceneTree
		if st.current_scene and is_instance_valid(st.current_scene):
			host_node = st.current_scene
		elif st.root and is_instance_valid(st.root):
			host_node = st.root

func _open_scene(path: String):
	if not host_node or not host_node.is_inside_tree():
		return null
	var packed = load(path)
	if packed == null:
		printerr("[OYS] OPEN failed, scene not found: ", path)
		return null
	var inst = packed.instance()
	if inst == null:
		printerr("[OYS] OPEN failed, could not instance: ", path)
		return null
	var tree = host_node.get_tree()
	var old_scene = tree.current_scene
	tree.root.add_child(inst)
	if is_instance_valid(old_scene):
		old_scene.queue_free()
	tree.current_scene = inst
	yield (tree, "idle_frame")
	yield (tree, "idle_frame")
	return null

func _resolve_selector_node(selector: String) -> Node:
	if not host_node or not host_node.is_inside_tree():
		return null
	var current_scene = host_node.get_tree().current_scene
	if not is_instance_valid(current_scene):
		return null
	var s = selector.strip_edges()
	if s == "":
		return null

	if s.begins_with("path="):
		var p = s.substr(5, s.length())
		return current_scene.get_node_or_null(p)

	if s.begins_with("name="):
		var name = s.substr(5, s.length())
		return current_scene.find_node(name, true, false)

	if s.begins_with("text="):
		var target_text = s.substr(5, s.length())
		return _find_control_by_text(current_scene, target_text)

	# Default: try as path first, then by name.
	var node = current_scene.get_node_or_null(s)
	if node:
		return node
	return current_scene.find_node(s, true, false)

func _find_control_by_text(root: Node, target_text: String) -> Node:
	if not is_instance_valid(root):
		return null
	if root is Label and String(root.text).find(target_text) != -1:
		return root
	if root is Button and String(root.text).find(target_text) != -1:
		return root
	for child in root.get_children():
		var hit = _find_control_by_text(child, target_text)
		if hit:
			return hit
	return null

func _click_selector(selector: String) -> bool:
	var node = _resolve_selector_node(selector)
	if not node:
		return false
	if node is BaseButton:
		node.emit_signal("pressed")
		return true
	if node is Control:
		var ctrl = node as Control
		ctrl.grab_focus()
		var center = ctrl.get_global_rect().position + (ctrl.get_global_rect().size * 0.5)
		return _inject_mouse_click(center)
	return false

func _fill_selector(selector: String, value: String, append: bool) -> bool:
	var node = _resolve_selector_node(selector)
	if not node:
		return false
	if node is LineEdit:
		var line = node as LineEdit
		line.text = line.text + value if append else value
		line.caret_position = line.text.length()
		return true
	if node is TextEdit:
		var te = node as TextEdit
		te.text = te.text + value if append else value
		return true
	if node.has_method("set_text"):
		if append and "text" in node:
			node.call("set_text", str(node.get("text")) + value)
		else:
			node.call("set_text", value)
		return true
	return false

func _press_selector(selector: String, key_name: String) -> bool:
	var node = _resolve_selector_node(selector)
	if not node:
		return false
	if node is Control:
		(node as Control).grab_focus()
	if node is LineEdit:
		var line = node as LineEdit
		var key_upper = key_name.strip_edges().to_upper()
		if key_upper == "ENTER" or key_upper == "RETURN":
			line.emit_signal("text_entered", line.text)
			return true
		if key_upper == "BACKSPACE":
			if line.text.length() > 0:
				line.text = line.text.substr(0, line.text.length() - 1)
				line.caret_position = line.text.length()
			return true
	return _inject_key(key_name)

func _extract_control_text(node: Node) -> String:
	if not node:
		return ""
	if node is Label:
		return String((node as Label).text)
	if node is Button:
		return String((node as Button).text)
	if node is LineEdit:
		return String((node as LineEdit).text)
	if node is TextEdit:
		return String((node as TextEdit).text)
	if node is RichTextLabel:
		var rt = node as RichTextLabel
		if rt.bbcode_enabled:
			return String(rt.bbcode_text)
		return String(rt.text)
	if "text" in node:
		return String(node.get("text"))
	return ""

func _inject_mouse_click(global_pos: Vector2) -> bool:
	if not host_node or not host_node.is_inside_tree():
		return false
	var viewport = host_node.get_viewport()
	if not viewport:
		return false
	var motion = InputEventMouseMotion.new()
	motion.position = global_pos
	motion.global_position = global_pos
	viewport.input(motion)
	var press = InputEventMouseButton.new()
	press.button_index = BUTTON_LEFT
	press.pressed = true
	press.position = global_pos
	press.global_position = global_pos
	viewport.input(press)
	var release = InputEventMouseButton.new()
	release.button_index = BUTTON_LEFT
	release.pressed = false
	release.position = global_pos
	release.global_position = global_pos
	viewport.input(release)
	return true

func _inject_key(key_name: String) -> bool:
	if not host_node or not host_node.is_inside_tree():
		return false
	var viewport = host_node.get_viewport()
	if not viewport:
		return false
	var key = key_name.strip_edges().to_upper()
	var scancode = _key_name_to_scancode(key)
	if scancode == 0:
		return false
	var press = InputEventKey.new()
	press.pressed = true
	press.scancode = scancode
	viewport.input(press)
	var release = InputEventKey.new()
	release.pressed = false
	release.scancode = scancode
	viewport.input(release)
	return true

func _key_name_to_scancode(key_name: String) -> int:
	match key_name:
		"ENTER", "RETURN":
			return KEY_ENTER
		"TAB":
			return KEY_TAB
		"UP":
			return KEY_UP
		"DOWN":
			return KEY_DOWN
		"LEFT":
			return KEY_LEFT
		"RIGHT":
			return KEY_RIGHT
		"BACKSPACE":
			return KEY_BACKSPACE
		"ESC", "ESCAPE":
			return KEY_ESCAPE
		_:
			if key_name.length() == 1:
				var maybe = OS.find_scancode_from_string(key_name)
				return maybe
	return 0

func _substitute_variables(message: String) -> String:
	var result = message
	for var_name in variables.keys():
		var pos = result.find(var_name)
		if pos != -1:
			var value = str(variables[var_name])
			result = result.replace(var_name, value)
	return result
