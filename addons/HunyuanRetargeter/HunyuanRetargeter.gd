tool
extends EditorScenePostImport

# CONFIG: User-adjustable angles for T-Pose correction.
# Common A-Poses might need around 45-60 degrees.
export(float, -180, 180) var left_arm_correction_deg = 60.0
export(float, -180, 180) var right_arm_correction_deg = -60.0

# CONFIG: Map Hunyuan/SMPL source names to Godot 3 Target names.
const BONE_MAP = {
    # Root and Pelvis
    "Pelvis": "Hips",
    "Hips": "Hips",
    "root": "Hips",
    # Left Leg
    "L_Hip": "LeftUpperLeg",
    "LeftUpLeg": "LeftUpperLeg",
    "L_Knee": "LeftLowerLeg",
    "LeftLeg": "LeftLowerLeg",
    "L_Ankle": "LeftFoot",
    "LeftFoot": "LeftFoot",
    "L_Foot": "LeftToes",
    "LeftToe": "LeftToes",
    # Right Leg
    "R_Hip": "RightUpperLeg",
    "RightUpLeg": "RightUpperLeg",
    "R_Knee": "RightLowerLeg",
    "RightLeg": "RightLowerLeg",
    "R_Ankle": "RightFoot",
    "RightFoot": "RightFoot",
    "R_Foot": "RightToes",
    "RightToe": "RightToes",
    # Spine
    "Spine1": "Spine",
    "Spine": "Spine",
    "Spine2": "Chest",
    "Chest": "Chest",
    "Spine3": "UpperChest",
    "UpperChest": "UpperChest",
    # Head
    "Neck": "Neck",
    "Head": "Head",
    # Left Arm
    "L_Collar": "LeftShoulder",
    "LeftShoulder": "LeftShoulder",
    "L_Shoulder": "LeftUpperArm",
    "L_UpArm": "LeftUpperArm",
    "L_Elbow": "LeftLowerArm",
    "L_LowArm": "LeftLowerArm",
    "L_Wrist": "LeftHand",
    "L_Hand": "LeftHand",
    # Right Arm
    "R_Collar": "RightShoulder",
    "RightShoulder": "RightShoulder",
    "R_Shoulder": "RightUpperArm",
    "R_UpArm": "RightUpperArm",
    "R_Elbow": "RightLowerArm",
    "R_LowArm": "RightLowerArm",
    "R_Wrist": "RightHand",
    "R_Hand": "RightHand"
}


# This function is called by the editor after a scene is imported.
func post_import(scene_root):
    # 1. Find the Skeleton node recursively.
    var skeleton = find_skeleton(scene_root)
    if skeleton == null:
        print("Hunyuan Retargeter: No Skeleton node found in the imported scene. Skipping.")
        return scene_root

    # 2. Rename Bones based on the BONE_MAP.
    print("Hunyuan Retargeter: Starting bone renaming...")
    for i in range(skeleton.get_bone_count()):
        var old_name = skeleton.get_bone_name(i)
        if old_name in BONE_MAP:
            var new_name = BONE_MAP[old_name]
            skeleton.set_bone_name(i, new_name)
            print("  - Renamed '%s' -> '%s'" % [old_name, new_name])

    # 3. Force a T-Pose by applying a simple rotation fix to the arms.
    # Note: This is a simplified approach. Axis of rotation might need adjustment
    # depending on how the source model is oriented (e.g., Y-up vs Z-up).
    print("Hunyuan Retargeter: Applying T-Pose correction...")
    fix_arm_rotation(skeleton, "LeftUpperArm", left_arm_correction_deg)
    fix_arm_rotation(skeleton, "RightUpperArm", right_arm_correction_deg)

    print("Hunyuan Retargeter: Processing complete.")
    return scene_root


# Recursively searches for a Skeleton node starting from the given node.
func find_skeleton(node):
    if node is Skeleton:
        return node
    for child in node.get_children():
        var result = find_skeleton(child)
        if result:
            return result
    return null


# Applies a rotation to a bone's rest transform.
func fix_arm_rotation(skel, bone_name, angle_deg):
    var bone_idx = skel.find_bone(bone_name)
    if bone_idx != -1:
        var rest_transform = skel.get_bone_rest(bone_idx)

        # Create a rotation quaternion around the Z-axis.
        # This is a common axis for arm rotation from an A-Pose to a T-Pose
        # if the character is facing forward (-Z axis in Godot).
        var rotation_axis = Vector3(0, 0, 1)
        var rotation_quat = Quat(rotation_axis, deg2rad(angle_deg))

        # Combine the original rest basis with the new rotation.
        var new_basis = rest_transform.basis * rotation_quat
        var new_transform = Transform(new_basis, rest_transform.origin)

        skel.set_bone_rest(bone_idx, new_transform)
        print("  - Applied %.1f degree rotation to '%s'" % [angle_deg, bone_name])
    else:
        print("  - Warning: Could not find bone '%s' to apply T-Pose correction." % bone_name)
