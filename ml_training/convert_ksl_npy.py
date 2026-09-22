"""Converts the joanwachuka/ksl-hand-landmarks Kaggle dataset (.npy files,
two-hand MediaPipe Holistic-style landmarks, variable-length frame sequences)
into the same JSON schema extract_landmarks.py produces, so it can go
straight into train_classifier.py unchanged.

Dataset layout on disk (after `kaggle datasets download
joanwachuka/ksl-hand-landmarks -p data/raw/ksl --unzip`):
  data/raw/ksl/data_split/data_split/{train,val,test}/{father,hello,is,my}/*.npy
  data/raw/ksl/dataset2/{fatherr,hellor,isr,myr}/*.npy   (a second batch of
    the same 4 words, 'r'-suffixed; merged into the base label below)

Each .npy is (num_frames, 126): per frame, 126 = 2 hands * 21 landmarks * 3
(x, y, z), concatenated hand-then-hand, coordinates in MediaPipe's normalized
[0,1] range. Inspection showed one hand block is consistently all-zero
(undetected/inactive hand) while the other carries the real signal — so per
sample we keep whichever hand block has more signal (larger sum of absolute
values) and drop the other, since the app currently only tracks one hand at
a time (see lib/features/sign_recognition — HandDetector.detectHandsFromCameraImage
takes hands.first).

Only 4 real words are available this way (father, hello, is, my) — smaller
than hoped, but genuine, licensed (Apache 2.0) data, unlike the unlabeled
"Task Mate" image mirrors this replaced.
"""

import json
from pathlib import Path

import numpy as np

LANDMARK_TYPES = [
    "wrist",
    "thumbCMC", "thumbMCP", "thumbIP", "thumbTip",
    "indexFingerMCP", "indexFingerPIP", "indexFingerDIP", "indexFingerTip",
    "middleFingerMCP", "middleFingerPIP", "middleFingerDIP", "middleFingerTip",
    "ringFingerMCP", "ringFingerPIP", "ringFingerDIP", "ringFingerTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip",
]

LABEL_ALIASES = {
    "father": "father", "fatherr": "father",
    "hello": "hello", "hellor": "hello",
    "is": "is", "isr": "is",
    "my": "my", "myr": "my",
}


def active_hand(arr: np.ndarray) -> np.ndarray:
    hand_a, hand_b = arr[:, :63], arr[:, 63:126]
    return hand_a if np.abs(hand_a).sum() >= np.abs(hand_b).sum() else hand_b


def npy_to_frames(path: Path) -> list[list[dict]] | None:
    arr = np.load(path)
    if arr.ndim != 2 or arr.shape[1] != 126 or arr.shape[0] == 0:
        return None
    hand = active_hand(arr).reshape(arr.shape[0], 21, 3)
    frames = []
    for frame in hand:
        frames.append([
            {"type": t, "x": float(x), "y": float(y), "z": float(z), "visibility": 1.0}
            for t, (x, y, z) in zip(LANDMARK_TYPES, frame)
        ])
    return frames


def main():
    root = Path(__file__).parent / "data" / "raw" / "ksl"
    out_path = Path(__file__).parent / "data" / "ksl_dataset.json"

    dataset = []
    skipped = 0
    for npy_path in sorted(root.rglob("*.npy")):
        label = LABEL_ALIASES.get(npy_path.parent.name)
        if label is None:
            continue
        frames = npy_to_frames(npy_path)
        if frames is None:
            skipped += 1
            continue
        dataset.append({"label": label, "frames": frames})

    if not dataset:
        raise SystemExit(f"No samples converted from {root}. Check the dataset was downloaded and unzipped.")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(dataset))
    labels = sorted({row["label"] for row in dataset})
    print(f"Wrote {len(dataset)} samples ({skipped} skipped) across labels {labels} to {out_path}")


if __name__ == "__main__":
    main()
