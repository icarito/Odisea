# Bone names for Godot Mixamo skeleton
BONE_NAMES = [
    "hips",
    "spine",
    "chest",
    "neck",
    "head",
    "shoulder.L",
    "elbow.L",
    "wrist.L",
    "shoulder.R",
    "elbow.R",
    "wrist.R",
    "upperLeg.L",
    "knee.L",
    "ankle.L",
    "upperLeg.R",
    "knee.R",
    "ankle.R"
]

# MediaPipe landmark indices (mirrored for webcam)
LANDMARK_INDICES = {
    'nose': 0,
    'left_shoulder': 12,
    'right_shoulder': 11,
    'left_elbow': 14,
    'right_elbow': 13,
    'left_wrist': 16,
    'right_wrist': 15,
    'left_hip': 24,
    'right_hip': 23,
    'left_knee': 26,
    'right_knee': 25,
    'left_ankle': 28,
    'right_ankle': 27,
}

# Calibration
DEFAULT_HEIGHT = 1.78  # meters