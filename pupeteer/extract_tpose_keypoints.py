import json
import sys
from pathlib import Path
import cv2
import numpy as np
from pose_detector import PoseDetector

def main():
    img_path = Path("../tpose_screenshot.png")
    out_json = Path("../tpose_posenet.json")
    out_vis = Path("../tpose_posenet_vis.png")

    if not img_path.exists():
        print(f"No se encontró la imagen: {img_path}")
        sys.exit(1)

    img = cv2.imread(str(img_path))
    if img is None:
        print(f"No se pudo cargar la imagen: {img_path}")
        sys.exit(1)

    # Extrae keypoints con PoseDetector
    detector = PoseDetector()
    landmarks = detector.process_frame(img)
    detector.close()
    # Formatea los keypoints en formato similar a PoseNet
    keypoints = {"keypoints": []}
    if landmarks:
        for idx, lm in enumerate(landmarks):
            keypoints["keypoints"].append({
                "part": str(idx),
                "position": {"x": lm["x"] * img.shape[1], "y": lm["y"] * img.shape[0]},
                "z": lm["z"],
                "visibility": lm.get("visibility", 1.0)
            })

    # Guarda los keypoints en JSON
    with open(out_json, "w") as f:
        json.dump(keypoints, f, indent=2)
    print(f"Keypoints guardados en {out_json}")

    # Visualización opcional
    for kp in keypoints.get("keypoints", []):
        x, y = int(kp["position"]["x"]), int(kp["position"]["y"])
        cv2.circle(img, (x, y), 4, (0, 255, 0), -1)
        cv2.putText(img, kp["part"], (x+5, y-5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 0, 0), 1)
    cv2.imwrite(str(out_vis), img)
    print(f"Visualización guardada en {out_vis}")

if __name__ == "__main__":
    main()
