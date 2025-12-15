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
    
    # Shoulders are tricky. Let's parent them to the upper spine.
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
        pos = np.array([lm['x'], -lm['y'], lm['z']]) # Use Y-up coordinate system internally
        lm_pos_cache[key] = pos
        return pos
    return None

def posenet_to_godot_bones(landmarks, tpose_godot):
    if not landmarks or not tpose_godot:
        return {}

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
    tpose_global_rotations = {}

    # Calcular rotaciones globales de T-Pose (Rest pose) para cada hueso
    for bone_name in BONE_HIERARCHY:
        if bone_name not in tpose_godot:
            continue
        parent_name = BONE_PARENTS.get(bone_name)
        if not parent_name or parent_name not in tpose_godot:
            # Raíz
            tpose_global_rotations[bone_name] = R.from_quat(tpose_godot[bone_name][3:7])
        else:
            parent_rot = tpose_global_rotations[parent_name]
            local_rot = R.from_quat(tpose_godot[bone_name][3:7])
            tpose_global_rotations[bone_name] = parent_rot * local_rot

    # Hips (raíz)
    hips_to_shoulders_vec = shoulders_center - hips_center
    hips_global_rot_quat = limb_quat(np.array([0,0,0]), hips_to_shoulders_vec, ref_vec=np.array([0, 1, 0]))
    global_bone_rotations["DEF-hips"] = R.from_quat(hips_global_rot_quat)
    hips_tpose_pos = tpose_godot["DEF-hips"][:3]
    final_bones["DEF-hips"] = list(hips_tpose_pos) + list(hips_global_rot_quat)


    # Procesar huesos en orden jerárquico
    for bone_name in BONE_HIERARCHY:
        if bone_name == "DEF-hips":
            continue
        parent_name = BONE_PARENTS.get(bone_name)
        if not parent_name or parent_name not in global_bone_rotations:
            continue
        parent_global_rot = global_bone_rotations[parent_name]
        child_global_rot = R.identity()

        # --- Calcular rotación global para el hueso actual (captura) ---
        if "thigh" in bone_name:
            hip = get_lm('left_hip' if 'L' in bone_name else 'right_hip')
            knee = get_lm('left_knee' if 'L' in bone_name else 'right_knee')
            if hip is not None and knee is not None:
                child_global_rot = R.from_quat(limb_quat(hip, knee, ref_vec=np.array([0, -1, 0])))
        elif "shin" in bone_name:
            knee = get_lm('left_knee' if 'L' in bone_name else 'right_knee')
            ankle = get_lm('left_ankle' if 'L' in bone_name else 'right_ankle')
            if knee is not None and ankle is not None:
                child_global_rot = R.from_quat(limb_quat(knee, ankle, ref_vec=np.array([0, -1, 0])))
        elif "upper_arm" in bone_name:
            shoulder = get_lm('left_shoulder' if 'L' in bone_name else 'right_shoulder')
            elbow = get_lm('left_elbow' if 'L' in bone_name else 'right_elbow')
            if shoulder is not None and elbow is not None:
                ref_vec = np.array([-1, 0, 0]) if 'L' in bone_name else np.array([1, 0, 0])
                child_global_rot = R.from_quat(limb_quat(shoulder, elbow, ref_vec=ref_vec))
        elif "forearm" in bone_name:
            elbow = get_lm('left_elbow' if 'L' in bone_name else 'right_elbow')
            wrist = get_lm('left_wrist' if 'L' in bone_name else 'right_wrist')
            if elbow is not None and wrist is not None:
                ref_vec = np.array([-1, 0, 0]) if 'L' in bone_name else np.array([1, 0, 0])
                child_global_rot = R.from_quat(limb_quat(elbow, wrist, ref_vec=ref_vec))
        elif "head" in bone_name or "neck" in bone_name:
            if nose is not None:
                child_global_rot = R.from_quat(limb_quat(shoulders_center, nose, ref_vec=np.array([0, 1, 0])))
        else:
            child_global_rot = parent_global_rot

        # Guardar rotación global para hijos
        global_bone_rotations[bone_name] = child_global_rot

        # --- Convertir a rotación local relativa al padre en la pose capturada ---
        # Q_local = (Q_parent_global)^-1 * Q_child_global
        local_rot = parent_global_rot.inv() * child_global_rot

        bone_tpose_pos = tpose_godot.get(bone_name, [0,0,0,0,0,0,1])[:3]
        final_bones[bone_name] = list(bone_tpose_pos) + list(local_rot.as_quat())

    # Solo huesos válidos
    return {k: v for k, v in final_bones.items() if k in tpose_godot}
