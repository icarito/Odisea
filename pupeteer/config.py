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
    # --- Computed landmarks ---
    'hips': 33, 
    'chest': 34,
    'neck': 35,
}

# Defines the skeleton structure (parent -> child)
# This order is important for hierarchical processing (parents must come before children)
BONE_HIERARCHY = [
    "DEF-hips",
    "DEF-thighL",
    "DEF-shinL",
    "DEF-footL",
    "DEF-thighR",
    "DEF-shinR",
    "DEF-footR",
    "DEF-spine", # Simplified spine
    "DEF-chest",
    "DEF-neck",
    "DEF-head",
    "DEF-shoulderL",
    "DEF-upper_armL",
    "DEF-forearmL",
    "DEF-handL",
    "DEF-shoulderR",
    "DEF-upper_armR",
    "DEF-forearmR",
    "DEF-handR",
]

BONE_PARENTS = {
    "DEF-hips": None, # Root of the hierarchy
    "DEF-spine": "DEF-hips",
    "DEF-chest": "DEF-spine",
    "DEF-neck": "DEF-chest",
    "DEF-head": "DEF-neck",
    
    # Left Arm
    "DEF-shoulderL": "DEF-chest",
    "DEF-upper_armL": "DEF-shoulderL",
    "DEF-forearmL": "DEF-upper_armL",
    "DEF-handL": "DEF-forearmL",

    # Right Arm
    "DEF-shoulderR": "DEF-chest",
    "DEF-upper_armR": "DEF-shoulderR",
    "DEF-forearmR": "DEF-upper_armR",
    "DEF-handR": "DEF-forearmR",

    # Left Leg
    "DEF-thighL": "DEF-hips",
    "DEF-shinL": "DEF-thighL",
    "DEF-footL": "DEF-shinL",

    # Right Leg
    "DEF-thighR": "DEF-hips",
    "DEF-shinR": "DEF-thighR",
    "DEF-footR": "DEF-shinR",
}

# Maps Godot bone names to the MediaPipe landmarks used to calculate their position.
BONE_LANDMARKS = {
    # Torso
    "DEF-hips": ['left_hip', 'right_hip'],
    "DEF-spine": ['left_shoulder', 'right_shoulder'], # Simplified: spine is chest
    "DEF-chest": ['left_shoulder', 'right_shoulder'],
    "DEF-neck": ['nose', 'chest'], # Midpoint
    "DEF-head": ['nose'],

    # Left Arm
    "DEF-shoulderL": ['left_shoulder'],
    "DEF-upper_armL": ['left_elbow'],
    "DEF-forearmL": ['left_wrist'],
    "DEF-handL": ['left_wrist'], # Using wrist for hand position
    
    # Right Arm
    "DEF-shoulderR": ['right_shoulder'],
    "DEF-upper_armR": ['right_elbow'],
    "DEF-forearmR": ['right_wrist'],
    "DEF-handR": ['right_wrist'],

    # Left Leg
    "DEF-thighL": ['left_knee'],
    "DEF-shinL": ['left_ankle'],
    "DEF-footL": ['left_ankle'], 

    # Right Leg
    "DEF-thighR": ['right_knee'],
    "DEF-shinR": ['right_ankle'],
    "DEF-footR": ['right_ankle'],
}

# Calibration
DEFAULT_HEIGHT = 1.78  # meters