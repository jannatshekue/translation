"""Trains a temporal KSL word classifier on the output of
extract_holistic_sequences.py — full-body sequences (both hands + upper-body
pose + non-manual face markers), not single frames. See that script's
docstring for the full rationale.

Two-pass design, because which words are reliable enough to ship can only
be known from real held-out results, not decided in advance:

  Pass 1 (evaluation): every word with >= MIN_SAMPLES_FOR_OWN_CLASS samples
  gets its own class; everything thinner (plus junk labels already dropped
  at extraction) is folded into one "_background" class. Train, then look
  at each class's validation recall.

  Pass 2 (production): only words whose Pass-1 recall cleared
  RECALL_THRESHOLD keep their own class; everything else (including
  Pass-1 candidates that didn't clear the bar) folds into "_background".
  Retrain fresh on this finalized label set and export that model. This
  avoids ending up with a shipped model whose label list doesn't match its
  actual output indices, which would happen if labels were dropped
  after the fact instead of before a fresh training run.

Small-sample caveat, stated plainly: many Pass-1 classes have only 3-5
total samples, meaning their validation split is a single clip. A recall
of 0% or 100% from one example is a weak signal, not a confident
measurement — but it's the only real signal available today, and it will
firm up automatically as Maseno releases more dataset batches (this
dataset ships in batches; re-running this pipeline against a bigger
download needs no code changes, just more samples per class).

Architecture: Conv1D over the fixed 32-frame sequence, not an LSTM.
Chosen deliberately — inputs are already a fixed length (see
extract_holistic_sequences.py's resampling), so there's no variable-length/
masking need an LSTM would justify, and plain Conv1D/Dense layers convert
to TFLite via the standard converter with zero risk of the
SELECT_TF_OPS/custom-op issues LSTM layers sometimes hit on-device.
"""

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

DATA_DIR = Path(__file__).parent / "data"
BACKGROUND_LABEL = "_background"
MIN_SAMPLES_FOR_OWN_CLASS = 3
RECALL_THRESHOLD = 0.5


def fold_thin_classes(y: np.ndarray, min_samples: int) -> np.ndarray:
    counts = {label: int((y == label).sum()) for label in set(y)}
    return np.array([label if counts[label] >= min_samples else BACKGROUND_LABEL for label in y])


def per_class_split(x: np.ndarray, y: np.ndarray, val_fraction: float, seed: int):
    """Splits so every class with enough samples gets at least 1 validation
    example — sklearn's stratified split can fail or silently starve val
    sets for classes this small, so this is done by hand per class."""
    rng = np.random.default_rng(seed)
    train_idx, val_idx = [], []
    for label in sorted(set(y)):
        idx = np.flatnonzero(y == label)
        rng.shuffle(idx)
        n_val = max(1, round(len(idx) * val_fraction)) if len(idx) > 1 else 0
        val_idx.extend(idx[:n_val])
        train_idx.extend(idx[n_val:])
    return (
        x[train_idx], y[train_idx],
        x[val_idx], y[val_idx],
    )


def build_model(input_shape: tuple[int, int], num_classes: int) -> tf.keras.Model:
    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=input_shape),
        tf.keras.layers.Conv1D(64, kernel_size=3, activation="relu", padding="same"),
        tf.keras.layers.Conv1D(64, kernel_size=3, activation="relu", padding="same"),
        tf.keras.layers.GlobalAveragePooling1D(),
        tf.keras.layers.Dense(128, activation="relu"),
        tf.keras.layers.Dropout(0.3),
        tf.keras.layers.Dense(num_classes, activation="softmax"),
    ])
    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return model


