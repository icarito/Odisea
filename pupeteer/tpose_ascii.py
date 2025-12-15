import json
import sys
from ascii_renderer import render_ascii_skeleton

def main():
    if len(sys.argv) < 2:
        print("Uso: python tpose_ascii.py tpose_posenet.json")
        return
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    # Detectar formato: PoseNet keypoints
    if 'keypoints' in data:
        # Convertir a lista de dicts tipo pose_detector
        keypoints = data['keypoints']
        landmarks = []
        for kp in keypoints:
            x = kp['position']['x']
            y = kp['position']['y']
            z = kp.get('z', 0)
            landmarks.append({'x': x, 'y': y, 'z': z, 'visibility': kp.get('visibility', 1.0)})
        ascii_art = render_ascii_skeleton(landmarks, (480, 640, 3))
        print(ascii_art)
    else:
        print("Formato no reconocido para renderizado ASCII.")

if __name__ == "__main__":
    main()
