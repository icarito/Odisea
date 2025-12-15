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