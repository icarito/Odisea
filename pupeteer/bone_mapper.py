import numpy as np
from scipy.spatial.transform import Rotation as R
import json

# --- Configuration (self-contained) ---

LANDMARK_INDICES = {
    'nose': 0, 'left_eye_inner': 1, 'left_eye': 2, 'left_eye_outer': 3, 'right_eye_inner': 4, 'right_eye': 5, 'right_eye_outer': 6, 'left_ear': 7, 'right_ear': 8, 'mouth_left': 9, 'mouth_right': 10,
    'left_shoulder': 11, 'right_shoulder': 12, 'left_elbow': 13, 'right_elbow': 14, 'left_wrist': 15, 'right_wrist': 16, 'left_pinky': 17, 'right_pinky': 18, 'left_index': 19, 'right_index': 20, 'left_thumb': 21, 'right_thumb': 22,
    'left_hip': 23, 'right_hip': 24, 'left_knee': 25, 'right_knee': 26, 'left_ankle': 27, 'right_ankle': 28, 'left_heel': 29, 'right_heel': 30, 'left_foot_index': 31, 'right_foot_index': 32
}

# The bone hierarchy for processing. Parents must come before children.
BONE_HIERARCHY = [
    "DEF-hips",
    "DEF-spine001", "DEF-spine002", "DEF-spine003",
    "DEF-neck", "DEF-head",
    "DEF-shoulderL", "DEF-upper_armL", "DEF-forearmL", "DEF-handL",
    "DEF-shoulderR", "DEF-upper_armR", "DEF-forearmR", "DEF-handR",
    "DEF-thighL", "DEF-shinL", "DEF-footL",
    "DEF-thighR", "DEF-shinR", "DEF-footR"
]

# Mapping from Godot bones to the MediaPipe landmarks that define their vectors.
# The vector is defined from the first landmark (parent) to the second (child).
BONE_TO_LANDMARKS = {
    "DEF-hips": ("hips", "neck"), # Drives the root rotation
    "DEF-spine001": ("hips", "neck"), # All spine bones follow hips-to-neck
    "DEF-spine002": ("hips", "neck"),
    "DEF-spine003": ("hips", "neck"),
    "DEF-neck": ("shoulders", "nose"),
    "DEF-head": ("shoulders", "nose"),
    "DEF-upper_armL": ("left_shoulder", "left_elbow"),
    "DEF-forearmL": ("left_elbow", "left_wrist"),
    "DEF-upper_armR": ("right_shoulder", "right_elbow"),
    "DEF-forearmR": ("right_elbow", "right_wrist"),
    "DEF-thighL": ("left_hip", "left_knee"),
    "DEF-shinL": ("left_knee", "left_ankle"),
    "DEF-thighR": ("right_hip", "right_knee"),
    "DEF-shinR": ("right_knee", "right_ankle"),
}

# Defines the parent of each bone in the hierarchy.
BONE_PARENTS = {
    "DEF-spine001": "DEF-hips", "DEF-spine002": "DEF-spine001", "DEF-spine003": "DEF-spine002",
    "DEF-neck": "DEF-spine003", "DEF-head": "DEF-neck",
    "DEF-shoulderL": "DEF-spine003", "DEF-upper_armL": "DEF-shoulderL", "DEF-forearmL": "DEF-upper_armL", "DEF-handL": "DEF-forearmL",
    "DEF-shoulderR": "DEF-spine003", "DEF-upper_armR": "DEF-shoulderR", "DEF-forearmR": "DEF-upper_armR", "DEF-handR": "DEF-forearmR",
    "DEF-thighL": "DEF-hips", "DEF-shinL": "DEF-thighL", "DEF-footL": "DEF-shinL",
    "DEF-thighR": "DEF-hips", "DEF-shinR": "DEF-thighR", "DEF-footR": "DEF-shinR",
}

# --- Caching for reference data ---
_tpose_ref_vectors = None
_tpose_ref_landmarks = None
_tpose_ref_scale_dist = None

