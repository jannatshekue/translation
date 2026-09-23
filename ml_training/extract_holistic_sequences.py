"""Extracts full-body sign sequences (both hands + upper-body pose + a
non-manual-marker face subset) from the Maseno University KSL Pose Dataset
(Zenodo 10.5281/zenodo.14338329, "Pose Data.zip", CC BY 4.0, open access —
see README.md) and writes a single windowed dataset ready for
train_sequence_classifier.py.

This is a SEPARATE pipeline from extract_landmarks.py / train_classifier.py,
which only ever handled static single-frame hand images (Kaggle ASL/KSL).
This dataset is fundamentally different: every clip is a short VIDEO of one
signed word (11-190 frames observed), and real KSL — like any sign
language — carries meaning in movement and facial grammar (non-manual
markers), not just a held handshape. Using it properly means a sequence
model over time, not a per-frame classifier; that's what this script feeds.

Per-frame source format (verified by loading real samples, not assumed):
    {"pose": [(x,y,z) x33], "left_hand": [(x,y,z) x21] or [],
     "right_hand": [...] or [], "face": [(x,y,z) x468]}
Hands are frequently `[]` (not detected that frame) — filled by carrying
forward/backward the nearest frame where that hand *was* detected, since
zero-filling would inject a false "hand at the origin" signal.

Landmark subsets (chosen, not the full raw counts, and why):
  - Both hands: all 21 points each — this is the actual sign content.
  - Pose: only nose + shoulders + elbows + wrists (7 of 33 BlazePose
    points). Hips/knees/ankles/feet are essentially never meaningfully in
    frame for a chest-up signing video and would just add noise dimensions.
  - Face: 18 of 468 FaceMesh points — eyebrows, eyes, and mouth corners/
    center, verified against MediaPipe's own canonical
    face_mesh_connections.py index groups (FACEMESH_LEFT/RIGHT_EYEBROW,
    FACEMESH_LEFT/RIGHT_EYE, FACEMESH_LIPS). These are the standard
    non-manual-marker regions in sign language linguistics (eyebrow
    raise/furrow, eye aperture, mouth shape). Feeding the classifier all
    468 raw points on a dataset this small (see class-count reality below)
    would overfit badly and triple the input width for no linguistic gain.

Every clip is resampled (linear interpolation along the time axis) to a
fixed 32 frames — the median clip length across the dataset — so the
downstream model can use a plain fixed-length architecture with no masking.

Class-count reality (checked directly, not assumed): 728 raw word labels,
but only ~128 have >=3 samples (the minimum to structurally take at least
one training AND one validation example). Labels below that threshold, and
a handful of clearly non-linguistic labels (".mp4", pure numbers), are
folded into a single "_background" class instead of getting their own
under-trained output slot — see train_sequence_classifier.py for why.
"""

import argparse
import io
import json
import re
import zipfile
from pathlib import Path

import numpy as np

SEQUENCE_LENGTH = 32  # median clip length across a 120-clip sample; see module docstring.

# MediaPipe BlazePose (33-point) indices for nose/shoulders/elbows/wrists —
# https://developers.google.com/mediapipe/solutions/vision/pose_landmarker
POSE_INDICES = [0, 11, 12, 13, 14, 15, 16]

# MediaPipe FaceMesh (468-point) indices, verified against the canonical
# connection groups in mediapipe/python/solutions/face_mesh_connections.py:
FACE_INDICES = [
    # eyebrows (3 per side, from FACEMESH_RIGHT_EYEBROW / FACEMESH_LEFT_EYEBROW)
    46, 52, 105, 276, 282, 334,
    # eyes: outer corner, inner corner, upper lid, lower lid, per side
    33, 133, 159, 145, 362, 263, 386, 374,
    # mouth: corners + upper/lower lip center, from FACEMESH_LIPS
    61, 291, 13, 14,
]

HAND_LEN = 21
JUNK_LABELS = {".MP4", "0", "4", "10", "24"}
BACKGROUND_LABEL = "_background"
MIN_SAMPLES_FOR_OWN_CLASS = 3  # see docstring: below this, a class can't be both trained and validated.

CLIP_PATH_RE = re.compile(r"^Pose Data/(Batch \d+)/(\d+)/Extract/Landmarks/(.+)\.npy$")


def _fill_missing(points_per_frame: list[list[tuple]], expected_len: int) -> np.ndarray:
    """Forward/backward-fills frames where a part (a hand, or rarely the
    face) wasn't detected, using the nearest frame where it was. Returns
    zeros only if the part is missing in literally every frame of the clip.
    """
    n = len(points_per_frame)
    arr = np.zeros((n, expected_len, 3), dtype=np.float32)
    present = np.array([len(p) == expected_len for p in points_per_frame])
    for i, pts in enumerate(points_per_frame):
        if present[i]:
            arr[i] = np.array(pts, dtype=np.float32)

    if not present.any():
        return arr  # never detected in this clip — leave as zeros.

    present_idx = np.flatnonzero(present)
    for i in np.flatnonzero(~present):
        nearest = present_idx[np.argmin(np.abs(present_idx - i))]
        arr[i] = arr[nearest]
    return arr


