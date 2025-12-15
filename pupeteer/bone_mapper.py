import numpy as np
from scipy.spatial.transform import Rotation as R
from config import LANDMARK_INDICES, BONE_HIERARCHY, BONE_PARENTS, BONE_LANDMARKS
from retarget_utils import quat_from_two_vectors, local_quat

def _get_landmark_pos(landmarks, key):
    """Helper to get a landmark's position vector."""
    if key in LANDMARK_INDICES and LANDMARK_INDICES[key] < len(landmarks):
        lm = landmarks[LANDMARK_INDICES[key]]
        return np.array([lm['x'], lm['y'], lm['z']])
    return None

def _compute_virtual_landmarks(landmarks):
    """Computes and adds virtual landmarks like hips, chest, and neck."""
    left_hip = _get_landmark_pos(landmarks, 'left_hip')
    right_hip = _get_landmark_pos(landmarks, 'right_hip')
    left_shoulder = _get_landmark_pos(landmarks, 'left_shoulder')
    right_shoulder = _get_landmark_pos(landmarks, 'right_shoulder')
    nose = _get_landmark_pos(landmarks, 'nose')

    if left_hip is not None and right_hip is not None:
        hips_pos = (left_hip + right_hip) / 2
        landmarks.append({'x': hips_pos[0], 'y': hips_pos[1], 'z': hips_pos[2]})

    if left_shoulder is not None and right_shoulder is not None:
        chest_pos = (left_shoulder + right_shoulder) / 2
        landmarks.append({'x': chest_pos[0], 'y': chest_pos[1], 'z': chest_pos[2]})
        
        if nose is not None:
            neck_pos = (chest_pos + nose) / 2
            landmarks.append({'x': neck_pos[0], 'y': neck_pos[1], 'z': neck_pos[2]})

    return landmarks

def posenet_to_godot_bones(landmarks, tpose_godot):
    """
    Converts MediaPipe landmarks to a dictionary of Godot bone transformations
    using a hierarchical approach to compute local quaternions.
    """
    if not landmarks or not tpose_godot:
        return {}

    landmarks = _compute_virtual_landmarks(list(landmarks))

    # --- Scaling and Offset ---
    # Calculate scale based on shoulder distance
    tpose_shoulder_l = np.array(tpose_godot.get('DEF-shoulderL', [0,0,0])[:3])
    tpose_shoulder_r = np.array(tpose_godot.get('DEF-shoulderR', [0,0,0])[:3])
    godot_shoulder_dist = np.linalg.norm(tpose_shoulder_l - tpose_shoulder_r)

    mp_shoulder_l = _get_landmark_pos(landmarks, 'left_shoulder')
    mp_shoulder_r = _get_landmark_pos(landmarks, 'right_shoulder')
    
    if mp_shoulder_l is None or mp_shoulder_r is None:
        return {} # Not enough landmarks for scaling
        
    mediapipe_shoulder_dist = np.linalg.norm(mp_shoulder_l - mp_shoulder_r)
    scale = godot_shoulder_dist / (mediapipe_shoulder_dist + 1e-8)

    # Calculate offset based on hips position
    tpose_hips = np.array(tpose_godot.get('DEF-hips', [0,0,0])[:3])
    mp_hips = _get_landmark_pos(landmarks, 'hips')
    if mp_hips is None:
        return {}
    offset = tpose_hips - mp_hips * scale

    def transform_mediapipe_pos(p):
        return p * scale + offset

    # --- Hierarchical Calculation ---
    final_bones = {}
    parent_global_rots = {"DEF-hips": R.identity()}
    parent_global_positions = {"DEF-hips": transform_mediapipe_pos(mp_hips)}
    final_bones["DEF-hips"] = list(parent_global_positions["DEF-hips"]) + [0, 0, 0, 1]

    for bone_name in BONE_HIERARCHY:
        if bone_name == "DEF-hips":
            continue

        parent_name = BONE_PARENTS.get(bone_name)
        if not parent_name:
            continue
            
        # Get parent's global transform (already computed)
        parent_rot_global = parent_global_rots.get(parent_name, R.identity())
        parent_pos_global = parent_global_positions.get(parent_name)

        if parent_pos_global is None:
            continue

        # Get T-Pose bone data
        bone_data_tpose = np.array(tpose_godot.get(bone_name, [0,0,0,0,0,0,1]))
        parent_data_tpose = np.array(tpose_godot.get(parent_name, [0,0,0,0,0,0,1]))
        
        # Vector from parent to bone in T-Pose (rest pose)
        v_rest = bone_data_tpose[:3] - parent_data_tpose[:3]

        # Get captured landmark positions
        bone_lm_keys = BONE_LANDMARKS.get(bone_name)
        if not bone_lm_keys:
            continue
            
        lm_positions = [_get_landmark_pos(landmarks, key) for key in bone_lm_keys]
        lm_positions = [p for p in lm_positions if p is not None]
        if not lm_positions:
            continue
            
        captured_pos_mp = np.mean(lm_positions, axis=0)
        captured_pos_global = transform_mediapipe_pos(captured_pos_mp)
        
        # Vector from parent to bone in captured pose
        v_captured = captured_pos_global - parent_pos_global

        if np.linalg.norm(v_rest) < 1e-6 or np.linalg.norm(v_captured) < 1e-6:
            continue

        # Calculate rotation that aligns rest vector to captured vector
        q_align = quat_from_two_vectors(v_rest, v_captured)
        
        # The final local rotation is the alignment applied to the T-pose local rotation
        # (For a simple skeleton where T-pose bones are aligned with axes, this is sufficient)
        # A more robust solution would compose it with the rest pose's local quaternion.
        final_local_quat = q_align

        # Store results for this bone
        final_bones[bone_name] = list(captured_pos_global) + list(final_local_quat)
        
        # Store global rotation for children
        # This is simplified. A full FK system would be more complex.
        parent_global_rots[bone_name] = parent_rot_global * R.from_quat(final_local_quat)
        parent_global_positions[bone_name] = captured_pos_global

    # Return only the bones that are in the hierarchy
    return {k: v for k, v in final_bones.items() if k in BONE_HIERARCHY}
