tool
extends EditorScenePostImport

# Set these to false if you don't want certain features
export var rename_bones = true
export var fix_animation_tracks = true
export var fix_skin_bindings = true

# The path to the skeleton node locally in the target scene (e.g., "Visual/Pivot/Skeleton")
# If empty, it will use the path found in the imported file (which is usually wrong for retargeting).
# The path to the skeleton node locally in the target scene (e.g., "Visual/Pivot/Skeleton")
# Hardcoded to automate the fix for Pilot model retargeting.
var target_skeleton_path = "Visual/Pivot/Skeleton"

# Stores the mapping of old_name -> new_name for this import run
var _bone_rename_map = {}

# A map of source bone names to the Godot Humanoid standard.
const BONE_MAP = {
	# Hips
	"Pelvis": "DEF-hips", "Hips": "DEF-hips", "root": "DEF-hips", "DEF-hips": "DEF-hips",
	# Spine
	"Spine1": "DEF-spine", "Spine": "DEF-spine", "DEF-spine": "DEF-spine",
	"Spine2": "DEF-spine002", "Chest": "DEF-spine002", "DEF-spine002": "DEF-spine002",
	"Spine3": "DEF-spine003", "UpperChest": "DEF-spine003", "DEF-spine003": "DEF-spine003",
	# Head
	"Neck": "DEF-neck", "DEF-neck": "DEF-neck",
	"Head": "DEF-head", "DEF-head": "DEF-head",
	# Left Leg
	"L_Hip": "DEF-thighL", "LeftUpLeg": "DEF-thighL", "DEF-thighL": "DEF-thighL",
	"L_Knee": "DEF-shinL", "LeftLeg": "DEF-shinL", "DEF-shinL": "DEF-shinL",
	"L_Ankle": "DEF-footL", "LeftFoot": "DEF-footL", "DEF-footL": "DEF-footL",
	"L_Foot": "DEF-toesL", "LeftToe": "DEF-toesL", "DEF-toesL": "DEF-toesL",
	# Right Leg
	"R_Hip": "DEF-thighR", "RightUpLeg": "DEF-thighR", "DEF-thighR": "DEF-thighR",
	"R_Knee": "DEF-shinR", "RightLeg": "DEF-shinR", "DEF-shinR": "DEF-shinR",
	"R_Ankle": "DEF-footR", "RightFoot": "DEF-footR", "DEF-footR": "DEF-footR",
	"R_Foot": "DEF-toesR", "RightToe": "DEF-toesR", "DEF-toesR": "DEF-toesR",
	# Left Arm
	"L_Collar": "DEF-shoulderL", "LeftShoulder": "DEF-shoulderL", "DEF-shoulderL": "DEF-shoulderL",
	"L_Shoulder": "DEF-upper_armL", "L_UpArm": "DEF-upper_armL", "DEF-upper_armL": "DEF-upper_armL",
	"L_Elbow": "DEF-forearmL", "L_LowArm": "DEF-forearmL", "DEF-forearmL": "DEF-forearmL",
	"L_Wrist": "DEF-handL", "L_Hand": "DEF-handL", "DEF-handL": "DEF-handL",
	# Right Arm
	"R_Collar": "DEF-shoulderR", "RightShoulder": "DEF-shoulderR", "DEF-shoulderR": "DEF-shoulderR",
	"R_Shoulder": "DEF-upper_armR", "R_UpArm": "DEF-upper_armR", "DEF-upper_armR": "DEF-upper_armR",
	"R_Elbow": "DEF-forearmR", "R_LowArm": "DEF-forearmR", "DEF-forearmR": "DEF-forearmR",
	"R_Wrist": "DEF-handR", "R_Hand": "DEF-handR", "DEF-handR": "DEF-handR",
	# Fingers (Basic mapping if present)
	"L_Thumb1": "DEF-thumb01L", "L_Index1": "DEF-f_index01L",
	"R_Thumb1": "DEF-thumb01R", "R_Index1": "DEF-f_index01R",
}


func post_import(scene_root):
	_bone_rename_map.clear()
	
	print("Hunyuan Retargeter: Starting import...")

	# --- 1. Find Skeleton ---
	var skeleton = _find_skeleton(scene_root)
	if skeleton == null:
		print("  - ERROR: No Skeleton node found. Aborting.")
		return scene_root

	# --- 2. Rename Bones ---
	if rename_bones:
		_rename_bones(skeleton)
	
	# --- 3. Fix Skin Bindings (MUST happen after bone rename) ---
	if fix_skin_bindings and not _bone_rename_map.empty():
		_fix_skin_bindings(scene_root)

	# --- 4. Fix Animation Tracks ---
	var anim_player = _find_animation_player(scene_root)
	if anim_player and fix_animation_tracks and not _bone_rename_map.empty():
		_fix_animation_tracks(anim_player, skeleton)
	elif not anim_player:
		print("  - No AnimationPlayer found. Skipping animation processing.")

	print("Hunyuan Retargeter: Import complete.")
	return scene_root


