import numpy as np
from config import LANDMARK_INDICES
from retarget_utils import quat_from_two_vectors

def posenet_to_godot_bones(landmarks, tpose_godot, mapeo=None):
    """
    Convierte keypoints de PoseNet a formato de huesos Godot (posición+cuaternión local).
    Si falta algún keypoint, usa identidad o posición por defecto.
    tpose_godot: dict de huesos Godot (nombre: [x, y, z, qx, qy, qz, qw])
    mapeo: dict opcional PoseNet→Godot
    """
    if not landmarks or not tpose_godot:
        return {}
    # Mapeo razonable por defecto
    if mapeo is None:
        mapeo = {
            'hips': ('hips', ['left_hip', 'right_hip']),
            'spine': ('spine', ['left_hip', 'right_hip', 'left_shoulder', 'right_shoulder']),
            'chest': ('chest', ['left_shoulder', 'right_shoulder']),
            'neck': ('neck', ['left_shoulder', 'right_shoulder', 'nose']),
            'head': ('head', ['nose']),
            'shoulder.L': ('shoulderL', ['left_shoulder']),
            'elbow.L': ('upper_armL', ['left_elbow']),
            'wrist.L': ('forearmL', ['left_wrist']),
            'shoulder.R': ('shoulderR', ['right_shoulder']),
            'elbow.R': ('upper_armR', ['right_elbow']),
            'wrist.R': ('forearmR', ['right_wrist']),
            'upperLeg.L': ('thighL', ['left_hip']),
            'knee.L': ('shinL', ['left_knee']),
            'ankle.L': ('footL', ['left_ankle']),
            'upperLeg.R': ('thighR', ['right_hip']),
            'knee.R': ('shinR', ['right_knee']),
            'ankle.R': ('footR', ['right_ankle']),
        }
    # --- Escalado y offset global para alinear con Godot ---
    # Usar caderas como referencia para centro y escala
    hips_godot = np.array(tpose_godot.get('DEF-hips', [0,0,0,0,0,0,1]))[:3]
    left_hip_idx = LANDMARK_INDICES.get('left_hip', 23)
    right_hip_idx = LANDMARK_INDICES.get('right_hip', 24)
    if left_hip_idx < len(landmarks) and right_hip_idx < len(landmarks):
        hips_posenet = (np.array([landmarks[left_hip_idx]['x'], landmarks[left_hip_idx]['y'], landmarks[left_hip_idx]['z']]) +
                       np.array([landmarks[right_hip_idx]['x'], landmarks[right_hip_idx]['y'], landmarks[right_hip_idx]['z']])) / 2
    else:
        hips_posenet = np.array([0,0,0])
    # Escala: distancia entre hombros en Godot y en PoseNet
    left_shoulder_idx = LANDMARK_INDICES.get('left_shoulder', 11)
    right_shoulder_idx = LANDMARK_INDICES.get('right_shoulder', 12)
    if left_shoulder_idx < len(landmarks) and right_shoulder_idx < len(landmarks):
        godot_shoulder = np.array(tpose_godot.get('DEF-shoulderL', [0,0,0,0,0,0,1]))[:3]
        godot_shoulder_r = np.array(tpose_godot.get('DEF-shoulderR', [0,0,0,0,0,0,1]))[:3]
        godot_shoulder_dist = np.linalg.norm(godot_shoulder - godot_shoulder_r)
        posenet_shoulder = np.array([landmarks[left_shoulder_idx]['x'], landmarks[left_shoulder_idx]['y'], landmarks[left_shoulder_idx]['z']])
        posenet_shoulder_r = np.array([landmarks[right_shoulder_idx]['x'], landmarks[right_shoulder_idx]['y'], landmarks[right_shoulder_idx]['z']])
        posenet_shoulder_dist = np.linalg.norm(posenet_shoulder - posenet_shoulder_r)
        scale = godot_shoulder_dist / (posenet_shoulder_dist + 1e-8)
    else:
        scale = 1.0
    # Offset: hips Godot menos hips PoseNet (escalado)
    offset = hips_godot - hips_posenet * scale
    # Función para transformar keypoints
    def transform_pos(p):
        return np.array(p) * scale + offset
    
    bones = {}

    def get_pos(keys):
        pts = [landmarks[LANDMARK_INDICES[k]] for k in keys if k in LANDMARK_INDICES and LANDMARK_INDICES[k] < len(landmarks)]
        if pts:
            arr = np.array([[p['x'], p['y'], p['z']] for p in pts])
            arr = np.array([transform_pos(a) for a in arr])
            return arr.mean(axis=0)
        return None

    for godot_bone, (tpose_bone, kp_keys) in mapeo.items():
        pos = get_pos(kp_keys)
        tpose = np.array(tpose_godot.get('DEF-'+tpose_bone, [0,0,0,0,0,0,1]))
        if pos is not None:
            v_ref = tpose[:3]
            v_cap = pos
            if np.linalg.norm(v_ref) < 1e-6 or np.linalg.norm(v_cap) < 1e-6:
                q_global = [0, 0, 0, 1]
            else:
                try:
                    q_global = quat_from_two_vectors(v_ref, v_cap)
                except Exception:
                    q_global = [0, 0, 0, 1]
            bones[godot_bone] = list(pos) + list(q_global)
        else:
            bones[godot_bone] = list(tpose)
    bones['root'] = [0,0,0,0,0,0,1]
    return bones

