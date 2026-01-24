tool
extends EditorScenePostImport

# --- CONFIGURATION ---
export var enable_root_motion = true
export var fix_animation_tracks = true
export var force_tpose = true
export var sanitize_scale = true

var _bone_rename_map = {} # Stores the mapping of old_name -> new_name for this import run

# A comprehensive map of potential source bone names to the Godot Humanoid standard.
const BONE_MAP = {
    # Hips
    "Pelvis": "Hips", "Hips": "Hips", "root": "Hips",
    # Left Leg
    "L_Hip": "LeftUpperLeg", "LeftUpLeg": "LeftUpperLeg",
    "L_Knee": "LeftLowerLeg", "LeftLeg": "LeftLowerLeg",
    "L_Ankle": "LeftFoot", "LeftFoot": "LeftFoot",
    "L_Foot": "LeftToes", "LeftToe": "LeftToes",
    # Right Leg
    "R_Hip": "RightUpperLeg", "RightUpLeg": "RightUpperLeg",
    "R_Knee": "RightLowerLeg", "RightLeg": "RightLowerLeg",
    "R_Ankle": "RightFoot", "RightFoot": "RightFoot",
    "R_Foot": "RightToes", "RightToe": "RightToes",
    # Spine
    "Spine1": "Spine", "Spine": "Spine",
    "Spine2": "Chest", "Chest": "Chest",
    "Spine3": "UpperChest", "UpperChest": "UpperChest",
    # Head
    "Neck": "Neck",
    "Head": "Head",
    # Left Arm
    "L_Collar": "LeftShoulder", "LeftShoulder": "LeftShoulder",
    "L_Shoulder": "LeftUpperArm", "L_UpArm": "LeftUpperArm",
    "L_Elbow": "LeftLowerArm", "L_LowArm": "LeftLowerArm",
    "L_Wrist": "LeftHand", "L_Hand": "LeftHand",
    # Right Arm
    "R_Collar": "RightShoulder", "RightShoulder": "RightShoulder",
    "R_Shoulder": "RightUpperArm", "R_UpArm": "RightUpperArm",
    "R_Elbow": "RightLowerArm", "R_LowArm": "RightLowerArm",
    "R_Wrist": "RightHand", "R_Hand": "RightHand",
}


func post_import(scene_root):
    _bone_rename_map.clear() # Reset for this import run

    # 1. Find the Skeleton
    var skeleton = find_skeleton(scene_root)
    if skeleton == null:
        print("Hunyuan Retargeter: No Skeleton node found in the scene.")
        return scene_root

    # 2. Rename Bones with prefix stripping and alias support
    print("Hunyuan Retargeter: Starting bone renaming...")
    for i in range(skeleton.get_bone_count()):
        var old_name = skeleton.get_bone_name(i)
        var core_name = strip_prefix(old_name)

        if core_name in BONE_MAP:
            var new_name = BONE_MAP[core_name]
            if old_name != new_name:
                skeleton.set_bone_name(i, new_name)
                _bone_rename_map[old_name] = new_name
                print("  - Renamed '" + old_name + "' -> '" + new_name + "'")

    # 3. Sanitize Scale (Optional)
    if sanitize_scale:
        sanitize_skeleton_scale(scene_root, skeleton)

    # 4. Force T-Pose (Optional)
    if force_tpose:
        force_tpose_vectorial(skeleton) # Placeholder for the new V2 logic

    # 5. Fix Animation Tracks (Optional)
    var anim_player = find_animation_player(scene_root)
    if anim_player:
        if fix_animation_tracks:
            fix_animation_tracks(anim_player, skeleton)

        # 6. Extract Root Motion (Optional)
        if enable_root_motion:
            extract_root_motion(skeleton, anim_player)
    else:
        print("Hunyuan Retargeter: No AnimationPlayer found. Skipping animation processing.")

    return scene_root

