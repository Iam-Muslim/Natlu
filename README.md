<div align="center">

# وما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ


# Natlu — نتلو



<p align="center">
  <img height="280" src="docs/screenshots/5-ar.png" alt="ReciteQuran Preview" /><img height="280" src="docs/screenshots/1-ar.png" alt="ReciteQuran Preview" /><img height="280" src="docs/screenshots/2-ar.png" alt="ReciteQuran Preview" /><img height="280" src="docs/screenshots/3-ar.png" alt="ReciteQuran Preview" /><img height="280" src="docs/screenshots/4-ar.png" alt="ReciteQuran Preview" />
</p>

</div>

---
<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.recitequran.app" target="_blank">
    <img src="docs/badges/google_play.svg" height="45" alt="Get it on Google Play" />
  </a>
  &nbsp;&nbsp;
  <a href="https://apps.apple.com/app/id6806614841" target="_blank">
    <img src="docs/badges/app_store.svg" height="45" alt="Download on the App Store" />
  </a>
  &nbsp;&nbsp;
  <a href="https://recitequran.pages.dev/recite" target="_blank">
    <img src="docs/badges/web_app.svg" height="45" alt="Web App" />
  </a>
  &nbsp;&nbsp;
  <a href="https://recitequran.pages.dev/" target="_blank">
    <img src="docs/badges/official_site.svg" height="45" alt="Official Website" />
  </a>
</p>
<br>

## Overview

**Natlu** is an open-source, on-device AI assistant designed to listen to your Quran recitation in real time, guide your pronunciation word-by-word, and verify acoustic Tajweed durations with millisecond precision.
---

## Platforms

-  Android
-  Web Browser
-  iOS (iPhone & iPad)
-  Windows (Desktop)
-  Linux - Insha'a Allah



## Features

### 1. Real-Time Word Tracking
- High-speed acoustic tracking follows your speech word by word.
- **Visual Feedback**:
  - **Green**: Correct recitation (Consonants and Harakat match).
  - **Red**: Word skipped, substituted, or mispronounced.
  - **Yellow**: Tajweed Mistake . 

---

### 2. Acoustic Tajweed & Madd Engine
- Evaluates acoustic vowel holding durations against Quranic Tadweer timing standards:
  - **Madd Elongation (المدود)**
  - **Mushaddad Ghunnah (غنة النون والميم المشددتين)**
  - **Shaddah (الشدة)**
- Tap any highlighted word to inspect expected versus recited duration in milliseconds.

---

### 3. Instant Voice Ayah Search
- The offline phonetic matcher locates the verse and jumps directly to it .
---

### 4. Hifz Revision & Hide Mode
- Words reveal themselves as you recite them correctly.
---


## Developer Guide

### Repository Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Iam-Muslim/Natlu.git
   cd Natlu
   ```

2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```

3. Download the quantized ONNX neural model:
   ```bash
   pip install -U "huggingface_hub[cli]"
   hf download Quran-Lab/zipformer_p-arabic-v3 zipformer_p_arabic_v3.int8.onnx --local-dir assets/model
   ```

---

### Running on Android

```bash
flutter run -d android
flutter build apk --release --split-per-abi
```

---

### Running on iOS

```bash
cd ios
pod install
cd ..
flutter run -d ios
```

---

### Running on Windows

```bash
flutter run -d windows
```

---

### Running on Web

```bash
flutter run -d chrome
```

---

### Architecture

```
lib/
├── audio/                     # 16 kHz PCM chunk capture and buffering
│   └── audio_processor.dart
├── data/                      # Quranic text dataset and rule definitions
│   └── quran_data.dart
├── engine/                    # Streaming Zipformer inference in background Isolate
│   ├── models/                # Inter-isolate communication protocols
│   └── sherpa_engine.dart
├── state/                     # Global settings and theme management
│   └── app_state.dart
├── tracking/
│   ├── ayah_search/           # Offline phonetic verse search
│   ├── tajweed/               # Tajweed duration validator and explainer
│   │   ├── error_explainer.dart
│   │   └── tajweed_rules.dart
│   └── word/                  # Real-time phoneme alignment and highlight sequencing
│       ├── dictation_matcher.dart
│       ├── dictation_sequencer.dart
│       ├── highlighting_controller.dart
│       └── phoneme_alignment_isolate.dart
├── ui/                        # UI screens, dialogs, and Mushaf view
│   ├── tracking_screen.dart
│   └── widgets/
└── utils/                     # Logging and debug helpers
    └── debug_logger.dart
```

---

## (لوجه الله تعالى)

### **ما أسألكم عليه من أجر إن أجري إلا على رب العالمين**

> **THIS APPLICATION AND SOURCE CODE ARE FOR THE SAKE OF ALLAH ALONE.**

Before viewing, using, distributing, or modifying any part of this repository, you explicitly agree to the following sacred covenants:

1. **100% Free to End Users**:
   You may use, study, and redistribute this software or its logic **ONLY** in applications and services that are completely free of charge to all end users forever.
2. **Strict Prohibition on Commercialization & Profit**:
   You are **STRICTLY FORBIDDEN** from selling this application, placing it behind paywalls, subscription models, in-app purchases, charging download fees, monetizing it with advertisements (AdMob, Unity Ads, etc.), or extracting any financial revenue from this codebase, models, or outputs.
3. **Perpetual Waqf Pass-Through**:
   These terms are immutable and strictly pass on to any fork, derivative work, or redistributed component.

---

*Alhamdulillah (الحمد لله رب العالمين)* — This project builds on research and work from the following open-source projects:

- **[Zipformer Quran Streaming Model](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)** by Brother - Mustafa 
- **[quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript)** by Brother - Abdullah Aml
- **[Quranic Universal Aligner (qua_sdk)](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner)** by Brother - Ahmad Ibrahim

---

<div align="center">

**هذا من فضل ربي — ربنا تقبل منا إنك أنت السميع العليم**

</div>