def _initialize_reference_data():
    """Loads and computes reference data from tpose_posenet.json just once."""
    global _tpose_ref_vectors, _tpose_ref_landmarks, _tpose_ref_scale_dist
    if _tpose_ref_vectors is not None:
        return

    try:
        with open('tpose_posenet.json', 'r') as f:
            # The actual landmarks are in the 'keypoints' list
            keypoints_data = json.load(f).get('keypoints', [])
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"ERROR: Could not read or parse tpose_posenet.json: {e}")
        return

    # Create a reverse map from index to name for quick lookup
    INDICES_TO_LANDMARK_NAME = {v: k for k, v in LANDMARK_INDICES.items()}

    # 1. Load landmarks from the JSON structure
    raw_landmarks = {}
    for lm in keypoints_data:
        try:
            part_index = int(lm.get('part', -1))
            name = INDICES_TO_LANDMARK_NAME.get(part_index)
            if name:
                pos = lm.get('position', {})
                x = pos.get('x')
                y = pos.get('y')
                # z is at the top level in the tpose_posenet.json structure
                z = lm.get('z', 0.0)
                if x is not None and y is not None:
                    raw_landmarks[name] = np.array([x, -y, z])
        except (ValueError, TypeError):
            # Skip malformed entries
            continue

    # Create virtual landmarks (hips, neck, shoulders)
    _tpose_ref_landmarks = raw_landmarks # Start with the loaded landmarks

    # Calculate shoulders first, as it's a reliable fallback
    if "left_shoulder" in _tpose_ref_landmarks and "right_shoulder" in _tpose_ref_landmarks:
        _tpose_ref_landmarks["shoulders"] = (_tpose_ref_landmarks.get("left_shoulder") + _tpose_ref_landmarks.get("right_shoulder")) / 2
    else:
        print("ERROR: tpose_posenet.json is missing shoulder landmarks. Cannot create virtual bones.")
        _tpose_ref_vectors = {} # Prevent further processing
        return

    # Calculate hips, with fallback to shoulders
    if "left_hip" in _tpose_ref_landmarks and "right_hip" in _tpose_ref_landmarks:
        _tpose_ref_landmarks["hips"] = (_tpose_ref_landmarks.get("left_hip") + _tpose_ref_landmarks.get("right_hip")) / 2
    else:
        print("WARNING: 'left_hip' or 'right_hip' not found in T-pose. Estimating hips from shoulders.")
        # Estimate hips position below the shoulders. This is a rough approximation.
        _tpose_ref_landmarks["hips"] = _tpose_ref_landmarks["shoulders"] - np.array([0, 0.5, 0])


    _tpose_ref_landmarks["neck"] = _tpose_ref_landmarks["shoulders"] # Approximation

    # 2. Calculate reference vectors
    _tpose_ref_vectors = {}
    for bone_name, (p1_name, p2_name) in BONE_TO_LANDMARKS.items():
        p1 = _tpose_ref_landmarks.get(p1_name)
        p2 = _tpose_ref_landmarks.get(p2_name)
        if p1 is not None and p2 is not None:
            _tpose_ref_vectors[bone_name] = p2 - p1
    
    # 3. Calculate reference scale distance
    if "neck" in _tpose_ref_landmarks and "hips" in _tpose_ref_landmarks:
        _tpose_ref_scale_dist = np.linalg.norm(_tpose_ref_landmarks["neck"] - _tpose_ref_landmarks["hips"])
    else:
        _tpose_ref_scale_dist = 1.0 # Default value if landmarks are missing


def get_bone_vector(bone_name, landmarks):
    """Calculates the vector for a bone from a given set of landmarks."""
    lm_map = BONE_TO_LANDMARKS.get(bone_name)
    if not lm_map:
        return None
    
    p1 = landmarks.get(lm_map[0])
    p2 = landmarks.get(lm_map[1])

    if p1 is not None and p2 is not None:
        return p2 - p1
    return None