# Strips the prefix from a bone name (e.g., "mixamorig:Hips" -> "Hips")
func strip_prefix(bone_name):
    var colon_pos = bone_name.find_last(":")
    if colon_pos != -1:
        return bone_name.substr(colon_pos + 1)
    return bone_name

func find_skeleton(node):
    if node is Skeleton: return node
    for child in node.get_children():
        var res = find_skeleton(child)
        if res: return res
    return null

func find_animation_player(node):
    if node is AnimationPlayer: return node
    for child in node.get_children():
        var res = find_animation_player(child)
        if res: return res
    return null

# Rewrites animation track paths to reflect renamed bones.
func fix_animation_tracks(anim_player, skeleton):
    if _bone_rename_map.empty():
        return # No bones were renamed, so no fixing is needed.

    print("Hunyuan Retargeter: Fixing animation tracks for renamed bones...")
    var skeleton_path_str = anim_player.get_parent().get_path_to(skeleton).get_concatenated_names()

    for anim_name in anim_player.get_animation_list():
        var anim = anim_player.get_animation(anim_name)
        for i in range(anim.get_track_count()):
            var path = anim.track_get_path(i)

            # Expected format: "SkeletonNodeName:BoneName"
            if path.get_subname_count() == 1:
                var bone_name = path.get_subname(0)
                if _bone_rename_map.has(bone_name):
                    var new_bone_name = _bone_rename_map[bone_name]
                    var new_path = NodePath(skeleton_path_str + ":" + new_bone_name)
                    anim.track_set_path(i, new_path)
                    print("  - Repathed track in '" + anim_name + "': " + bone_name + " -> " + new_bone_name)

# Extracts horizontal motion from the Hips bone and applies it to the scene root.
func extract_root_motion(skeleton, anim_player):
    print("Hunyuan Retargeter: Starting root motion extraction...")

    # Correctly determine the NodePath from the AnimationPlayer's root to the Skeleton.
    # This is crucial for finding the animation track reliably.
    var anim_root = anim_player.get_parent()
    if anim_root == null:
        print("  - ERROR: AnimationPlayer has no parent. Cannot determine root path for animations.")
        return
    var skeleton_path = anim_root.get_path_to(skeleton)
    var hips_path = skeleton_path + ":Hips"

    for anim_name in anim_player.get_animation_list():
        var anim = anim_player.get_animation(anim_name)
        var track_idx = anim.find_track(hips_path + ":position")

        if track_idx == -1:
            print("  - No position track for Hips found in animation '" + anim_name + "'. Skipping.")
            continue

        print("  - Processing animation '" + anim_name + "'...")

        # Create new track for root motion on the scene's root spatial node.
        # The path "." correctly targets the AnimationPlayer's root_node.
        var root_motion_track_idx = anim.add_track(Animation.TYPE_POSITION, 0)
        anim.track_set_path(root_motion_track_idx, ".")

        # Create a new track for the hips with cleared X/Z motion
        var new_hips_track_idx = anim.add_track(Animation.TYPE_POSITION, 0)
        anim.track_set_path(new_hips_track_idx, hips_path)

        for i in range(anim.track_get_key_count(track_idx)):
            var time = anim.track_get_key_time(track_idx, i)
            var transition = anim.track_get_key_transition(track_idx, i)
            var original_pos = anim.track_get_key_value(track_idx, i)

            # Key for the root motion track (X and Z motion)
            anim.track_insert_key(root_motion_track_idx, time, Vector3(original_pos.x, 0, original_pos.z), transition)

            # Key for the new hips track (only Y motion)
            anim.track_insert_key(new_hips_track_idx, time, Vector3(0, original_pos.y, 0), transition)

        # Remove the original, combined hips position track
        anim.remove_track(track_idx)


