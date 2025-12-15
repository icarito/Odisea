import time
import math

def generate_synthetic_pose(t):
    # Simple T-pose animation
    angle = math.sin(t * 2 * math.pi / 2) * 0.1  # Slight sway

    # Synthetic landmarks (simplified)
    landmarks = [
        {'x': 0.5, 'y': 0.1, 'z': 0.0, 'visibility': 1.0},  # nose
        {'x': 0.4, 'y': 0.2, 'z': 0.0, 'visibility': 1.0},  # left_shoulder
        {'x': 0.6, 'y': 0.2, 'z': 0.0, 'visibility': 1.0},  # right_shoulder
        {'x': 0.3 + angle, 'y': 0.4, 'z': 0.0, 'visibility': 1.0},  # left_elbow
        {'x': 0.7 - angle, 'y': 0.4, 'z': 0.0, 'visibility': 1.0},  # right_elbow
        {'x': 0.2, 'y': 0.6, 'z': 0.0, 'visibility': 1.0},  # left_wrist
        {'x': 0.8, 'y': 0.6, 'z': 0.0, 'visibility': 1.0},  # right_wrist
        {'x': 0.45, 'y': 0.5, 'z': 0.0, 'visibility': 1.0},  # left_hip
        {'x': 0.55, 'y': 0.5, 'z': 0.0, 'visibility': 1.0},  # right_hip
        {'x': 0.4, 'y': 0.8, 'z': 0.0, 'visibility': 1.0},  # left_knee
        {'x': 0.6, 'y': 0.8, 'z': 0.0, 'visibility': 1.0},  # right_knee
        {'x': 0.4, 'y': 1.0, 'z': 0.0, 'visibility': 1.0},  # left_ankle
        {'x': 0.6, 'y': 1.0, 'z': 0.0, 'visibility': 1.0},  # right_ankle
    ]
    return landmarks

def demo_generator():
    start_time = time.time()
    while True:
        t = time.time() - start_time
        yield generate_synthetic_pose(t)
        time.sleep(1/60)  # 60Hz