def map_pose_to_bones_quat(landmarks, height=1.78):
    """
    Igual a map_pose_to_bones pero calcula quaterniones reales para cada hueso principal.
    El quaternion es relativo al padre (local).
    """
    if not landmarks:
        return {}

    bones = {}

    # Hips
    left_hip = get_landmark(landmarks, 'left_hip')
    right_hip = get_landmark(landmarks, 'right_hip')
    if left_hip is not None and right_hip is not None:
        hips_pos = (left_hip + right_hip) / 2
        # Forward vector: de hips a chest
        left_shoulder = get_landmark(landmarks, 'left_shoulder')
        right_shoulder = get_landmark(landmarks, 'right_shoulder')
        if left_shoulder is not None and right_shoulder is not None:
            chest_pos = (left_shoulder + right_shoulder) / 2
            forward = chest_pos - hips_pos
            up = np.array([0, 1, 0])
            quat = quat_from_two_vectors(np.array([0, 0, 1]), forward)
            bones['hips'] = list(hips_pos) + list(quat)
        else:
            bones['hips'] = list(hips_pos) + [0, 0, 0, 1]

    # Chest
    if left_shoulder is not None and right_shoulder is not None:
        chest_pos = (left_shoulder + right_shoulder) / 2
        if 'hips' in bones:
            forward = chest_pos - np.array(bones['hips'][:3])
            quat = quat_from_two_vectors(np.array([0, 0, 1]), forward)
            bones['chest'] = list(chest_pos) + list(quat)
        else:
            bones['chest'] = list(chest_pos) + [0, 0, 0, 1]

        # Spine
        if 'hips' in bones:
            spine_pos = lerp(np.array(bones['hips'][:3]), chest_pos)
            forward = chest_pos - np.array(bones['hips'][:3])
            quat = quat_from_two_vectors(np.array([0, 0, 1]), forward)
            bones['spine'] = list(spine_pos) + list(quat)

        # Neck y Head
        nose = get_landmark(landmarks, 'nose')
        if nose is not None:
            neck_pos = lerp(chest_pos, nose)
            forward = nose - chest_pos
            quat = quat_from_two_vectors(np.array([0, 0, 1]), forward)
            bones['neck'] = list(neck_pos) + list(quat)
            bones['head'] = list(nose) + list(quat)

    # Limbs (ejemplo para brazo izquierdo)
    # Hombro -> codo -> muñeca
    def limb_quat(a, b):
        if a is not None and b is not None:
            v = b - a
            return quat_from_two_vectors(np.array([0, 0, 1]), v)
        return [0, 0, 0, 1]

    # Left Arm
    bones['shoulder.L'] = list(left_shoulder) + list(limb_quat(left_shoulder, get_landmark(landmarks, 'left_elbow'))) if left_shoulder is not None else [0,0,0,0,0,0,1]
    left_elbow = get_landmark(landmarks, 'left_elbow')
    bones['elbow.L'] = list(left_elbow) + list(limb_quat(left_elbow, get_landmark(landmarks, 'left_wrist'))) if left_elbow is not None else [0,0,0,0,0,0,1]
    left_wrist = get_landmark(landmarks, 'left_wrist')
    bones['wrist.L'] = list(left_wrist) + [0, 0, 0, 1] if left_wrist is not None else [0,0,0,0,0,0,1]

    # Right Arm
    bones['shoulder.R'] = list(right_shoulder) + list(limb_quat(right_shoulder, get_landmark(landmarks, 'right_elbow'))) if right_shoulder is not None else [0,0,0,0,0,0,1]
    right_elbow = get_landmark(landmarks, 'right_elbow')
    bones['elbow.R'] = list(right_elbow) + list(limb_quat(right_elbow, get_landmark(landmarks, 'right_wrist'))) if right_elbow is not None else [0,0,0,0,0,0,1]
    right_wrist = get_landmark(landmarks, 'right_wrist')
    bones['wrist.R'] = list(right_wrist) + [0, 0, 0, 1] if right_wrist is not None else [0,0,0,0,0,0,1]

    # Left Leg
    bones['upperLeg.L'] = list(left_hip) + list(limb_quat(left_hip, get_landmark(landmarks, 'left_knee'))) if left_hip is not None else [0,0,0,0,0,0,1]
    left_knee = get_landmark(landmarks, 'left_knee')
    bones['knee.L'] = list(left_knee) + list(limb_quat(left_knee, get_landmark(landmarks, 'left_ankle'))) if left_knee is not None else [0,0,0,0,0,0,1]
    left_ankle = get_landmark(landmarks, 'left_ankle')
    bones['ankle.L'] = list(left_ankle) + [0, 0, 0, 1] if left_ankle is not None else [0,0,0,0,0,0,1]

    # Right Leg
    bones['upperLeg.R'] = list(right_hip) + list(limb_quat(right_hip, get_landmark(landmarks, 'right_knee'))) if right_hip is not None else [0,0,0,0,0,0,1]
    right_knee = get_landmark(landmarks, 'right_knee')
    bones['knee.R'] = list(right_knee) + list(limb_quat(right_knee, get_landmark(landmarks, 'right_ankle'))) if right_knee is not None else [0,0,0,0,0,0,1]
    right_ankle = get_landmark(landmarks, 'right_ankle')
    bones['ankle.R'] = list(right_ankle) + [0, 0, 0, 1] if right_ankle is not None else [0,0,0,0,0,0,1]

    return bones
