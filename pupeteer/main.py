#!/usr/bin/env python3
import argparse
import cv2
import time
import threading
import signal
import sys
import os
from pose_detector import PoseDetector
from udp_sender import UDPSender
from demo import demo_generator
from config import DEFAULT_HEIGHT
from ascii_renderer import render_ascii_skeleton

running = True
paused = False
calibrated_height = DEFAULT_HEIGHT

def signal_handler(sig, frame):
    global running
    running = False

def keyboard_listener():
    global paused, calibrated_height, running
    while running:
        try:
            key = input().strip().lower()
            if key == 'q':
                running = False
            elif key == ' ':
                paused = not paused
                print("Paused" if paused else "Resumed")
            elif key == 'c':
                # Simple height calibration (placeholder)
                calibrated_height = 1.75  # Example
                print(f"Height calibrated to {calibrated_height}m")
        except EOFError:
            break

def main():
    global running, paused, calibrated_height

    parser = argparse.ArgumentParser(description="Kohai Godot LiveLink")
    parser.add_argument('--port', type=int, default=5555, help='UDP port for Godot')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='UDP host for Godot')
    parser.add_argument('--video', type=str, help='Video file path')
    parser.add_argument('--demo', action='store_true', help='Use synthetic demo')
    parser.add_argument('--calib', action='store_true', help='Auto-calibrate height')
    parser.add_argument('--ascii', action='store_true', help='Render ASCII skeleton')
    parser.add_argument('--quat', action='store_true', help='Export/send only position+quaternion for Godot')
    parser.add_argument('--tpose', action='store_true', help='Envia la T-Pose Godot convertida para depuración')
    args = parser.parse_args()

    signal.signal(signal.SIGINT, signal_handler)

    detector = PoseDetector()
    sender = UDPSender(host=args.host, port=args.port)

    if args.calib:
        calibrated_height = 1.80  # Placeholder

    # Start keyboard listener
    threading.Thread(target=keyboard_listener, daemon=True).start()


    def send_pose_with_quat(pose, shape_hint=None):
        from bone_mapper import posenet_to_godot_bones
        import json
        import numpy as np
        # Cargar tpose_export.json una vez (puedes optimizar cacheando si es necesario)
        with open('tpose_export.json','r') as f:
            tpose_godot = json.load(f)
        bones = posenet_to_godot_bones(pose, tpose_godot)
        
        # Normalizar quaternions antes de enviar
        for bone_name, bone_data in bones.items():
            if len(bone_data) == 7:
                pos = bone_data[:3]
                quat_raw = np.array(bone_data[3:])
                norm = np.linalg.norm(quat_raw)
                if norm > 1e-6:
                    quat_norm = quat_raw / norm
                    bones[bone_name] = list(pos) + list(quat_norm)
                else: # Quat inválido, enviar identidad
                    bones[bone_name] = list(pos) + [0, 0, 0, 1]

        # Verification print as requested
        print("ENVIANDO HUESOS:", sorted(bones.keys()))
        
        sender.send_pose({"bones": bones})
        if args.ascii and shape_hint is not None:
            ascii_art = render_ascii_skeleton(pose, shape_hint)
            os.system('clear')
            print(ascii_art)

    if not args.quat:
        print("WARN: The --quat flag is now implicitly enabled. The old mode is no longer supported.")

    send_pose = send_pose_with_quat

    # --- MODO TEST T-POSE ---
    if args.tpose:
        import json
        from bone_mapper import posenet_to_godot_bones
        import numpy as np
        # Cargar tpose_posenet.json
        with open('tpose_posenet.json','r') as f:
            data = json.load(f)
        
        # The new bone_mapper expects un-normalized coordinates, similar to what MediaPipe
        # provides before normalization. The tpose_posenet.json file contains pixel coordinates.
        # We can use them directly.
        if 'keypoints' in data:
            landmarks = []
            for kp in data['keypoints']:
                # The bone mapper expects a list of dicts with 'x', 'y', 'z'
                landmarks.append({
                    'x': kp['position']['x'],
                    'y': kp['position']['y'],
                    'z': kp.get('z', 0) # Z might not be present, default to 0
                })
        else:
            print('No se encontraron keypoints en tpose_posenet.json')
            return
            
        # Cargar tpose_export.json para la referencia de huesos
        with open('tpose_export.json','r') as f:
            tpose_godot = json.load(f)
            
        print("--- MODO TEST T-POSE: Enviando tpose_posenet.json convertido a Godot (feed continuo) ---")
        while running:
            if paused:
                time.sleep(0.1)
                continue

            bones = posenet_to_godot_bones(landmarks, tpose_godot)

            # Normalizar quaternions antes de enviar
            for bone_name, bone_data in bones.items():
                if len(bone_data) == 7:
                    pos = bone_data[:3]
                    quat_raw = np.array(bone_data[3:])
                    norm = np.linalg.norm(quat_raw)
                    if norm > 1e-6:
                        quat_norm = quat_raw / norm
                        bones[bone_name] = list(pos) + list(quat_norm)
                    else: # Quat inválido, enviar identidad
                        bones[bone_name] = list(pos) + [0, 0, 0, 1]

            sender.send_pose({"bones": bones})
            if args.ascii:
                # The ascii renderer expects normalized coordinates (0-1).
                # The bone mapper now expects un-normalized coordinates.
                # So, we create a normalized copy just for rendering.
                xs = [lm['x'] for lm in landmarks]
                ys = [lm['y'] for lm in landmarks]
                max_x = max(xs) if xs else 1
                max_y = max(ys) if ys else 1
                
                normalized_landmarks = []
                for lm in landmarks:
                    normalized_landmarks.append({
                        'x': lm['x'] / max_x,
                        'y': lm['y'] / max_y,
                        'z': lm.get('z', 0), # z is not used by renderer but good to keep
                        'visibility': lm.get('visibility', 1.0)
                    })

                shape_hint = (int(max_y), int(max_x), 3)
                ascii_art = render_ascii_skeleton(normalized_landmarks, shape_hint)
                os.system('clear')
                print(ascii_art)
            time.sleep(1/60)
            
        detector.close()
        sender.close()
        print("Shutdown complete (T-Pose test)")
        return

    if args.demo:
        print("Starting demo mode...")
        for pose in demo_generator():
            if not running:
                break
            if paused:
                time.sleep(0.1)
                continue
            send_pose(pose, (480, 640, 3))
    else:
        cap = cv2.VideoCapture(args.video if args.video else 0)
        if not cap.isOpened():
            print("Error opening video source")
            return

        print("Starting pose detection...")
        while running:
            if paused:
                time.sleep(0.1)
                continue

            ret, frame = cap.read()
            if not ret:
                break

            frame = cv2.flip(frame, 1)  # Mirror for webcam
            landmarks = detector.process_frame(frame)

            if landmarks:
                send_pose(landmarks, frame.shape)

            time.sleep(1/60)  # 60Hz

        cap.release()

    detector.close()
    sender.close()
    print("Shutdown complete")

if __name__ == '__main__':
    main()