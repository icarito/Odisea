import cv2
import mediapipe as mp
import numpy as np
from collections import deque

class LandmarkSmoother:
    def __init__(self, alpha=0.25, visibility_threshold=0.5, velocity_threshold=0.05):
        self.alpha = alpha
        self.visibility_threshold = visibility_threshold
        self.velocity_threshold = velocity_threshold
        self._smoothed = None
        self._prev_raw = None

    def reset(self):
        self._smoothed = None
        self._prev_raw = None

    def smooth(self, landmarks):
        if landmarks is None:
            return None
        if self._smoothed is None:
            self._smoothed = [dict(lm) for lm in landmarks]
            self._prev_raw = [dict(lm) for lm in landmarks]
            return self._smoothed

        for i, lm in enumerate(landmarks):
            if i < len(self._smoothed) and i < len(self._prev_raw):
                vis = lm.get('visibility', 1.0)
                dx = lm['x'] - self._prev_raw[i]['x']
                dy = lm['y'] - self._prev_raw[i]['y']
                velocity = (dx*dx + dy*dy) ** 0.5

                base_alpha = self.alpha
                if vis < self.visibility_threshold:
                    base_alpha *= 0.5
                if velocity < self.velocity_threshold:
                    base_alpha *= 0.6
                effective_alpha = max(base_alpha, 0.05)

                self._smoothed[i]['x'] = effective_alpha * lm['x'] + (1 - effective_alpha) * self._smoothed[i]['x']
                self._smoothed[i]['y'] = effective_alpha * lm['y'] + (1 - effective_alpha) * self._smoothed[i]['y']
                self._smoothed[i]['z'] = effective_alpha * lm['z'] + (1 - effective_alpha) * self._smoothed[i]['z']
                self._smoothed[i]['visibility'] = lm['visibility']

                self._prev_raw[i] = dict(lm)
        return self._smoothed

class PoseDetector:
    def __init__(self):
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            static_image_mode=False,
            model_complexity=0,
            enable_segmentation=False,
            min_detection_confidence=0.2,
            min_tracking_confidence=0.2,
            smooth_landmarks=True
        )
        self.smoother = LandmarkSmoother()

    def process_frame(self, frame):
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.pose.process(rgb_frame)

        if results.pose_landmarks:
            landmarks = []
            for landmark in results.pose_landmarks.landmark:
                landmarks.append({
                    'x': landmark.x,
                    'y': landmark.y,
                    'z': landmark.z,
                    'visibility': landmark.visibility
                })
            smoothed = self.smoother.smooth(landmarks)
            return smoothed
        else:
            return None

    def close(self):
        self.pose.close()