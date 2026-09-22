# Sign & Voice Translator

A Flutter mobile app for two-way communication between people with hearing
or speech disabilities and people without them. Built as a BSc Computer
Science academic project at Umma University.

Every core feature works fully offline. Online connectivity is only ever
used to *improve* accuracy (e.g. downloading a translation language model
once) — it never gates a feature. The whole project is built to run at
**zero ongoing cost**.

---

## Table of contents

- [Features](#features)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Setup guide (step by step, for a new machine)](#setup-guide-step-by-step-for-a-new-machine)
- [Running the app on your phone](#running-the-app-on-your-phone)
- [Building a release APK](#building-a-release-apk)
- [Building for the Play Store](#building-for-the-play-store-android-app-bundle)
- [Testing](#testing)
- [The ML training pipeline](#the-ml-training-pipeline-ml_training)
- [Known limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Sign Recognition** — live camera feed, on-device hand-landmark
  detection. Recognizes signs in this priority order:
  1. Your own **Custom Signs** (see below), if any match.
  2. A **trained classifier** for the sign language selected in Settings
     (ASL or KSL — see [ML training pipeline](#the-ml-training-pipeline-ml_training)).
  3. The built-in gesture set (thumbs up/down, victory, open palm, closed
     fist, pointing up, "I love you") as a fallback.

  Whatever is recognized is spoken aloud via text-to-speech, with haptic and
  screen-flash feedback.
- **Custom Sign Creation** — record and label your own signs (e.g. a name,
  or a sign not covered by ASL/KSL); matched against the live camera feed
  using lightweight on-device template matching. This is a *personal*
  feature — nothing recorded here is used to train the shared ASL/KSL
  models, and nothing in those models depends on it.
- **Voice Translation** — on-device speech-to-text and text-to-speech, each
  with its own language picker. Section order adapts automatically: users
  with the "Cannot speak" accessibility profile see text-to-speech first.
- **Conversation Mode** — two people, two languages, one phone: speech is
  recognized, translated on-device (Google ML Kit), and spoken back in the
  other person's language.
- **Learning Module** — 33 practice lessons: the 7 built-in gestures plus
  the full real ASL alphabet (A–Z), each with a handshape description and
  progress tracking.
- **Saved Phrases** — quick-access phrases you can save and speak aloud.
- **Emergency Mode** (Android only) — defaults to a real, editable emergency
  contact (112) plus any contacts you add yourself. Sending an alert always
  shows a confirmation dialog listing every recipient (and lets you add a
  one-off number) before anything is sent — nothing goes out on a single
  tap. Sends an SMS with your GPS location. Not available on iOS, which
  blocks programmatic SMS sending.
- **Accessibility profiles** — chosen once on first launch (Normal /
  Hearing disability / Cannot speak), changeable anytime in Settings.
  Adjusts Home screen ordering, Voice Translation section order, and
  default vibration/flash-alert toggles for the chosen profile. No feature
  is ever hidden by profile choice — only reordered and pre-toggled.
- **Appearance & alerts settings** — light/dark/automatic (time-based)
  theme, adjustable text size, high contrast mode, vibration alerts, and
  screen-flash alerts.
- **Backup & restore** — export/import your custom signs and saved phrases
  as a file, for moving to a new phone or before uninstalling.

## Tech stack

| Layer | Choice |
|---|---|
| App shell | Flutter (Dart) |
| Hand/gesture detection | [`hand_detection`](https://pub.dev/packages/hand_detection) (on-device TFLite, pure Dart) |
| Trained sign classifiers (ASL/KSL) | `tflite_flutter` running models trained offline — see [ML training pipeline](#the-ml-training-pipeline-ml_training) |
| Speech-to-text / text-to-speech | `speech_to_text`, `flutter_tts` (on-device) |
| Translation (Conversation Mode) | `google_mlkit_translation` (on-device, one-time model download per language) |
| Local storage | SQLite via `sqflite` |
| Emergency SMS | Native Android `SmsManager` via a Kotlin platform channel + `geolocator` for GPS |
| Model training (off-device) | Python + TensorFlow + MediaPipe, trains only a small classification head on hand landmarks |

Every dependency was chosen to work at **$0 cost**, mostly offline, without
needing weeks of native-platform work from a single developer. See
`lib/core/services/` for the service layer backing each feature, and
`lib/features/` for the screens themselves (one folder per feature).

## Project structure

```
lib/
  core/
    services/     # SettingsService, DatabaseService, EmergencySmsService,
                   # SignClassifierService, HandDetectionService, ...
    theme/         # App theme + color scheme
    utils/         # PermissionPrimer, FlashAlert, etc.
  features/        # One folder per screen/feature (see Features above)
  models/          # Plain data classes (CustomSign, Lesson, EmergencyContact, ...)
  routes/          # Named route table
  shared/widgets/  # Reusable widgets (AppBackground, PressableScale, SectionCard)
android/           # Native Android project (Kotlin platform channel for SMS)
ios/               # Native iOS project (untested — see Known limitations)
assets/
  models/          # Bundled .tflite models + label files for Sign Recognition
  lessons/         # Learning Module content (lessons.json)
ml_training/       # Separate Python toolchain that produces assets/models/*
                    # — see ml_training/README.md
test/              # Flutter unit/widget tests
```

## Setup guide (step by step, for a new machine)

This section assumes **no prior setup at all**. It takes most people
30–90 minutes the first time, mostly waiting for downloads/installs. Take it
one step at a time — you don't need to understand Flutter or Android
development to follow it.

### 1. Install Git

Git is what lets you download ("clone") this project's code.

- **Windows**: download and run the installer from
  [git-scm.com/download/win](https://git-scm.com/download/win). Accept the
  defaults throughout.
- **macOS**: open Terminal and run `git --version` — macOS will offer to
  install it for you if it's missing.
- **Linux**: `sudo apt install git` (Ubuntu/Debian) or your distro's
  equivalent.

### 2. Install Flutter

Follow the **official installer** for your operating system — it's the most
reliable path and changes less often than any instructions written here:

- Windows: [docs.flutter.dev/get-started/install/windows](https://docs.flutter.dev/get-started/install/windows)
- macOS: [docs.flutter.dev/get-started/install/macos](https://docs.flutter.dev/get-started/install/macos)
- Linux: [docs.flutter.dev/get-started/install/linux](https://docs.flutter.dev/get-started/install/linux)

The installer will also prompt you to install **Android Studio**, which you
need (it provides the Android SDK and `adb`, the tool used to talk to your
phone). Accept that prompt.

Once installed, open a terminal (Command Prompt/PowerShell on Windows,
Terminal on macOS/Linux) and run:

```bash
flutter doctor
```

This checks your setup and tells you what's missing, if anything. Fix
anything it flags with a `✗` before continuing — it usually gives you the
exact command to run. It's normal to see a warning about Xcode/iOS if
you're not building for iPhone; you can ignore that one.

### 3. Clone the repository

```bash
git clone https://github.com/jannatshekue/translation.git
cd translation
```

### 4. Install the app's dependencies

From inside the project folder:

```bash
flutter pub get
```

This downloads all the packages the app needs. It can take a minute or two.

### 5. Enable Developer Options and USB debugging on your Android phone

This lets your computer install and run the app directly on your phone.

1. Open **Settings** on your phone → **About phone**.
2. Find **Build number** and tap it **7 times** in a row. You'll see a
   message saying "You are now a developer!"
3. Go back to **Settings** → you'll now see a new **Developer options**
   menu (sometimes under **System**).
4. Open **Developer options** and turn on **USB debugging**.
5. Connect your phone to your computer with a USB cable.
6. Your phone will show a popup asking "Allow USB debugging?" — tap
   **Allow** (and tick "always allow from this computer" if offered).

### 6. Confirm your phone is detected

```bash
flutter devices
```

You should see your phone listed. If you see nothing, see
[Troubleshooting](#troubleshooting) below.

You're now ready to run the app — see the next section.

## Running the app on your phone

With your phone connected (see setup step 5 above):

```bash
flutter run
```

This builds the app, installs it on your phone, and opens it automatically.
The first run can take several minutes; later runs are much faster.

While it's running, you can press `r` in the terminal to reload your latest
code changes instantly, or `q` to stop.

## Building a release APK

To produce a standalone install file (an `.apk`) that doesn't need
`flutter run` — useful for sharing the app or installing it without a
computer connected every time:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The resulting file is at `build/app/outputs/flutter-apk/app-release.apk` —
this is the file you'd share with someone else to let them install the app
directly (they'll need to allow "install unknown apps" for whichever app
they use to open the file, since this isn't distributed through the Play
Store).

Note: this single APK is large (~190MB) because it bundles native code for
every supported CPU architecture at once, including the OpenCV library used
by the sign classifier. For a smaller download when sharing directly, build
per-architecture APKs instead:

```bash
flutter build apk --release --split-per-abi
```

This produces three smaller files under
`build/app/outputs/flutter-apk/` (one each for `armeabi-v7a`, `arm64-v8a`,
and `x86_64`) — share whichever matches the recipient's phone (`arm64-v8a`
covers the vast majority of modern Android phones).

## Building for the Play Store (Android App Bundle)

The Play Store requires uploading an `.aab` (Android App Bundle) rather than
an APK. Unlike an APK, an `.aab` **cannot be installed directly on a
phone** — it only works as an upload to Google Play Console, which then
automatically generates and serves the right small package to each device
at install time (Google calls this "dynamic delivery").

```bash
flutter build appbundle --release
```

Produces `build/app/outputs/bundle/release/app-release.aab`. Publishing it
requires a one-time $25 Google Play Developer account registration fee —
not something to do without deciding on that cost first.

## Testing

```bash
flutter test
```

Covers the core recognition/translation logic (`HandPoseMatcher`,
`TranslationService`), the SQLite data layer (`DatabaseService`), and a
smoke test that the app launches through onboarding to the home screen.

## The ML training pipeline (`ml_training/`)

A separate Python toolchain (not part of the Flutter build, and not
something you need to touch just to run the app) that trains the ASL and
KSL sign classifiers bundled in `assets/models/`. Full details, including
where the training datasets come from and how to reproduce or extend the
models, are documented in [`ml_training/README.md`](ml_training/README.md).

In short: hand landmarks are extracted from labeled image/landmark datasets
using MediaPipe, a small classifier is trained on top of them with
TensorFlow, and the result is exported to a tiny `.tflite` file the app
loads on-device. Current bundled models:

| Model | Classes | Validation accuracy |
|---|---|---|
| ASL alphabet | A–Z, del, space (28) | 98.84% |
| KSL | father, hello, is, my (4) | 100%* |

\* KSL's dataset is small (4 words); treat that number as an upper bound
under ideal conditions, not a guarantee — see `ml_training/README.md` for
the full caveat and how to extend the vocabulary.

## Known limitations

- **iOS**: builds have not been tested (no Xcode/macOS environment used
  during development). All required `Info.plist` permission descriptions
  are in place, but the app has never actually been compiled or run on
  iOS, and Emergency Mode has no iOS equivalent (iOS blocks programmatic
  SMS sending).
- **Online speech-to-text**: only on-device recognition is implemented.
  Google Cloud Speech-to-Text (higher accuracy, optional) was considered
  but dropped to avoid requiring a billing account on file.
- **Custom Sign Creation accuracy**: uses a lightweight nearest-centroid
  matcher on normalized hand landmarks rather than a trained classifier —
  works well for a small number of distinct signs per user, not intended
  to scale to a large shared vocabulary. This is by design (instant,
  no retraining needed per new sign), not a bug.
- **KSL vocabulary**: only 4 words currently, due to the scarcity of
  free, licensed, labeled Kenyan Sign Language datasets. See
  `ml_training/README.md` for what was evaluated and why.
- **Not published to an app store yet**: an Android App Bundle builds
  successfully (see [Building for the Play Store](#building-for-the-play-store-android-app-bundle)),
  but nothing has been submitted — that requires deciding on the one-time
  $25 Google Play Developer fee first. Currently installed via `flutter run`
  or a manually-shared release APK.

## Troubleshooting

**`flutter devices` shows nothing / my phone isn't detected**
- Make sure USB debugging is enabled (setup step 5) and you tapped "Allow"
  on your phone's popup.
- Try a different USB cable — some cables are charge-only.
- Run `flutter doctor` and fix anything it flags.

**`flutter pub get` fails**
- Check your internet connection — it downloads packages from pub.dev.
- Make sure `flutter doctor` shows no unresolved errors first.

**The app crashes or a permission dialog loops**
- Make sure you tapped "Allow" (not "Deny") for camera/microphone/location/
  SMS permissions when the app asked. You can also grant them manually in
  your phone's Settings → Apps → Sign & Voice Translator → Permissions.

**Still stuck?**
Open an issue on this repository describing what you ran and the exact
error message — a screenshot of the terminal output is the most useful
thing you can include.
