import sys
import os

def check_recorder():
    with open("core_v2/telemetry/HotzoneRecorder.gd", "r") as f:
        content = f.read()

    checks = {
        "Buffer size 600": "var hotzone_buffer_frames := 600",
        "Ambient enabled var": "var _ambient_enabled := true",
        "Manual recording var": "var _manual_recording := false",
        "Manual input action": 'InputMap.has_action("hotzone_manual_capture")',
        "Continuous storage": "_store_frame(input, dt, fps, now, pos, player)",
        "No reset in auto": "# We no longer reset the ring buffer here"
    }

    for name, snippet in checks.items():
        if snippet in content:
            print(f"[OK] {name}")
        else:
            print(f"[FAIL] {name} - snippet not found: {snippet}")

def check_central():
    with open("odisea_central.py", "r") as f:
        content = f.read()

    checks = {
        "Alert metadata scene": '"scene": scene',
        "Alert metadata duration": '"capture_duration": capture_duration',
        "Alert metadata frames": '"frame_count": capture_frames'
    }

    for name, snippet in checks.items():
        if snippet in content:
            print(f"[OK] {name}")
        else:
            print(f"[FAIL] {name}")

check_recorder()
check_central()
