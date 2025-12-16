
import socket
import json
import time
from scipy.spatial.transform import Rotation as R
import numpy as np

# Assuming UPose and other necessary modules are available
# from pose_detector import UPoseTracker # Placeholder for the actual class
# For demonstration, we'll mock the necessary classes and data.

class MockUPoseTracker:
    """
    A mock class to simulate the behavior of UPoseTracker for testing purposes.
    It returns predefined rotations and landmark positions.
    """
    LEFT_HIP = 23
    RIGHT_HIP = 24

    def __init__(self):
        # Simulate some initial rotation
        self.t = 0

    def getPelvisRotation(self):
        # Simulate a simple rotation around Y axis over time
        rotation = R.from_euler('y', self.t, degrees=True)
        self.t = (self.t + 1) % 360
        return {"world": rotation, "local": rotation}

    def get_rotation(self, bone_name):
        # Return a fixed identity rotation for other bones for simplicity
        return {"local": R.identity()}

    def getLandmark(self, landmark_index):
        # Return a static landmark position
        if landmark_index == self.LEFT_HIP:
            return np.array([-0.1, -0.8, 0])
        if landmark_index == self.RIGHT_HIP:
            return np.array([0.1, -0.8, 0])
        return np.array([0, 0, 0])

# --- Critical T-Pose Data from Godot ---

# T-Pose of Godot (Formato: [X, Y, Z, W] para scipy.from_quat())
# This is the LOCAL rest rotation of the DEF-hips bone in the Godot model.
HIP_TPOSE_SCIPY = R.from_quat([0, 0, 0.612503, 0.790468])

# Bone mapping from UPose convention to Godot skeleton
BONE_MAPPING = {
    "pelvis": "DEF-hips",
    "torso": "DEF-spine001",
    "left_shoulder": "DEF-shoulderL",
    "right_shoulder": "DEF-shoulderR",
    "left_elbow": "DEF-forearmL",
    "right_elbow": "DEF-forearmR",
    "left_hip": "DEF-thighL",
    "right_hip": "DEF-thighR",
    "left_knee": "DEF-shinL",
    "right_knee": "DEF-shinR",
}

# Placeholder for Godot's T-Pose bone positions.
# This should be filled with the actual local positions of the bones in the Godot skeleton.
GODOT_TPOSE_POS = {
    "DEF-hips": [0, 0, 0],
    "DEF-spine001": [0, 0.1, 0],
    "DEF-shoulderL": [0.1, 0.1, 0],
    "DEF-shoulderR": [-0.1, 0.1, 0],
    "DEF-forearmL": [0.2, 0, 0],
    "DEF-forearmR": [-0.2, 0, 0],
    "DEF-thighL": [0.1, -0.2, 0],
    "DEF-thighR": [-0.1, -0.2, 0],
    "DEF-shinL": [0, -0.4, 0],
    "DEF-shinR": [0, -0.4, 0],
}


# Global correction rotation (180 degrees around the Y-axis)
R_WORLD_CORRECTION_180 = R.from_euler('y', 180, degrees=True)

def send_frame(sock, pose_tracker, host, port):
    """
    Calculates and sends a single frame of pose data.
    """
    final_bones = {}

    # --- Retargeting and Calibration for DEF-hips ---
    
    # 1. Get the world rotation of the pelvis from UPose
    pelvis_rot_upose = pose_tracker.getPelvisRotation()
    Q_global_upose = pelvis_rot_upose["world"]

    # 2. Apply Global Axis Correction (Aligns Front/Back)
    Q_global_captura_aligned = R_WORLD_CORRECTION_180 * Q_global_upose

    # 3. Apply T-Pose Retargeting (Eliminates twisting)
    # Formula: Q_Local_Final = Q_Global_Capture_Aligned * Q_Tpose_Godot_Inverse
    Q_local_hips_final = Q_global_captura_aligned * HIP_TPOSE_SCIPY.inv()

    # 4. Get Global Hip Position for _SKELETON_ROOT_POS
    hips_lm_l = pose_tracker.getLandmark(pose_tracker.LEFT_HIP)
    hips_lm_r = pose_tracker.getLandmark(pose_tracker.RIGHT_HIP)
    hips_lm = hips_lm_l + (hips_lm_r - hips_lm_l) / 2
    
    # Apply Z-inversion for Godot's coordinate system
    final_root_pos = [hips_lm[0], hips_lm[1], -hips_lm[2]]

    # 5. Format for Sending DEF-hips
    # Scipy as_quat() is (X, Y, Z, W). JSON needs (W, X, Y, Z).
    x, y, z, w = Q_local_hips_final.as_quat()
    hips_quat_json = [w, x, y, z]

    # Use the static local position for the hips bone itself
    final_bones["DEF-hips"] = GODOT_TPOSE_POS["DEF-hips"] + hips_quat_json
    
    # Set the skeleton root position (translation only, rotation is identity)
    final_bones["_SKELETON_ROOT_POS"] = final_root_pos + [1, 0, 0, 0] # W=1 for identity quat

    # --- Logic for Other Bones ---
    for bone_name, godot_bone in BONE_MAPPING.items():
        if bone_name != "pelvis":
            Q_local_upose = pose_tracker.get_rotation(bone_name)["local"]
            x, y, z, w = Q_local_upose.as_quat()
            
            # Get static T-pose position and add the calculated rotation
            if godot_bone in GODOT_TPOSE_POS:
                final_bones[godot_bone] = list(GODOT_TPOSE_POS[godot_bone]) + [w, x, y, z]

    # --- Send Data ---
    json_data = json.dumps(final_bones)
    sock.sendto(json_data.encode('utf-8'), (host, port))
    print(f"Sent: {json_data}")


def main():
    """
    Main loop to capture and send pose data.
    """
    # In a real scenario, initialize the actual UPoseTracker
    # pose_tracker = UPoseTracker()
    pose_tracker = MockUPoseTracker() # Using mock for demonstration

    host = "127.0.0.1"
    port = 4242

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        print(f"Sending Mocap data to {host}:{port}...")
        while True:
            try:
                send_frame(sock, pose_tracker, host, port)
                time.sleep(0.016) # Limit to ~60 FPS
            except KeyboardInterrupt:
                print("Stopping sender.")
                break
            except Exception as e:
                print(f"An error occurred: {e}")
                break

if __name__ == "__main__":
    main()
