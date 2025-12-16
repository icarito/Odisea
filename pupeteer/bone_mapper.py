import numpy as np
from scipy.spatial.transform import Rotation as R
from config import LANDMARK_INDICES
from retarget_utils import limb_quat

# --- Bone Hierarchy and Mapping ---
# This data is now self-contained to avoid issues with config.py
# The order is crucial: parents must appear before their children.
BONE_HIERARCHY = [
    "DEF-hips",
    "DEF-spine001", "DEF-spine002", "DEF-spine003", "DEF-neck", "DEF-head",
    "DEF-thighL", "DEF-shinL", "DEF-footL",
    "DEF-thighR", "DEF-shinR", "DEF-footR",
    "DEF-shoulderL", "DEF-upper_armL", "DEF-forearmL", "DEF-handL",
    "DEF-shoulderR", "DEF-upper_armR", "DEF-forearmR", "DEF-handR",
]

BONE_PARENTS = {
    "DEF-spine001": "DEF-hips", "DEF-spine002": "DEF-spine001", "DEF-spine003": "DEF-spine002",
    "DEF-neck": "DEF-spine003", "DEF-head": "DEF-neck",

    "DEF-thighL": "DEF-hips", "DEF-shinL": "DEF-thighL", "DEF-footL": "DEF-shinL",
    "DEF-thighR": "DEF-hips", "DEF-shinR": "DEF-thighR", "DEF-footR": "DEF-shinR",
    
    "DEF-shoulderL": "DEF-spine003", "DEF-upper_armL": "DEF-shoulderL", "DEF-forearmL": "DEF-upper_armL", "DEF-handL": "DEF-forearmL",
    "DEF-shoulderR": "DEF-spine003", "DEF-upper_armR": "DEF-shoulderR", "DEF-forearmR": "DEF-upper_armR", "DEF-handR": "DEF-forearmR",
}

def _get_landmark_pos(landmarks, key, lm_pos_cache):
    """Helper to get a landmark's position vector, using a cache."""
    if key in lm_pos_cache:
        return lm_pos_cache[key]
    
    index = LANDMARK_INDICES.get(key)
    if index is not None and index < len(landmarks):
        lm = landmarks[index]
        # PRUEBA: Solo invertir eje Z (Godot: Y+ arriba, Z- adelante)
        pos = np.array([lm['x'], lm['y'], -lm['z']])
        lm_pos_cache[key] = pos
        return pos
    return None