import numpy as np
from config import LANDMARK_INDICES

def get_landmark(landmarks, name):
    idx = LANDMARK_INDICES[name]
    if idx < len(landmarks):
        lm = landmarks[idx]
        return np.array([lm['x'], lm['y'], lm['z']])
    return None

def lerp(a, b, t=0.5):
    return a + t * (b - a)

def vector_to_quaternion(v, up=np.array([0, 1, 0])):
    # Simple quaternion from forward vector
    forward = v / np.linalg.norm(v)
    right = np.cross(up, forward)
    right /= np.linalg.norm(right)
    up = np.cross(forward, right)
    # Quaternion from rotation matrix
    m = np.eye(4)
    m[0:3, 0] = right
    m[0:3, 1] = up
    m[0:3, 2] = forward
    # Extract quaternion
    q = np.zeros(4)
    t = m[0,0] + m[1,1] + m[2,2]
    if t > 0:
        s = 0.5 / np.sqrt(t + 1)
        q[3] = 0.25 / s
        q[0] = (m[2,1] - m[1,2]) * s
        q[1] = (m[0,2] - m[2,0]) * s
        q[2] = (m[1,0] - m[0,1]) * s
    else:
        if m[0,0] > m[1,1] and m[0,0] > m[2,2]:
            s = 2 * np.sqrt(1 + m[0,0] - m[1,1] - m[2,2])
            q[3] = (m[2,1] - m[1,2]) / s
            q[0] = 0.25 * s
            q[1] = (m[0,1] + m[1,0]) / s
            q[2] = (m[0,2] + m[2,0]) / s
        elif m[1,1] > m[2,2]:
            s = 2 * np.sqrt(1 + m[1,1] - m[0,0] - m[2,2])
            q[3] = (m[0,2] - m[2,0]) / s
            q[0] = (m[0,1] + m[1,0]) / s
            q[1] = 0.25 * s
            q[2] = (m[1,2] + m[2,1]) / s
        else:
            s = 2 * np.sqrt(1 + m[2,2] - m[0,0] - m[1,1])
            q[3] = (m[1,0] - m[0,1]) / s
            q[0] = (m[0,2] + m[2,0]) / s
            q[1] = (m[1,2] + m[2,1]) / s
            q[2] = 0.25 * s
    return q