# Aligns limbs to a target vector for a robust T-Pose.
func force_tpose_vectorial(skeleton):
    print("Hunyuan Retargeter: Applying V2 Vectorial T-Pose...")

    # Define bone pairs and their target vectors
    var limbs_to_correct = [
        # Arms
        ["LeftUpperArm", "LeftLowerArm", Vector3(-1, 0, 0)],
        ["RightUpperArm", "RightLowerArm", Vector3(1, 0, 0)],
        # Legs
        ["LeftUpperLeg", "LeftLowerLeg", Vector3(0, -1, 0)],
        ["RightUpperLeg", "RightLowerLeg", Vector3(0, -1, 0)]
    ]

    for limb_info in limbs_to_correct:
        var upper_bone = limb_info[0]
        var lower_bone = limb_info[1]
        var target_vec = limb_info[2]

        var upper_idx = skeleton.find_bone(upper_bone)
        var lower_idx = skeleton.find_bone(lower_bone)

        if upper_idx != -1 and lower_idx != -1:
            _align_bone_vectorially(skeleton, upper_idx, lower_idx, target_vec)
            print("  - Aligned " + upper_bone)
        else:
            print("  - WARNING: Could not find bones for " + upper_bone + ". Skipping alignment.")

# Helper function to align a bone based on joint positions.
func _align_bone_vectorially(skeleton, upper_idx, lower_idx, target_world_dir):
    var parent_idx = skeleton.get_bone_parent(upper_idx)
    if parent_idx == -1:
        print("  - WARNING: Limb bone '" + skeleton.get_bone_name(upper_idx) + "' has no parent. Cannot T-Pose safely.")
        return

    # Get global poses to calculate the direction vector
    var upper_global_pose = skeleton.get_bone_global_pose(upper_idx)
    var lower_global_pose = skeleton.get_bone_global_pose(lower_idx)

    # Calculate the actual vector from the upper joint to the lower joint
    var current_world_dir = (lower_global_pose.origin - upper_global_pose.origin).normalized()

    # Calculate the rotation needed to get from current to target
    var correction_quat = Quat(current_world_dir, target_world_dir)

    # Transform the world-space correction into the parent's local space
    var parent_global_pose = skeleton.get_bone_global_pose(parent_idx)
    var parent_global_basis_inv = parent_global_pose.basis.inverse()
    var local_correction_quat = parent_global_basis_inv * correction_quat * parent_global_pose.basis

    # Apply the local correction to the bone's rest transform.
    # The order is crucial: apply the new rotation BEFORE the existing one.
    var current_rest = skeleton.get_bone_rest(upper_idx)
    var new_basis = Basis(local_correction_quat) * current_rest.basis
    var new_rest = Transform(new_basis, current_rest.origin)

    skeleton.set_bone_rest(upper_idx, new_rest)

# Sanitizes the skeleton's scale to prevent "spaghetti effect" or giant models.
func sanitize_skeleton_scale(scene_root, skeleton):
    print("Hunyuan Retargeter: Sanitizing skeleton scale...")

    # 1. Force the root node's scale to (1, 1, 1).
    if scene_root is Spatial:
        scene_root.scale = Vector3(1, 1, 1)
        print("  - Scene root scale forced to (1, 1, 1).")

    # 2. Calculate height based on Hips-to-Head distance.
    var hips_idx = skeleton.find_bone("Hips")
    var head_idx = skeleton.find_bone("Head")

    if hips_idx == -1 or head_idx == -1:
        print("  - WARNING: Cannot find Hips or Head bone. Skipping height check.")
        return

    # Use global pose to get positions in the same (skeleton) coordinate space.
    var hips_pos = skeleton.get_bone_global_pose(hips_idx).origin
    var head_pos = skeleton.get_bone_global_pose(head_idx).origin
    var height = abs(head_pos.y - hips_pos.y)

    print("  - Calculated skeleton height (Hips to Head): " + str(height))

    # 3. If height is too small, scale up the bone positions.
    if height < 0.5:
        print("  - Height is less than 0.5. Scaling up bone positions by x100.")
        for i in range(skeleton.get_bone_count()):
            var rest = skeleton.get_bone_rest(i)
            rest.origin *= 100
            skeleton.set_bone_rest(i, rest)
