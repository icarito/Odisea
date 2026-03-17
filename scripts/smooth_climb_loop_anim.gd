extends SceneTree

# Regenerate Climb_Loop_70.anim from the raw Climb_Loop.anim source.
# 1. Trims to N frames
# 2. Replaces the right arm with a mirrored, phase-shifted copy of the left arm
# 3. Clamps per-frame angular velocity to reduce mocap "spasms"
# 4. Applies a symmetric cross-fade to close the loop seamlessly

const SOURCE_PATH := "res://models/Pilot/Climb_Loop.anim"
const OUTPUT_PATH := "res://models/Pilot/Climb_Loop_70.anim"
const SOURCE_FPS := 15.0

# How many source frames to keep (24 out of ~42 ≈ 1.6s)
const TRIM_FRAMES := 24

# Fraction of the trimmed animation to cross-fade (0.4 = last 40% blends toward frame 0)
const CROSSFADE_RATIO := 0.40

# Maximum degrees of rotation change allowed per frame for any single bone.
const MAX_DEG_PER_FRAME := 16.0
const SMOOTH_PASSES := 2

class Sorter:
	static func sort_by_time(a, b):
		return a.time < b.time

func _init() -> void:
	var source: Animation = load(SOURCE_PATH)
	if source == null:
		push_error("Could not load source animation: %s" % SOURCE_PATH)
		quit(1)
		return

	var trim_end_time := TRIM_FRAMES / SOURCE_FPS
	if trim_end_time > source.length:
		trim_end_time = source.length

	var result := Animation.new()
	result.length = trim_end_time
	result.loop = true
	result.step = 1.0 / SOURCE_FPS

	# --- PRE-PASS: COLLECT LEFT ARM TRACKS FOR MIRRORING ---
	var expected_left_bones = ["DEF-shoulderL", "DEF-upper_armL", "DEF-forearmL", "DEF-handL"]
	var left_arm_data = {}
	for src_track in range(source.get_track_count()):
		if source.track_get_type(src_track) != Animation.TYPE_TRANSFORM: continue
		var path = String(source.track_get_path(src_track))
		for l_bone in expected_left_bones:
			if path.ends_with(l_bone):
				left_arm_data[l_bone] = []
				var key_count = source.track_get_key_count(src_track)
				for k in range(key_count):
					var t = source.track_get_key_time(src_track, k)
					if t > trim_end_time + 0.001: break
					var val = source.track_get_key_value(src_track, k)
					left_arm_data[l_bone].append({
						"time": t, "location": val.location, "rotation": val.rotation, "scale": val.scale
					})

	# --- MAIN PASS ---
	for src_track in range(source.get_track_count()):
		var track_type := source.track_get_type(src_track)
		if track_type != Animation.TYPE_TRANSFORM:
			var dst_track := result.add_track(track_type)
			result.track_set_path(dst_track, source.track_get_path(src_track))
			result.track_set_interpolation_type(dst_track, source.track_get_interpolation_type(src_track))
			for k in range(source.track_get_key_count(src_track)):
				var t := source.track_get_key_time(src_track, k)
				if t > trim_end_time:
					break
				result.track_insert_key(dst_track, t,
					source.track_get_key_value(src_track, k),
					source.track_get_key_transition(src_track, k))
			continue

		var dst_track := result.add_track(Animation.TYPE_TRANSFORM)
		result.track_set_path(dst_track, source.track_get_path(src_track))
		result.track_set_interpolation_type(dst_track, source.track_get_interpolation_type(src_track))
		result.track_set_interpolation_loop_wrap(dst_track, true)

		var bone_name = String(source.track_get_path(src_track))
		var trimmed_keys := []
		
		# Determine if we should replace this right arm bone with mirroring
		var r_to_l = {
			"DEF-shoulderR": "DEF-shoulderL",
			"DEF-upper_armR": "DEF-upper_armL",
			"DEF-forearmR": "DEF-forearmL",
			"DEF-handR": "DEF-handL"
		}
		
		var is_mirrored = false
		for r_bone in r_to_l:
			if bone_name.ends_with(r_bone):
				var l_bone = r_to_l[r_bone]
				if left_arm_data.has(l_bone):
					var half_loop = trim_end_time / 2.0
					for entry in left_arm_data[l_bone]:
						var t = entry.time + half_loop
						if t >= trim_end_time: t -= trim_end_time
						var orig_rot = entry.rotation
						var mirrored_rot = Quat(orig_rot.x, -orig_rot.y, -orig_rot.z, orig_rot.w)
						
						# X reflections shouldn't matter since hand local Y is mostly vertical? 
						# Rest poses origin are identical, so location can stay identical.
						trimmed_keys.append({
							"time": t,
							"location": entry.location,
							"rotation": mirrored_rot,
							"scale": entry.scale
						})
					trimmed_keys.sort_custom(Sorter, "sort_by_time")
					is_mirrored = true
					break

		if not is_mirrored:
			var key_count := source.track_get_key_count(src_track)
			for k in range(key_count):
				var t := source.track_get_key_time(src_track, k)
				if t > trim_end_time + 0.001:
					break
				var val = source.track_get_key_value(src_track, k)
				trimmed_keys.append({
					"time": t,
					"location": val.location,
					"rotation": val.rotation,
					"scale": val.scale,
				})

		if trimmed_keys.size() < 2:
			for entry in trimmed_keys:
				result.transform_track_insert_key(dst_track, entry.time,
					entry.location, entry.rotation, entry.scale)
			continue

		# === PASS 1: Clamp angular velocity spikes ===
		for _pass in range(SMOOTH_PASSES):
			for i in range(1, trimmed_keys.size()):
				var prev_rot: Quat = trimmed_keys[i - 1].rotation
				var curr_rot: Quat = trimmed_keys[i].rotation
				var angle_deg := rad2deg(prev_rot.angle_to(curr_rot))
				
				if angle_deg > MAX_DEG_PER_FRAME:
					var clamp_ratio := MAX_DEG_PER_FRAME / angle_deg
					trimmed_keys[i].rotation = prev_rot.slerp(curr_rot, clamp_ratio)

		# === PASS 2: Bone Offsets (Arm Width, Spine/Head) ===
		
		if bone_name.ends_with(":DEF-upper_armR"):
			# Simple Z-roll to widen grip to match ladder tube half-width (0.34m)
			var offset_quat := Quat(Vector3(0, 0, deg2rad(15)))
			for entry in trimmed_keys:
				entry.rotation = offset_quat * entry.rotation
				
		elif bone_name.ends_with(":DEF-upper_armL"):
			var offset_quat := Quat(Vector3(0, 0, deg2rad(-15)))
			for entry in trimmed_keys:
				entry.rotation = offset_quat * entry.rotation

		# Removed dampening logic on the left arm entirely so it moves fully!

		# Dampen head/neck/spine "cabezaso" and lateral tilt
		if bone_name.ends_with(":DEF-head") or bone_name.ends_with(":DEF-neck") or bone_name.ends_with(":DEF-spine01") or bone_name.ends_with(":DEF-spine") or bone_name.ends_with(":DEF-spine02") or bone_name.ends_with(":DEF-chest"):
			var base_rot = trimmed_keys[0].rotation
			for entry in trimmed_keys:
				entry.rotation = base_rot.slerp(entry.rotation, 0.05)


		# === PASS 3: Cross-fade to close the loop ===
		var first_loc: Vector3 = trimmed_keys[0].location
		var first_rot: Quat = trimmed_keys[0].rotation
		var first_scl: Vector3 = trimmed_keys[0].scale

		var fade_start := trim_end_time * (1.0 - CROSSFADE_RATIO)

		for entry in trimmed_keys:
			var t: float = entry.time
			if t <= fade_start:
				continue
			if t >= trim_end_time - 0.001:
				entry.location = first_loc
				entry.rotation = first_rot
				entry.scale = first_scl
				continue

			var progress := (t - fade_start) / (trim_end_time - fade_start)
			progress = clamp(progress, 0.0, 1.0)
			var weight := progress * progress * (3.0 - 2.0 * progress)

			entry.location = entry.location.linear_interpolate(first_loc, weight)
			entry.rotation = entry.rotation.slerp(first_rot, weight)
			entry.scale = entry.scale.linear_interpolate(first_scl, weight)

		# Insert all keyframes
		for entry in trimmed_keys:
			result.transform_track_insert_key(dst_track, entry.time,
				entry.location, entry.rotation, entry.scale)

	var err := ResourceSaver.save(OUTPUT_PATH, result)
	if err != OK:
		push_error("Failed to save animation. Error: %d" % err)
	else:
		print("=== Generated %s ===" % OUTPUT_PATH)
		print("  Length: %.1fs (%d frames @ 15fps)" % [trim_end_time, TRIM_FRAMES])

		# Verify
		var test_anim = load(OUTPUT_PATH)
		var max_diff = 0.0
		for t in range(test_anim.get_track_count()):
			if test_anim.track_get_type(t) != Animation.TYPE_TRANSFORM: continue
			var key_cnt = test_anim.track_get_key_count(t)
			if key_cnt < 2: continue
			var f_rot = test_anim.track_get_key_value(t, 0).rotation
			var l_rot = test_anim.track_get_key_value(t, key_cnt - 1).rotation
			var diff = rad2deg(f_rot.angle_to(l_rot))
			if diff > max_diff:
				max_diff = diff
		print("  Max first/last rotation diff: %.4f°" % max_diff)
	
	quit()
