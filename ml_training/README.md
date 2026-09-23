# ml_training

Off-device training for the app's sign classifiers. This trains only a small
classification head on top of hand landmarks — it does not touch the hand
detector itself (that's `hand_detection` in the Flutter app, a pretrained
on-device model).

Two separate things live here, and they are **not** the same data source:

- **Custom Signs** (in the app) — a per-user, zero-shot template matcher
  (`lib/core/services/custom_sign_recognizer.dart`). Users record their own
  non-standard signs and the app matches against them directly, no training
  involved. Nothing here feeds into that, and nothing recorded there feeds
  into this.
- **This pipeline** — trains a general classifier for a real, standard sign
  vocabulary (ASL alphabet, KSL words) from public datasets, bundled into the
  app so it works out of the box for every user.

## Setup

```
pyenv install 3.11.9   # if not already installed
cd ml_training
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 1. Pipeline test (synthetic data — always works, proves nothing about real accuracy)

```
python generate_dummy_data.py
python train_classifier.py --data data/dummy_dataset.json --out-prefix dummy
```

Confirms the training + TFLite export code path works. Never copy
`data/dummy_model.tflite` into `assets/models/` — it's trained on fabricated
data.

## 2. Real data: download

Two manual steps only you can do (this environment has no accounts on your
behalf):

**a) The hand landmark model** (free, no login, ~7.8MB):

```
mkdir -p models_cache
curl -L -o models_cache/hand_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
```

**b) The image datasets** (free, but requires a Kaggle account + API token):

1. Create a free account at kaggle.com if you don't have one.
2. Go to kaggle.com → Settings → API → "Create New Token". This downloads
   `kaggle.json`.
3. `pip install kaggle` (already in requirements.txt) and place the token:
   ```
   mkdir -p ~/.kaggle
   mv ~/Downloads/kaggle.json ~/.kaggle/kaggle.json
   chmod 600 ~/.kaggle/kaggle.json
   ```
4. Download the datasets:
   ```
   kaggle datasets download grassknoted/asl-alphabet -p data/raw/asl --unzip
   kaggle datasets download gauravduttakiit/kslc-kenyan-sign-language-classification-challenge -p data/raw/ksl --unzip
   ```

ASL Alphabet: 87k images, A–Z + space/delete/nothing, folder-per-class.
After unzipping, the images are nested one level deeper
(`data/raw/asl/asl_alphabet_train/asl_alphabet_train/<LETTER>/*.jpg`) — point
`extract_landmarks.py` at that inner folder.

KSL: ~8,898 images of 10 everyday KSL signs (CC-BY-SA 4.0, attribute Zindi /
Task Mate / the original KSL dataset collectors if you publish results).
Check what actually lands in `data/raw/ksl` after unzipping — Kaggle mirrors
of Zindi competitions sometimes ship as a CSV (`Train.csv` with an image ID
column and a label column) plus a flat `images/` folder rather than
folder-per-class. `extract_landmarks.py` supports both layouts; use `--csv`
if you get the CSV form.

There are two more KSL sources from the Maseno University team (Maina,
Wanzare, Obuhuma), verified 2026-09-23:

- **`10.5281/zenodo.14338329`** — "KSL Pose Dataset". CC BY 4.0, `Pose
  Data.zip` (1.5GB), **open access, no login needed**. MediaPipe Holistic
  landmarks (body + hands + face) with stickman videos. This is the one
  actually being integrated now — see the full-body/face pipeline extension
  below.
- `10.5281/zenodo.14974973` — "KSL Word Based Pose Dataset", much larger
  (57GB this version, 420GB across all versions), same CC BY 4.0 license
  but files require a Zenodo login/access request. Not yet pursued.

(A stale note previously here claimed the second dataset was ~30k clips
from 685 signers and openly downloadable — that was never actually
verified against the source and was wrong; corrected after being caught.)

## 3. Real data: extract landmarks

```
python extract_landmarks.py \
  --input-dir data/raw/asl/asl_alphabet_train/asl_alphabet_train \
  --output data/asl_dataset.json \
  --max-per-class 400

# if the KSL dataset is folder-per-class:
python extract_landmarks.py \
  --input-dir data/raw/ksl/<class folders live here> \
  --output data/ksl_dataset.json \
  --max-per-class 400

# if the KSL dataset is CSV-labeled instead:
python extract_landmarks.py \
  --input-dir data/raw/ksl/images \
  --csv data/raw/ksl/Train.csv --csv-id-col ID --csv-label-col target \
  --output data/ksl_dataset.json \
  --max-per-class 400
```

`--max-per-class` caps samples per class so training stays CPU-fast; raise
it once you've confirmed the pipeline works end-to-end.

## 4. Real data: train + export

```
python train_classifier.py --data data/asl_dataset.json --out-prefix asl_alphabet
python train_classifier.py --data data/ksl_dataset.json --out-prefix ksl_words
```

Prints both training and validation accuracy. Outputs land in `data/` as
`<prefix>_model.tflite` and `<prefix>_labels.json`.

## 5. Bundle into the app

Copy the two output pairs into `../assets/models/`:

```
cp data/asl_alphabet_model.tflite data/asl_alphabet_labels.json ../assets/models/
cp data/ksl_words_model.tflite data/ksl_words_labels.json ../assets/models/
```

`SignClassifierService` (`lib/core/services/sign_classifier_service.dart`)
loads whichever pair matches the language selected in Settings. If a pair is
missing, that language option in Settings has no effect and the app falls
back to the built-in gesture set + Custom Signs — it won't crash.
