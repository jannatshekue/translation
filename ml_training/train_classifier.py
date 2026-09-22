"""Trains the sign-classification layer on landmark sample data and exports
a TFLite model + labels file for the app to bundle in assets/models/.

Default run (no arguments) trains on the SYNTHETIC pipeline-test data from
generate_dummy_data.py — this only proves the training + export pipeline
works; it is not a real classifier. Do not copy its output into assets/models/.

For a real classifier, pass --data pointing at a dataset produced by
extract_landmarks.py (see that script and README.md), and --out-prefix to
name the outputs, e.g.:

    python train_classifier.py --data data/asl_dataset.json --out-prefix asl_alphabet
    python train_classifier.py --data data/ksl_dataset.json --out-prefix ksl_words

Preprocessing mirrors the Dart-side on-device matcher
(lib/core/services/hand_pose_matcher.dart): each frame's landmarks are
translated to a wrist-relative origin and scaled by wrist-to-middle-MCP
distance, then frames within a sample are averaged into one fixed-length
feature vector (21 landmarks * 2 coords = 42 features). This keeps the
off-device model trained on the same representation the on-device code uses.
"""

import argparse
import json
import math
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split

LANDMARK_TYPES = [
    "wrist",
    "thumbCMC", "thumbMCP", "thumbIP", "thumbTip",
    "indexFingerMCP", "indexFingerPIP", "indexFingerDIP", "indexFingerTip",
    "middleFingerMCP", "middleFingerPIP", "middleFingerDIP", "middleFingerTip",
    "ringFingerMCP", "ringFingerPIP", "ringFingerDIP", "ringFingerTip",
    "pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip",
]

DATA_DIR = Path(__file__).parent / "data"


def normalize_frame(frame: list[dict]) -> np.ndarray | None:
    by_type = {p["type"]: p for p in frame}
    wrist = by_type.get("wrist")
    middle_mcp = by_type.get("middleFingerMCP")
    if wrist is None or middle_mcp is None:
        return None

    scale = math.hypot(middle_mcp["x"] - wrist["x"], middle_mcp["y"] - wrist["y"])
    if scale < 1e-6:
        return None

    vector = []
    for t in LANDMARK_TYPES:
        point = by_type.get(t)
        if point is None:
            return None
        vector.append((point["x"] - wrist["x"]) / scale)
        vector.append((point["y"] - wrist["y"]) / scale)
    return np.array(vector, dtype=np.float32)


def sample_to_feature(frames: list[list[dict]]) -> np.ndarray | None:
    vectors = [v for v in (normalize_frame(f) for f in frames) if v is not None]
    if not vectors:
        return None
    return np.mean(vectors, axis=0)


def load_dataset(data_path: Path) -> tuple[np.ndarray, np.ndarray, list[str]]:
    if not data_path.exists():
        raise SystemExit(
            f"No dataset at {data_path}. Run generate_dummy_data.py for a pipeline "
            "test, or extract_landmarks.py for a real dataset."
        )
    raw = json.loads(data_path.read_text())

    labels = sorted({row["label"] for row in raw})
    label_to_index = {label: i for i, label in enumerate(labels)}

    features, targets = [], []
    for row in raw:
        feature = sample_to_feature(row["frames"])
        if feature is None:
            continue
        features.append(feature)
        targets.append(label_to_index[row["label"]])

    return np.stack(features), np.array(targets, dtype=np.int64), labels


def build_model(num_classes: int, num_features: int) -> tf.keras.Model:
    hidden1 = max(32, num_classes * 2)
    hidden2 = max(16, num_classes)
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(num_features,)),
        tf.keras.layers.Dense(hidden1, activation="relu"),
        tf.keras.layers.Dense(hidden2, activation="relu"),
        tf.keras.layers.Dense(num_classes, activation="softmax"),
    ])
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return model


def split_dataset(features: np.ndarray, targets: np.ndarray, val_split: float):
    counts = np.bincount(targets)
    can_stratify = val_split > 0 and counts.min() >= 2
    if val_split <= 0:
        return features, targets, None, None
    return train_test_split(
        features, targets,
        test_size=val_split,
        random_state=42,
        stratify=targets if can_stratify else None,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, default=DATA_DIR / "dummy_dataset.json",
                         help="Dataset JSON (default: the synthetic pipeline-test data).")
    parser.add_argument("--out-prefix", default="dummy",
                         help="Output filename prefix under data/ (default: 'dummy').")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--val-split", type=float, default=0.2,
                         help="Fraction held out for validation (0 to disable).")
    args = parser.parse_args()

    features, targets, labels = load_dataset(args.data)
    print(f"Loaded {len(features)} samples across {len(labels)} labels: {labels}")

    x_train, x_val, y_train, y_val = split_dataset(features, targets, args.val_split)
    validation_data = (x_val, y_val) if x_val is not None else None

    model = build_model(num_classes=len(labels), num_features=features.shape[1])
    history = model.fit(
        x_train, y_train,
        validation_data=validation_data,
        epochs=args.epochs,
        batch_size=8,
        verbose=2,
    )

    train_accuracy = history.history["accuracy"][-1]
    print(f"Final training accuracy: {train_accuracy:.2%}")
    if validation_data is not None:
        val_accuracy = history.history["val_accuracy"][-1]
        print(f"Final validation accuracy: {val_accuracy:.2%}")
    else:
        print("No validation split — accuracy above is training accuracy only.")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    model_out = DATA_DIR / f"{args.out_prefix}_model.tflite"
    labels_out = DATA_DIR / f"{args.out_prefix}_labels.json"
    model_out.write_bytes(tflite_model)
    labels_out.write_text(json.dumps(labels))
    print(f"Wrote {model_out} and {labels_out}")


if __name__ == "__main__":
    main()
