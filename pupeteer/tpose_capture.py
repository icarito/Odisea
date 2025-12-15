import cv2
import numpy as np
import time
import json
from pathlib import Path
from pose_detector import PoseDetector

def draw_keypoints(img, keypoints, color=(0,255,0)):
    if not keypoints:
        return img
    for idx, lm in enumerate(keypoints):
        x = int(lm['x'] * img.shape[1])
        y = int(lm['y'] * img.shape[0])
        cv2.circle(img, (x, y), 4, color, -1)
        cv2.putText(img, str(idx), (x+5, y-5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1)
    return img

def main():
    tpose_img_path = Path("../tpose_screenshot.png")
    out_json = Path("../tpose_posenet.json")
    cap = cv2.VideoCapture(0)
    # Baja resolución para mejor FPS
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 360)
    detector = PoseDetector()

    # Carga la imagen de referencia y la redimensiona al tamaño del video
    ret, frame = cap.read()
    if not ret:
        print("No se pudo acceder a la cámara.")
        return
    tpose_img = cv2.imread(str(tpose_img_path))
    tpose_img = cv2.resize(tpose_img, (frame.shape[1], frame.shape[0]))
    # Aumenta la opacidad de la imagen de referencia (por ejemplo, 0.5)
    tpose_opacity = 0.5

    countdown = 30
    last_landmarks = None
    start_time = time.time()
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # Flip horizontal (mirror)
        frame = cv2.flip(frame, 1)
        elapsed = int(time.time() - start_time)
        remaining = countdown - elapsed
        if remaining <= 0:
            break
        overlay = cv2.addWeighted(frame, 1.0, tpose_img, tpose_opacity, 0)
        landmarks = detector.process_frame(frame)
        if landmarks:
            last_landmarks = landmarks
            overlay = draw_keypoints(overlay, landmarks)
        cv2.putText(overlay, f"Countdown: {remaining}", (30, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0,0,255), 3)
        cv2.imshow("T-Pose Alignment", overlay)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
    # Guarda los keypoints al final
    if last_landmarks:
        keypoints = {"keypoints": []}
        for idx, lm in enumerate(last_landmarks):
            keypoints["keypoints"].append({
                "part": str(idx),
                "position": {"x": lm["x"] * frame.shape[1], "y": lm["y"] * frame.shape[0]},
                "z": lm["z"],
                "visibility": lm.get("visibility", 1.0)
            })
        with open(out_json, "w") as f:
            json.dump(keypoints, f, indent=2)
        print(f"Keypoints guardados en {out_json}")
    else:
        print("No se detectaron keypoints al final del countdown.")
    cap.release()
    cv2.destroyAllWindows()
    detector.close()

if __name__ == "__main__":
    main()
