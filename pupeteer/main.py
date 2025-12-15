#!/usr/bin/env python3
import argparse
import cv2
import time
import threading
import signal
import sys
import os
from pose_detector import PoseDetector
from bone_mapper import map_pose_to_bones
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
    args = parser.parse_args()

    signal.signal(signal.SIGINT, signal_handler)

    detector = PoseDetector()
    sender = UDPSender(host=args.host, port=args.port)

    if args.calib:
        calibrated_height = 1.80  # Placeholder

    # Start keyboard listener
    threading.Thread(target=keyboard_listener, daemon=True).start()

    if args.demo:
        print("Starting demo mode...")
        for pose in demo_generator():
            if not running:
                break
            if paused:
                time.sleep(0.1)
                continue
            bones = map_pose_to_bones(pose, calibrated_height)
            pose_data = {
                "t": time.time(),
                "h": calibrated_height,
                "bones": bones
            }
            sender.send_pose(pose_data)
            if args.ascii:
                ascii_art = render_ascii_skeleton(pose, (480, 640, 3))
                os.system('clear')
                print(ascii_art)
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
                bones = map_pose_to_bones(landmarks, calibrated_height)
                pose_data = {
                    "t": time.time(),
                    "h": calibrated_height,
                    "bones": bones
                }
                sender.send_pose(pose_data)
                if args.ascii:
                    ascii_art = render_ascii_skeleton(landmarks, frame.shape)
                    os.system('clear')
                    print(ascii_art)

            time.sleep(1/60)  # 60Hz

        cap.release()

    detector.close()
    sender.close()
    print("Shutdown complete")

if __name__ == '__main__':
    main()