def _normalize(points: np.ndarray, origin_idx, scale_a_idx, scale_b_idx) -> np.ndarray | None:
    """Translates to an origin point (or midpoint of two) and scales by the
    distance between two reference points, per-frame. Returns None if scale
    collapses to ~0 anywhere (degenerate frame, e.g. shoulders not visible).
    Uses x,y only — matches the existing on-device HandPoseMatcher, which
    also drops z (MediaPipe's relative-depth estimate is noisier than x/y).
    """
    xy = points[:, :, :2]
    if isinstance(origin_idx, tuple):
        origin = (xy[:, origin_idx[0]] + xy[:, origin_idx[1]]) / 2
    else:
        origin = xy[:, origin_idx]
    scale = np.linalg.norm(xy[:, scale_a_idx] - xy[:, scale_b_idx], axis=-1)
    if np.any(scale < 1e-6):
        return None
    centered = xy - origin[:, None, :]
    return centered / scale[:, None, None]


def frame_feature_sequence(frames: np.ndarray) -> np.ndarray | None:
    """Builds the (num_frames, D) feature sequence for one clip, or None if
    it can't be normalized (e.g. pose/shoulders never detected)."""
    left_hand = _fill_missing([f.get("left_hand", []) for f in frames], HAND_LEN)
    right_hand = _fill_missing([f.get("right_hand", []) for f in frames], HAND_LEN)
    pose_full = np.array([[f["pose"][i] for i in POSE_INDICES] for f in frames], dtype=np.float32)
    face_full = _fill_missing(
        [[f["face"][i] for i in FACE_INDICES] if len(f.get("face", [])) > 0 else [] for f in frames],
        len(FACE_INDICES),
    )

    # Pose subset indices within POSE_INDICES: nose=0, l_shoulder=1, r_shoulder=2, l_elbow=3, r_elbow=4, l_wrist=5, r_wrist=6.
    pose_norm = _normalize(pose_full, origin_idx=(1, 2), scale_a_idx=1, scale_b_idx=2)
    # Hand landmark order matches extract_landmarks.py's LANDMARK_TYPES: wrist=0, middleFingerMCP=9.
    left_norm = _normalize(left_hand, origin_idx=0, scale_a_idx=0, scale_b_idx=9)
    right_norm = _normalize(right_hand, origin_idx=0, scale_a_idx=0, scale_b_idx=9)
    # Face subset order: eyebrows[0:6], eyes[6:14] (right outer=6, right inner=7, left inner=10, left outer=11), mouth[14:18].
    face_norm = _normalize(face_full, origin_idx=(6, 11), scale_a_idx=6, scale_b_idx=11)

    if pose_norm is None or face_norm is None:
        return None
    # A hand that's simply never used for this sign (all-zero fill) has scale 0
    # at the wrist-to-MCP distance; treat that as "hand absent", not a reject.
    if left_norm is None:
        left_norm = np.zeros((len(frames), HAND_LEN, 2), dtype=np.float32)
    if right_norm is None:
        right_norm = np.zeros((len(frames), HAND_LEN, 2), dtype=np.float32)

    parts = [left_norm, right_norm, pose_norm, face_norm]
    return np.concatenate([p.reshape(len(frames), -1) for p in parts], axis=1)


def resample_to_fixed_length(sequence: np.ndarray, length: int) -> np.ndarray:
    """Linearly interpolates a (T, D) sequence to (length, D) along time, so
    a fast 11-frame sign and a slow 190-frame sign both become one
    fixed-length representation a plain (non-masked) model can consume."""
    t_original = np.linspace(0, 1, num=len(sequence))
    t_target = np.linspace(0, 1, num=length)
    return np.stack([np.interp(t_target, t_original, sequence[:, d]) for d in range(sequence.shape[1])], axis=1)


def clean_label(raw_label: str) -> str | None:
    label = raw_label.strip().upper()
    if not label or label in JUNK_LABELS or label.replace(".", "").isdigit():
        return None
    return label


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", type=Path, default=Path(__file__).parent / "data/ksl_pose_dataset/Pose Data.zip")
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "data/ksl_holistic_sequences.npz")
    args = parser.parse_args()

    with zipfile.ZipFile(args.zip) as z:
        clip_names = [n for n in z.namelist() if CLIP_PATH_RE.match(n)]
        print(f"Found {len(clip_names)} clip files in {args.zip.name}.")

        sequences, raw_labels = [], []
        skipped_junk = skipped_normalize = 0
        for i, name in enumerate(clip_names, start=1):
            match = CLIP_PATH_RE.match(name)
            label = clean_label(match.group(3))
            if label is None:
                skipped_junk += 1
                continue

            with z.open(name) as f:
                frames = np.load(io.BytesIO(f.read()), allow_pickle=True)
            if len(frames) == 0:
                skipped_normalize += 1
                continue

            try:
                features = frame_feature_sequence(frames)
            except (KeyError, IndexError, ValueError):
                # A shape this script's design didn't anticipate (verified
                # against a 120-clip sample, not all 1495) — skip rather
                # than crash the whole extraction run.
                features = None
            if features is None:
                skipped_normalize += 1
                continue

            sequences.append(resample_to_fixed_length(features, SEQUENCE_LENGTH))
            raw_labels.append(label)

            if i % 200 == 0:
                print(f"  processed {i}/{len(clip_names)}")

    if not sequences:
        raise SystemExit("No usable clips extracted — check the zip path / dataset contents.")

    x = np.stack(sequences).astype(np.float32)
    y = np.array(raw_labels)
    print(f"Extracted {len(x)} clips (skipped {skipped_junk} junk-labeled, {skipped_normalize} unnormalizable), "
          f"feature width {x.shape[2]}, across {len(set(raw_labels))} raw labels.")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(args.output, x=x, y=y)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