def posenet_to_godot_bones(landmarks_current_raw, tpose_godot):
    _initialize_reference_data()
    if _tpose_ref_vectors is None:
        return {}

    # --- Step 1: Create landmark dictionary and virtual landmarks ---
    landmarks_current = {}
    for key, index in LANDMARK_INDICES.items():
        if index < len(landmarks_current_raw):
            lm = landmarks_current_raw[index]
            # Invertir Z para alinear con Godot
            landmarks_current[key] = np.array([lm['x'], -lm['y'], -lm['z']])

    if 'left_hip' not in landmarks_current or 'right_hip' not in landmarks_current or \
       'left_shoulder' not in landmarks_current or 'right_shoulder' not in landmarks_current:
        return {} # Not enough data
        
    landmarks_current["hips"] = (landmarks_current["left_hip"] + landmarks_current["right_hip"]) / 2
    landmarks_current["shoulders"] = (landmarks_current["left_shoulder"] + landmarks_current["right_shoulder"]) / 2
    landmarks_current["neck"] = landmarks_current["shoulders"] # Approximation

    # --- Step 2: Scale Correction (UPose Method) ---
    current_scale_dist = np.linalg.norm(landmarks_current["neck"] - landmarks_current["hips"])
    scale_factor = _tpose_ref_scale_dist / current_scale_dist if current_scale_dist > 1e-6 else 1.0

    landmarks_scaled = {name: pos * scale_factor for name, pos in landmarks_current.items()}
    
    # --- Step 3: Hierarchical Rotation Calculation ---
    final_bones = {}
    global_rotations = {} # Cache for global rotations: { "bone_name": Scipy_Rotation }
    
    for bone_name in BONE_HIERARCHY:
        V_ref = _tpose_ref_vectors.get(bone_name)
        V_capt = get_bone_vector(bone_name, landmarks=landmarks_scaled)
        
        Q_global = R.identity()
        if V_ref is not None and V_capt is not None and np.linalg.norm(V_ref) > 1e-6 and np.linalg.norm(V_capt) > 1e-6:
            # R.align_vectors finds the rotation between two vectors
            Q_global, _ = R.align_vectors([V_capt], [V_ref])
        
        global_rotations[bone_name] = Q_global

        # --- Convert to Local Rotation ---
        parent_name = BONE_PARENTS.get(bone_name)
        if parent_name is None: # Root bone
            # --- Offset de rotación de T-Pose para la cadera ---
            tpose_hips_quat_wxyz = tpose_godot.get("DEF-hips", [0, 0, 0, 1, 0, 0, 0])[3:]
            tpose_hips_quat_xyzw = [tpose_hips_quat_wxyz[1], tpose_hips_quat_wxyz[2], tpose_hips_quat_wxyz[3], tpose_hips_quat_wxyz[0]]
            Q_tpose_godot = R.from_quat(tpose_hips_quat_xyzw)
            Q_local = Q_global * Q_tpose_godot
        else:
            Q_global_padre = global_rotations.get(parent_name, R.identity())
            Q_local = Q_global_padre.inv() * Q_global

        # --- Store Final Bone Transform ---
        if bone_name == "DEF-hips":
            # Escala y ejes correctos para Godot
            hips_tpose_godot_y = tpose_godot.get("DEF-hips", [0, 0, 0])[1]
            delta_y = landmarks_scaled['hips'][1] - _tpose_ref_landmarks['hips'][1]
            pos_out = np.array([
                landmarks_scaled['hips'][0],
                hips_tpose_godot_y + delta_y,
                -landmarks_scaled['hips'][2]
            ])
            # Invertir Y si sigue siendo negativa (altura debe ser positiva en Godot)
            if pos_out[1] < 0:
                pos_out[1] = abs(pos_out[1])
            final_bones[bone_name] = list(pos_out) + list(Q_local.as_quat())
        elif bone_name in tpose_godot:
            # For all other bones, use the T-pose's local position and the new local rotation
            tpose_local_pos = tpose_godot[bone_name][:3]
            final_bones[bone_name] = list(tpose_local_pos) + list(Q_local.as_quat())

    return final_bones
