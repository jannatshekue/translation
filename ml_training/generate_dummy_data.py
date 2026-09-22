"""Generates SYNTHETIC landmark data for testing the training pipeline only.

This is not real captured sign data — the "signs" and landmark positions are
fabricated. A model trained on this can prove the code path (data loading,
preprocessing, training loop, TFLite export) works end-to-end; it cannot and
must not be used as a real sign classifier. Nothing here is wired into the
app's assets/models/.

Output format matches exactly what the app's Custom Sign Creation screen
records: each sample is a list of frames, each frame a list of 21 landmark
dicts with type/x/y/z/visibility (see lib/models/custom_sign.dart and
lib/core/services/hand_pose_matcher.dart on the Dart side).
"""

import json
import random
from pathlib import Path

LANDMARK_TYPES = [
    "wrist",
    "thumbCMC", "thumbMCP", "thumbIP", "thumbTip",
    "indexFingerMCP", "indexFingerPIP", "indexFingerDIP", "indexFingerTip",
    "middleFingerMCP", "middleFingerPIP", "middleFingerDIP", "middleFingerTip",
    "ringFingerMCP", "ringFingerPIP", "ringFingerDIP", "ringFingerTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip",
]

# Fabricated "signs" — arbitrary labels, not real ASL/BSL signs. Each gets a
# distinct base pose (deterministic offset per landmark) so the synthetic
# classes are actually separable, which is what makes the pipeline test
# meaningful (loss should visibly drop during training) rather than trivial.
DUMMY_LABELS = ["dummy_sign_a", "dummy_sign_b", "dummy_sign_c"]

SAMPLES_PER_LABEL = 30
FRAMES_PER_SAMPLE = 15
NOISE_STDDEV = 3.0


def base_pose_for_label(label_index: int) -> dict:
    """A fixed, label-dependent (x, y) for every landmark, in pixel-like units."""
    rng = random.Random(f"base-{label_index}")
    return {
        t: (rng.uniform(50, 250) + label_index * 80, rng.uniform(50, 250) + label_index * 40)
        for t in LANDMARK_TYPES
    }


def make_frame(base_pose: dict, rng: random.Random) -> list[dict]:
    frame = []
    for t in LANDMARK_TYPES:
        bx, by = base_pose[t]
        frame.append({
            "type": t,
            "x": bx + rng.gauss(0, NOISE_STDDEV),
            "y": by + rng.gauss(0, NOISE_STDDEV),
            "z": rng.gauss(0, 1.0),
            "visibility": 1.0,
        })
    return frame


def make_sample(label_index: int, sample_seed: int) -> list[list[dict]]:
    base_pose = base_pose_for_label(label_index)
    rng = random.Random(sample_seed)
    return [make_frame(base_pose, rng) for _ in range(FRAMES_PER_SAMPLE)]


def main():
    dataset = []
    for label_index, label in enumerate(DUMMY_LABELS):
        for sample_index in range(SAMPLES_PER_LABEL):
            dataset.append({
                "label": label,
                "frames": make_sample(label_index, sample_seed=label_index * 1000 + sample_index),
            })

    random.Random(42).shuffle(dataset)

    out_dir = Path(__file__).parent / "data"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "dummy_dataset.json"
    out_path.write_text(json.dumps(dataset))
    print(f"Wrote {len(dataset)} synthetic samples ({len(DUMMY_LABELS)} labels) to {out_path}")


if __name__ == "__main__":
    main()
