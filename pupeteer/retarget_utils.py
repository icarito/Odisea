import numpy as np
from scipy.spatial.transform import Rotation as R

def quat_from_two_vectors(v_from, v_to):
    """
    Computes a quaternion that rotates vector v_from to vector v_to.
    Handles the case where vectors are nearly opposite.
    """
    v_from = v_from / np.linalg.norm(v_from)
    v_to = v_to / np.linalg.norm(v_to)
    
    cross_prod = np.cross(v_from, v_to)
    dot_prod = np.dot(v_from, v_to)

    if np.isclose(dot_prod, -1.0):
        # Vectors are opposite. Find an arbitrary perpendicular axis.
        axis = np.cross(v_from, np.array([1.0, 0.0, 0.0]))
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(v_from, np.array([0.0, 1.0, 0.0]))
        axis = axis / np.linalg.norm(axis)
        return R.from_rotvec(np.pi * axis).as_quat()

    # Use scipy's robust method for all other cases
    rot, _ = R.align_vectors([v_to], [v_from])
    return rot.as_quat()

def limb_quat(p1, p2, ref_vec=np.array([0, 1, 0])):
    """
    Calculates the quaternion to rotate a reference vector to align with the vector from p1 to p2.
    """
    limb_vec = p2 - p1
    if np.linalg.norm(limb_vec) < 1e-6:
        return np.array([0, 0, 0, 1]) # Return identity if the points are too close
    return quat_from_two_vectors(ref_vec, limb_vec)

def local_quat(global_quat, parent_global_quat):
    """
    Calculates the local rotation quaternion from a global and a parent's global quaternion.
    """
    qg = R.from_quat(global_quat)
    qp = R.from_quat(parent_global_quat)
    ql = qp.inv() * qg
    return ql.as_quat()
