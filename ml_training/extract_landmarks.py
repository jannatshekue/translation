"""Extracts hand landmarks from a labeled image dataset using MediaPipe
(offline, free, runs on CPU) and writes them in the exact JSON schema the
rest of this pipeline expects — the same schema generate_dummy_data.py
produces and the app's Custom Sign Creation screen records on-device:

    [{"label": "...", "frames": [[{"type", "x", "y", "z", "visibility"}, ...21...]]}, ...]

Each image becomes a single-frame "sample" (frames list of length 1) since
these are static photos, not recorded sequences.

Supports two dataset layouts:
  1. Folder-per-class (default): <input_dir>/<label>/*.jpg
     e.g. the Kaggle ASL Alphabet dataset once pointed at the folder that
     directly contains the A/, B/, C/, ... subfolders.
  2. CSV-labeled, flat image folder: pass --csv with columns for an image
     id/filename and a label, plus --images-dir containing the files. Some
     Kaggle-mirrored competition datasets (including the KSL one) ship this
     way instead of folder-per-class.

Landmark ordering: MediaPipe's HandLandmarker returns 21 landmarks in a
fixed index order (WRIST, THUMB_CMC, THUMB_MCP, ...) that lines up
positionally with LANDMARK_TYPES below, which mirrors the Dart-side
HandLandmarkType enum (lib/core/services/hand_pose_matcher.dart). Coordinates
are converted from MediaPipe's normalized [0,1] range to pixel space (x *
width, y * height) to match what the Dart side actually records — using the
normalized values directly would skew x/y relative scale on non-square
images.

Requires the hand_landmarker.task model file (free, no account needed):
    curl -L -o models_cache/hand_landmarker.task \\
      https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
This uses the modern MediaPipe Tasks API (mediapipe.tasks) — the older
mediapipe.solutions.hands API used by many older tutorials no longer exists
in current mediapipe releases (1.0.1 at time of writing).
"""

import argparse
import csv
import json
import sys
from pathlib import Path

import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

LANDMARK_TYPES = [
    "wrist",
    "thumbCMC", "thumbMCP", "thumbIP", "thumbTip",
    "indexFingerMCP", "indexFingerPIP", "indexFingerDIP", "indexFingerTip",
    "middleFingerMCP", "middleFingerPIP", "middleFingerDIP", "middleFingerTip",
    "ringFingerMCP", "ringFingerPIP", "ringFingerDIP", "ringFingerTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip",
]

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}


def make_landmarker(model_path: Path) -> vision.HandLandmarker:
    if not model_path.exists():
        sys.exit(
            f"Model file not found at {model_path}. Download it first:\n"
            "  curl -L -o models_cache/hand_landmarker.task "
            "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
            "hand_landmarker/float16/latest/hand_landmarker.task"
        )
    options = vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        num_hands=1,
        min_hand_detection_confidence=0.5,
        running_mode=vision.RunningMode.IMAGE,
    )
    return vision.HandLandmarker.create_from_options(options)


def landmarks_from_image(landmarker: vision.HandLandmarker, image_path: Path) -> list[dict] | None:
    try:
        mp_image = mp.Image.create_from_file(str(image_path))
    except RuntimeError:
        return None
    result = landmarker.detect(mp_image)
    if not result.hand_landmarks:
        return None

    hand = result.hand_landmarks[0]
    width, height = mp_image.width, mp_image.height
    frame = []
    for landmark_type, point in zip(LANDMARK_TYPES, hand):
        frame.append({
            "type": landmark_type,
            "x": point.x * width,
            "y": point.y * height,
            "z": point.z * width,
            "visibility": 1.0,
        })
    return frame


def collect_folder_per_class(input_dir: Path, max_per_class: int) -> list[tuple[str, Path]]:
    pairs = []
    for label_dir in sorted(p for p in input_dir.iterdir() if p.is_dir()):
        images = sorted(
            p for p in label_dir.iterdir() if p.suffix.lower() in IMAGE_EXTENSIONS
        )[:max_per_class]
        pairs.extend((label_dir.name, image_path) for image_path in images)
    return pairs


def collect_from_csv(
    csv_path: Path, images_dir: Path, id_col: str, label_col: str, max_per_class: int
) -> list[tuple[str, Path]]:
    counts: dict[str, int] = {}
    pairs = []
    with csv_path.open(newline="") as f:
        for row in csv.DictReader(f):
            label = row[label_col]
            if counts.get(label, 0) >= max_per_class:
                continue
            image_id = row[id_col]
            candidates = [images_dir / image_id]
            if Path(image_id).suffix == "":
                candidates += [images_dir / f"{image_id}{ext}" for ext in IMAGE_EXTENSIONS]
            image_path = next((c for c in candidates if c.exists()), None)
            if image_path is None:
                continue
            pairs.append((label, image_path))
            counts[label] = counts.get(label, 0) + 1
    return pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input-dir", required=True, type=Path,
                         help="Folder-per-class root, or (with --csv) the flat images folder.")
    parser.add_argument("--output", required=True, type=Path, help="Output dataset JSON path.")
    parser.add_argument("--max-per-class", type=int, default=400,
                         help="Cap samples per class so CPU-only training stays fast (default: 400).")
    parser.add_argument("--csv", type=Path, default=None,
                         help="CSV file with an id column and a label column, for flat/CSV-labeled datasets.")
    parser.add_argument("--csv-id-col", default="id")
    parser.add_argument("--csv-label-col", default="label")
    parser.add_argument("--model", type=Path, default=Path(__file__).parent / "models_cache" / "hand_landmarker.task",
                         help="Path to the downloaded hand_landmarker.task model file.")
    args = parser.parse_args()

    if args.csv is not None:
        pairs = collect_from_csv(args.csv, args.input_dir, args.csv_id_col, args.csv_label_col, args.max_per_class)
    else:
        pairs = collect_folder_per_class(args.input_dir, args.max_per_class)

    if not pairs:
        sys.exit(f"No labeled images found under {args.input_dir}. Check --input-dir / --csv options.")

    print(f"Found {len(pairs)} labeled images across {len({label for label, _ in pairs})} classes.")

    landmarker = make_landmarker(args.model)
    dataset = []
    skipped = 0
    for i, (label, image_path) in enumerate(pairs, start=1):
        frame = landmarks_from_image(landmarker, image_path)
        if frame is None:
            skipped += 1
            continue
        dataset.append({"label": label, "frames": [frame]})
        if i % 200 == 0:
            print(f"  processed {i}/{len(pairs)} ({skipped} skipped, no hand detected)")

    if not dataset:
        sys.exit("No hand landmarks could be extracted from any image. Check the dataset contents.")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dataset))
    print(f"Wrote {len(dataset)} samples ({skipped} skipped) to {args.output}")


if __name__ == "__main__":
    main()
