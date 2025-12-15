import numpy as np
from scipy.spatial.transform import Rotation as R

def quat_from_two_vectors(v_from, v_to):
    v_from = v_from / np.linalg.norm(v_from)
    v_to = v_to / np.linalg.norm(v_to)
    rot, _ = R.align_vectors([v_to], [v_from])
    return rot.as_quat()  # [x, y, z, w]

def local_quat(global_quat, parent_global_quat):
    qg = R.from_quat(global_quat)
    qp = R.from_quat(parent_global_quat)
    ql = qp.inv() * qg
    return ql.as_quat()
