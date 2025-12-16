#!/usr/bin/env python3
import argparse
import cv2
import time
import signal
import sys
import os
import json
import numpy as np
from scipy.spatial.transform import Rotation as R

# Import necessary components from the project
from pose_detector import PoseDetector
from udp_sender import UDPSender
from demo import demo_generator
from ascii_renderer import render_ascii_skeleton
from bone_mapper import posenet_to_godot_bones

# --- Global State ---
running = True

def signal_handler(sig, frame):
    """Gracefully handle Ctrl+C."""
    global running
    print("\nSignal received, shutting down...")
    running = False



def main():
    global running

    # --- Argument Parsing ---
    parser = argparse.ArgumentParser(description="Mocap stream sender for Godot")
    parser.add_argument('--port', type=int, default=5555, help='UDP port for Godot')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='UDP host for Godot')
    parser.add_argument('--video', type=str, help='Path to a video file to process instead of webcam')
    parser.add_argument('--demo', action='store_true', help='Use synthetic demo data instead of a live camera')
    parser.add_argument('--ascii', action='store_true', help='Render an ASCII art skeleton in the terminal')
    parser.add_argument('--tpose', action='store_true', help='Send the converted tpose_posenet.json for debugging')
    args = parser.parse_args()

    # --- Initialization ---
    signal.signal(signal.SIGINT, signal_handler)
    
    detector = PoseDetector()
    sender = UDPSender(host=args.host, port=args.port)
    
    try:
        with open('tpose_export.json', 'r') as f:
            tpose_godot = json.load(f)
    except FileNotFoundError:
        print("FATAL: 'tpose_export.json' not found. Please run the Godot project first to generate it.")
        return

    # --- Shared Bone Mapping ---
    # Maps the internal DEF- names from bone_mapper to the names Godot's script expects
    sender_map = {
        "_SKELETON_ROOT_POS": "_SKELETON_ROOT_POS",
        "DEF-hips": "hips", "DEF-chest": "chest", "DEF-spine": "spine", "DEF-neck": "neck",
        "DEF-head": "head", "DEF-shoulderL": "shoulder.L", "DEF-upper_armL": "elbow.L",
        "DEF-forearmL": "wrist.L", "DEF-shoulderR": "shoulder.R", "DEF-upper_armR": "elbow.R",
        "DEF-forearmR": "wrist.R", "DEF-thighL": "upperLeg.L", "DEF-shinL": "knee.L",
        "DEF-footL": "ankle.L", "DEF-thighR": "upperLeg.R", "DEF-shinR": "knee.R", "DEF-footR": "ankle.R"
    }

    # --- T-Pose Debug Mode ---
    if args.tpose:
        print("--- T-POSE DEBUG MODE ---")
        try:
            with open('tpose_posenet.json', 'r') as f:
                posenet_data = json.load(f)
        except FileNotFoundError:
            print("FATAL: 'tpose_posenet.json' not found for --tpose mode.")
            return

        landmarks = [{'x': kp['position']['x'], 'y': kp['position']['y'], 'z': kp.get('z', 0)} for kp in posenet_data.get('keypoints', [])]
        if not landmarks:
            print("Error: No keypoints found in tpose_posenet.json")
            return

        print("Continuously sending converted T-Pose...")
        while running:
            bones = posenet_to_godot_bones(landmarks, tpose_godot)

            corrected_bones = bones
            
            final_packet = {}
            for def_name, data in corrected_bones.items():
                sender_name = sender_map.get(def_name)
                if sender_name:
                    quat_xyzw = data[3:]
                    quat_wxyz = [quat_xyzw[3], quat_xyzw[0], quat_xyzw[1], quat_xyzw[2]] # W,X,Y,Z
                    final_packet[sender_name] = data[:3] + quat_wxyz
            
            if final_packet:
                sender.send_pose({"bones": final_packet})

            if args.ascii:
                xs = [lm['x'] for lm in landmarks]; ys = [lm['y'] for lm in landmarks]
                max_x, max_y = (max(xs) if xs else 1, max(ys) if ys else 1)
                norm_landmarks = [{'x': lm['x']/max_x, 'y': lm['y']/max_y, 'z': lm['z']} for lm in landmarks]
                shape_hint = (int(max_y), int(max_x), 3)
                ascii_art = render_ascii_skeleton(norm_landmarks, shape_hint)
                os.system('clear'); print(ascii_art)
            time.sleep(1/30)
        return

    # --- Main Loop (Live/Demo) ---
    print("Starting pose detection. Press Ctrl+C to stop.")
    
    source_iterator = None
    if args.demo:
        source_iterator = demo_generator()
    else:
        cap = cv2.VideoCapture(args.video if args.video else 0)
        if not cap.isOpened():
            print(f"Error: Could not open video source '{args.video or 0}'")
            return
        def video_generator(capture):
            while running:
                ret, frame = capture.read()
                if not ret: break
                yield frame
            capture.release()
        source_iterator = video_generator(cap)


    save_counter = 0
    for frame in source_iterator:
        if not running:
            break

        landmarks = None
        # Demo mode yields landmarks directly, video yields frames
        if isinstance(frame, np.ndarray):
            if not args.video:
                frame = cv2.flip(frame, 1) # Mirror webcam
            landmarks = detector.process_frame(frame)
        else: # Demo data
            landmarks = frame

        if landmarks:
            bones = posenet_to_godot_bones(landmarks, tpose_godot)
            corrected_bones = bones
            final_packet = {}
            for def_name, data in corrected_bones.items():
                sender_name = sender_map.get(def_name)
                if sender_name:
                    quat_xyzw = data[3:]
                    quat_wxyz = [quat_xyzw[3], quat_xyzw[0], quat_xyzw[1], quat_xyzw[2]] # W,X,Y,Z
                    final_packet[sender_name] = data[:3] + quat_wxyz

            if final_packet:
                print(f"Sending bones: {list(final_packet.keys())}")
                sender.send_pose({"bones": final_packet})

                # --- Export result000.json (auto-increment) ---
                try:
                    export_dict = {def_name: data for def_name, data in corrected_bones.items()}
                    json_path = f"result{save_counter:03d}.json"
                    with open(json_path, "w") as f:
                        json.dump(export_dict, f, indent=2)
                    save_counter = (save_counter + 1) % 1000  # Rollover after 999
                except Exception as e:
                    print(f"[POSE_EXPORT] Error saving {json_path}: {e}")

            if args.ascii:
                shape = frame.shape if isinstance(frame, np.ndarray) else (480, 640, 3)
                ascii_art = render_ascii_skeleton(landmarks, shape)
                os.system('clear'); print(ascii_art)

        time.sleep(1/30)

    # --- Shutdown ---
    detector.close()
    sender.close()
    print("Shutdown complete.")

if __name__ == '__main__':
    main()