def posenet_to_godot_bones(landmarks, tpose_godot):
    if not landmarks or not tpose_godot:
        return {}

    # --- Constants for Corrections ---
    SCALE_FACTOR = 0.001
    ROOT_OFFSET_Y = -1.0  # Calibrate this value to adjust character height
    ROOT_OFFSET_Z = 0.5   # Nuevo offset para empujar el personaje hacia atrás (Z+)
    TILT_CORRECTION = R.from_euler('x', 20, degrees=True) # Corrects forward tilt
    # Flips the arm rotation on its twist axis

    lm_pos_cache = {}
    def get_lm(key):
        return _get_landmark_pos(landmarks, key, lm_pos_cache)

    # --- Compute virtual landmarks ---
    left_hip = get_lm('left_hip')
    right_hip = get_lm('right_hip')
    left_shoulder = get_lm('left_shoulder')
    right_shoulder = get_lm('right_shoulder')
    nose = get_lm('nose')

    if left_hip is None or right_hip is None or left_shoulder is None or right_shoulder is None:
        return {} # Need hips and shoulders

    hips_center = (left_hip + right_hip) / 2
    shoulders_center = (left_shoulder + right_shoulder) / 2
    
    # --- Hierarchical Calculation ---
    final_bones = {}
    global_bone_rotations = {}
    
    # --- Root Position and Scaling (with Y Offset) ---
    final_root_pos = hips_center * SCALE_FACTOR
    final_root_pos[1] += ROOT_OFFSET_Y # Offset vertical (Y)
    final_root_pos[2] += ROOT_OFFSET_Z # Offset horizontal (Z)
    final_bones["_SKELETON_ROOT_POS"] = final_root_pos.tolist() + [0, 0, 0, 1]

    # --- Hips (Root of animated skeleton) ---
    hips_to_shoulders_vec = shoulders_center - hips_center
    # PRUEBA: ref_vec apunta hacia arriba (Y+) pero con Y no invertido
    hips_global_rot_capture = R.from_quat(limb_quat(np.array([0,1,0]), hips_to_shoulders_vec, ref_vec=np.array([0, 1, 0])))

    # Offset global: rotación de 90° en X + flip 180° en Y
    offset_rot = R.from_euler('xy', [90, 180], degrees=True)

    hip_tpose_quat_xyzw = tpose_godot["DEF-hips"][3:]
    hip_tpose_rotation = R.from_quat(hip_tpose_quat_xyzw)

    # Apply T-Pose retargeting, tilt correction y offset global
    final_hips_rotation = offset_rot * hips_global_rot_capture * hip_tpose_rotation.inv() * TILT_CORRECTION
    global_bone_rotations["DEF-hips"] = final_hips_rotation

    hip_tpose_pos = tpose_godot.get("DEF-hips", [0,0,0,0,0,0,1])[:3]
    final_bones["DEF-hips"] = list(hip_tpose_pos) + list(final_hips_rotation.as_quat())

    # --- Process all other bones hierarchically ---
    for bone_name in BONE_HIERARCHY:
        if bone_name == "DEF-hips":
            continue
        
        parent_name = BONE_PARENTS.get(bone_name)
        if not parent_name or parent_name not in global_bone_rotations:
            continue
            
        parent_global_rot = global_bone_rotations[parent_name]
        
        # --- Calculate child's global rotation from landmarks ---
        child_global_rot = None
        start_lm, end_lm = None, None
        
        if "thigh" in bone_name:
            start_lm = get_lm('left_hip' if 'L' in bone_name else 'right_hip')
            end_lm = get_lm('left_knee' if 'L' in bone_name else 'right_knee')
            if start_lm is not None and end_lm is not None:
                # Usar Y+ como referencia para flexión de pierna
                child_global_rot = R.from_quat(limb_quat(start_lm, end_lm, ref_vec=np.array([0, 1, 0])))
        elif "shin" in bone_name:
            start_lm = get_lm('left_knee' if 'L' in bone_name else 'right_knee')
            end_lm = get_lm('left_ankle' if 'L' in bone_name else 'right_ankle')
            if start_lm is not None and end_lm is not None:
                child_global_rot = R.from_quat(limb_quat(start_lm, end_lm, ref_vec=np.array([0, 1, 0])))
        elif "upper_arm" in bone_name:
            start_lm = get_lm('left_shoulder' if 'L' in bone_name else 'right_shoulder')
            end_lm = get_lm('left_elbow' if 'L' in bone_name else 'right_elbow')
            if start_lm is not None and end_lm is not None:
                # Convención clásica: X+ para L, X- para R
                ref_vec = np.array([1, 0, 0]) if 'L' in bone_name else np.array([-1, 0, 0])
                quat = limb_quat(start_lm, end_lm, ref_vec=ref_vec)
                child_global_rot = R.from_quat(quat)
        elif "forearm" in bone_name:
            start_lm = get_lm('left_elbow' if 'L' in bone_name else 'right_elbow')
            end_lm = get_lm('left_wrist' if 'L' in bone_name else 'right_wrist')
            if start_lm is not None and end_lm is not None:
                ref_vec = np.array([1, 0, 0]) if 'L' in bone_name else np.array([-1, 0, 0])
                quat = limb_quat(start_lm, end_lm, ref_vec=ref_vec)
                child_global_rot = R.from_quat(quat)
        elif "head" in bone_name or "neck" in bone_name or "spine" in bone_name:
            # For spine, neck, and head, just inherit parent's rotation for simplicity for now
            child_global_rot = parent_global_rot
        
        if child_global_rot is None:
            child_global_rot = parent_global_rot # Fallback to parent rotation
            
        global_bone_rotations[bone_name] = child_global_rot

        # --- Convert to local rotation ---
        local_rot = parent_global_rot.inv() * child_global_rot


        # --- Store final bone data (STATIC position + DYNAMIC rotation) ---
        bone_tpose_pos = tpose_godot.get(bone_name, [0,0,0,0,0,0,1])[:3]
        final_bones[bone_name] = list(bone_tpose_pos) + list(local_rot.as_quat())

    return {k: v for k, v in final_bones.items() if k in tpose_godot or k == "_SKELETON_ROOT_POS"}