def train_and_evaluate(x, y, labels, epochs, seed):
    label_to_index = {label: i for i, label in enumerate(labels)}
    x_train, y_train_str, x_val, y_val_str = per_class_split(x, y, val_fraction=0.2, seed=seed)
    y_train = np.array([label_to_index[label] for label in y_train_str])
    y_val = np.array([label_to_index[label] for label in y_val_str])

    model = build_model(input_shape=x.shape[1:], num_classes=len(labels))
    model.fit(
        x_train, y_train,
        validation_data=(x_val, y_val),
        epochs=epochs,
        batch_size=16,
        verbose=0,
    )

    val_predictions = np.argmax(model.predict(x_val, verbose=0), axis=1)
    per_class_recall = {}
    for label, idx in label_to_index.items():
        class_mask = y_val == idx
        if class_mask.sum() == 0:
            continue
        per_class_recall[label] = float((val_predictions[class_mask] == idx).mean())

    overall_val_accuracy = float((val_predictions == y_val).mean())
    return model, per_class_recall, overall_val_accuracy


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", type=Path, default=DATA_DIR / "ksl_holistic_sequences.npz")
    parser.add_argument("--out-prefix", default="ksl_words_dynamic")
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--recall-threshold", type=float, default=RECALL_THRESHOLD)
    parser.add_argument("--min-samples", type=int, default=MIN_SAMPLES_FOR_OWN_CLASS)
    args = parser.parse_args()

    loaded = np.load(args.data, allow_pickle=True)
    x, y_raw = loaded["x"], loaded["y"]
    print(f"Loaded {len(x)} clips, {len(set(y_raw))} raw labels, feature width {x.shape[2]}.")

    # Pass 1: evaluation run.
    y_pass1 = fold_thin_classes(y_raw, args.min_samples)
    labels_pass1 = sorted(set(y_pass1))
    print(f"\nPass 1: {len(labels_pass1) - 1} candidate word classes "
          f"(>= {args.min_samples} samples) + background.")
    _, per_class_recall, overall_acc = train_and_evaluate(x, y_pass1, labels_pass1, args.epochs, seed=0)
    print(f"Pass 1 overall validation accuracy: {overall_acc:.1%}")

    reliable_words = sorted(
        label for label, recall in per_class_recall.items()
        if label != BACKGROUND_LABEL and recall >= args.recall_threshold
    )
    print(f"\n{len(reliable_words)} of {len(labels_pass1) - 1} candidate words cleared "
          f"the {args.recall_threshold:.0%} validation-recall bar:")
    for label in reliable_words:
        print(f"  {label}: recall {per_class_recall[label]:.0%}")
    dropped = sorted(
        (label, recall) for label, recall in per_class_recall.items()
        if label != BACKGROUND_LABEL and recall < args.recall_threshold
    )
    if dropped:
        print(f"\n{len(dropped)} candidates did NOT clear the bar (folded into background for Pass 2):")
        for label, recall in dropped:
            print(f"  {label}: recall {recall:.0%}")

    if not reliable_words:
        raise SystemExit(
            "No word cleared the reliability bar in Pass 1 — nothing to ship. "
            "This dataset needs more samples per class before a production model is worth exporting."
        )

    # Pass 2: production run, restricted to words that actually proved out.
    y_pass2 = np.array([label if label in reliable_words else BACKGROUND_LABEL for label in y_raw])
    labels_pass2 = sorted(set(y_pass2))
    model, final_recall, final_overall_acc = train_and_evaluate(x, y_pass2, labels_pass2, args.epochs, seed=1)
    print(f"\nPass 2 (production) overall validation accuracy: {final_overall_acc:.1%}")
    for label in reliable_words:
        print(f"  {label}: recall {final_recall.get(label, float('nan')):.0%}")

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()

    model_out = DATA_DIR / f"{args.out_prefix}_model.tflite"
    labels_out = DATA_DIR / f"{args.out_prefix}_labels.json"
    model_out.write_bytes(tflite_model)
    labels_out.write_text(json.dumps(labels_pass2))
    print(f"\nWrote {model_out} and {labels_out} ({len(labels_pass2)} classes incl. background).")


if __name__ == "__main__":
    main()
