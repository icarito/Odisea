tool
extends EditorScenePostImport

# --- CONFIGURATION ---
export var enable_root_motion = true

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
                print("  - Renamed '" + old_name + "' -> '" + new_name + "'")

    # 3. Force T-Pose
    force_tpose(skeleton)

    # 4. Extract Root Motion (Optional)
    if enable_root_motion:
        var anim_player = find_animation_player(scene_root)
        if anim_player:
            extract_root_motion(skeleton, anim_player)
        else:
            print("Hunyuan Retargeter: No AnimationPlayer found. Cannot extract root motion.")

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

        # Create new track for root motion on the scene's root spatial node
        var root_motion_track_idx = anim.add_track(Animation.TYPE_POSITION, 0)
        anim.track_set_path(root_motion_track_idx, "..")

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


# Calculates and applies the necessary rotation to force the arms into a T-pose.
func force_tpose(skeleton):
    print("Hunyuan Retargeter: Attempting to force T-Pose...")

    var left_arm_idx = skeleton.find_bone("LeftUpperArm")
    var right_arm_idx = skeleton.find_bone("RightUpperArm")

    if left_arm_idx != -1:
        _correct_bone_rotation(skeleton, left_arm_idx, Vector3(1, 0, 0))
        print("  - Corrected LeftUpperArm rotation.")
    else:
        print("  - WARNING: LeftUpperArm not found. Cannot apply T-Pose correction.")

    if right_arm_idx != -1:
        _correct_bone_rotation(skeleton, right_arm_idx, Vector3(-1, 0, 0))
        print("  - Corrected RightUpperArm rotation.")
    else:
        print("  - WARNING: RightUpperArm not found. Cannot apply T-Pose correction.")

# Helper function to apply rotation correction to a single bone.
func _correct_bone_rotation(skeleton, bone_idx, target_world_dir):
    var parent_idx = skeleton.get_bone_parent(bone_idx)
    if parent_idx == -1:
        print("  - WARNING: Arm bone has no parent, cannot T-Pose safely.")
        return

    var parent_global_pose = skeleton.get_bone_global_pose(parent_idx)
    var bone_global_pose = skeleton.get_bone_global_pose(bone_idx)

    # ASSUMPTION: The bone's local X-axis points down its length. This is a common
    # convention in 3D modeling, but if a source skeleton uses a different axis
    # (e.g., Y-axis), this line will need to be adjusted.
    var current_world_dir = bone_global_pose.basis.xform(Vector3(1, 0, 0)).normalized()

    var correction_quat = Quat(current_world_dir, target_world_dir)

    var parent_global_basis_inv = parent_global_pose.basis.inverse()
    var local_correction_quat = parent_global_basis_inv * correction_quat * parent_global_pose.basis

    var current_rest = skeleton.get_bone_rest(bone_idx)
    var new_basis = current_rest.basis * Basis(local_correction_quat)
    var new_rest = Transform(new_basis, current_rest.origin)

    skeleton.set_bone_rest(bone_idx, new_rest)