func _find_skeleton(node):
	if node is Skeleton:
		print("  - Found Skeleton: " + node.name)
		return node
	for child in node.get_children():
		var res = _find_skeleton(child)
		if res:
			return res
	return null


func _find_animation_player(node):
	if node is AnimationPlayer:
		print("  - Found AnimationPlayer: " + node.name)
		return node
	for child in node.get_children():
		var res = _find_animation_player(child)
		if res:
			return res
	return null


func _rename_bones(skeleton):
	print("  - Renaming bones...")
	for i in range(skeleton.get_bone_count()):
		var old_name = skeleton.get_bone_name(i)
		var core_name = _strip_prefix(old_name)
		if BONE_MAP.has(core_name):
			var new_name = BONE_MAP[core_name]
			if old_name != new_name:
				skeleton.set_bone_name(i, new_name)
				_bone_rename_map[old_name] = new_name
				print("    - " + old_name + " -> " + new_name)


func _strip_prefix(bone_name):
	var colon_pos = bone_name.find_last(":")
	if colon_pos != -1:
		return bone_name.substr(colon_pos + 1)
	return bone_name


func _fix_skin_bindings(node):
	# Find all MeshInstance nodes and update their skin bindings
	if node is MeshInstance:
		var skin = node.get_skin()
		if skin:
			_update_skin(skin, node.name)
	
	for child in node.get_children():
		_fix_skin_bindings(child)


func _update_skin(skin: Skin, mesh_name: String):
	var bind_count = skin.get_bind_count()
	var updated = false
	
	for i in range(bind_count):
		var bind_name = skin.get_bind_name(i)
		if _bone_rename_map.has(bind_name):
			var new_name = _bone_rename_map[bind_name]
			skin.set_bind_name(i, new_name)
			updated = true
	
	if updated:
		print("  - Fixed skin bindings for: " + mesh_name)


func _fix_animation_tracks(anim_player, skeleton):
	print("  - Fixing animation tracks...")
	
	# Determine the path prefix relative to the AnimationPlayer
	# Usually the AnimationPlayer is a sibling of the Skeleton container or root
	var skeleton_path = anim_player.get_parent().get_path_to(skeleton)
	var skeleton_path_str = str(skeleton_path)
	
	# If a robust target path is provided, use it instead of the local import path
	if not target_skeleton_path.empty():
		skeleton_path_str = target_skeleton_path
	
	print("    - Target Skeleton path: " + skeleton_path_str)
	
	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		var track_count = anim.get_track_count()
		print("    - Animation '" + anim_name + "': " + str(track_count) + " tracks")
		
		for i in range(track_count):
			var path = anim.track_get_path(i)
			var path_str = str(path)
			
			# We need to handle paths like "Reference/Skeleton:BoneName"
			# Split by first colon to separate node path from bone/property
			var parts = path_str.split(":", true, 1)
			if parts.size() < 2:
				continue
				
			var node_path_part = parts[0]
			var bone_part = parts[1]
			
			# Check if this track targets our skeleton
			# Relaxed check: if the node path ends with the skeleton name
			if not node_path_part.ends_with(skeleton.name):
				continue

			# Isolate bone name from property (e.g., "BoneName:position")
			var bone_name = bone_part
			var property_suffix = ""
			var col_idx = bone_part.find(":")
			if col_idx != -1:
				bone_name = bone_part.substr(0, col_idx)
				property_suffix = bone_part.substr(col_idx) # Includes the colon
			
			# Check rename map
			var search_name = _strip_prefix(bone_name)
			
			# Apply Retargeting (Rename + Repath)
			if BONE_MAP.has(search_name):
				var new_bone_name = BONE_MAP[search_name]
				
				# Construct new path using the CORRECT skeleton path discovered at runtime
				var new_path_str = skeleton_path_str + ":" + new_bone_name + property_suffix
				anim.track_set_path(i, NodePath(new_path_str))
				print("      - Repathed: " + path_str + " -> " + new_path_str)
			
			# Even if bone isn't renamed, we MUST fix the path prefix if target_skeleton_path is set
			elif not target_skeleton_path.empty() and skeleton_path_str != node_path_part:
				var new_path_str = skeleton_path_str + ":" + bone_name + property_suffix
				anim.track_set_path(i, NodePath(new_path_str))
				print("      - Fixed Path Prefix: " + path_str + " -> " + new_path_str)