def map_pose_to_bones(landmarks, height=1.78):
    if not landmarks:
        return {}

    bones = {}

    # Positions
    left_hip = get_landmark(landmarks, 'left_hip')
    right_hip = get_landmark(landmarks, 'right_hip')
    if left_hip is not None and right_hip is not None:
        hips_pos = (left_hip + right_hip) / 2
        bones['hips'] = list(hips_pos) + [0, 0, 0, 1]  # pos + identity quat

    left_shoulder = get_landmark(landmarks, 'left_shoulder')
    right_shoulder = get_landmark(landmarks, 'right_shoulder')
    if left_shoulder is not None and right_shoulder is not None:
        chest_pos = (left_shoulder + right_shoulder) / 2
        bones['chest'] = list(chest_pos) + [0, 0, 0, 1]

        if 'hips' in bones:
            spine_pos = lerp(np.array(bones['hips'][:3]), chest_pos)
            bones['spine'] = list(spine_pos) + [0, 0, 0, 1]

        nose = get_landmark(landmarks, 'nose')
        if nose is not None:
            neck_pos = lerp(chest_pos, nose)
            bones['neck'] = list(neck_pos) + [0, 0, 0, 1]
            bones['head'] = list(nose) + [0, 0, 0, 1]

    # Limbs
    bones['shoulder.L'] = list(left_shoulder) + [0, 0, 0, 1] if left_shoulder is not None else [0,0,0,0,0,0,1]
    left_elbow = get_landmark(landmarks, 'left_elbow')
    bones['elbow.L'] = list(left_elbow) + [0, 0, 0, 1] if left_elbow is not None else [0,0,0,0,0,0,1]
    left_wrist = get_landmark(landmarks, 'left_wrist')
    bones['wrist.L'] = list(left_wrist) + [0, 0, 0, 1] if left_wrist is not None else [0,0,0,0,0,0,1]

    bones['shoulder.R'] = list(right_shoulder) + [0, 0, 0, 1] if right_shoulder is not None else [0,0,0,0,0,0,1]
    right_elbow = get_landmark(landmarks, 'right_elbow')
    bones['elbow.R'] = list(right_elbow) + [0, 0, 0, 1] if right_elbow is not None else [0,0,0,0,0,0,1]
    right_wrist = get_landmark(landmarks, 'right_wrist')
    bones['wrist.R'] = list(right_wrist) + [0, 0, 0, 1] if right_wrist is not None else [0,0,0,0,0,0,1]

    bones['upperLeg.L'] = list(left_hip) + [0, 0, 0, 1] if left_hip is not None else [0,0,0,0,0,0,1]
    left_knee = get_landmark(landmarks, 'left_knee')
    bones['knee.L'] = list(left_knee) + [0, 0, 0, 1] if left_knee is not None else [0,0,0,0,0,0,1]
    left_ankle = get_landmark(landmarks, 'left_ankle')
    bones['ankle.L'] = list(left_ankle) + [0, 0, 0, 1] if left_ankle is not None else [0,0,0,0,0,0,1]

    bones['upperLeg.R'] = list(right_hip) + [0, 0, 0, 1] if right_hip is not None else [0,0,0,0,0,0,1]
    right_knee = get_landmark(landmarks, 'right_knee')
    bones['knee.R'] = list(right_knee) + [0, 0, 0, 1] if right_knee is not None else [0,0,0,0,0,0,1]
    right_ankle = get_landmark(landmarks, 'right_ankle')
    bones['ankle.R'] = list(right_ankle) + [0, 0, 0, 1] if right_ankle is not None else [0,0,0,0,0,0,1]

    # Rotations (simple forward kinematics)
    # For now, keep identity quaternions, as full FK is complex
    # TODO: Implement proper bone rotations

    return bones