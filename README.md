> *"And We have certainly made the Quran easy for remembrance, so is there any who will remember?"* — Al-Qamar 54:17

# ما أَسأَلُكُم عَلَيهِ مِن أَجرٍ إِن أَجرِيَ إِلّا عَلىٰ رَبِّ العالَمينَ

<br>
<div align="center">
  <a href="https://recitequran.pages.dev/">
    <img src="https://img.shields.io/badge/Download-For android-2ea44f?style=for-the-badge&logo=download" alt="Recite Quran Download" />
  </a>
</div>

<br>

before using any single character of codes here , you agree to this :
**For The Sake Of Allah only** if you used this app or the source code in any other work you aren't allowed to get from it any money or make profit from it and you have to mention that this app is for the sake of Allah only .
 (never sell or gain money from any work has any of this project )
 
(1) you may use and redistribute it ONLY in applications that are FREE to end users

(2) you are NOT allowed to sell it, place it behind a paid subscription or paywall, monetize it with ads, or earn any revenue from an app or service that uses this model or its outputs or this app or this codes or logics;

(3) these terms pass on to anyone you share it with.

---

<img width="139" height="292" alt="Screenshot_20260628-164337_Recite Quran" src="https://github.com/user-attachments/assets/42fc7e30-8a39-44bf-a4b9-9a3b48135e94" /><img width="139" height="292" alt="Screenshot_20260628-164253_Recite Quran" src="https://github.com/user-attachments/assets/357b58a4-3a84-4880-bce6-856c0092f211" /><img width="139" height="292" alt="Screenshot_20260628-164411_Recite Quran" src="https://github.com/user-attachments/assets/71bc8cb1-0c01-4eee-8053-3427fa0e0f99" /><img width="139" height="292" alt="Screenshot_20260628-164242_Recite Quran" src="https://github.com/user-attachments/assets/ce275229-65fd-435d-921e-de590eeecba6" />

---

## What Is This Project?

**ReciteQuran** is a Flutter mobile application that listens to a user reciting the Holy Quran, word by word, and highlights each word as **correct (green)**, **wrong (red)**, or **has a Tajweed error (yellow)**.

It runs **entirely on-device**, with no internet connection needed. An Arabic ASR (Automatic Speech Recognition) model runs live in the background, converting your voice into phonetic Arabic text in real-time.

---

## Table of Contents

1. [How the Architecture Works](#how-the-architecture-works)
2. [Data Files — The JSON Assets](#data-files--the-json-assets)
3. [The Audio Pipeline](#the-audio-pipeline)
4. [The ASR Engine (Sherpa-ONNX)](#the-asr-engine-sherpa-onnx)
5. [The Tracking Pipeline — Real-Time](#the-tracking-pipeline--real-time)
6. [Instant Tajweed Evaluation](#instant-tajweed-evaluation)
7. [Voice Navigation — "Recite to Find"](#voice-navigation--recite-to-find)
8. [The Phonetic Representation System](#the-phonetic-representation-system)
9. [Directory Structure](#directory-structure)

---

## How the Architecture Works

Think of it like an assembly line:

```
Microphone
    ↓
AudioProcessor (Silero VAD — speech detection + chunking)
    ↓
SherpaEngine (Isolate — ONNX model inference)
    ↓
HighlightingController (Manages state and orchestrates audio flow)
    ↓
PhonemeAlignmentIsolate (Manages continuous ASR text and timestamps)
    ↓
ForwardDictationMatcher (Mathematical DP core calculating precise alignments)
    ↓
UI (TrackingScreen → VerseRow → word highlighting)
```

Each step operates asynchronously. The heavy mathematical computations run inside background Isolates, guaranteeing the UI never drops frames.

### Real-Time Word Highlighting & Tajweed
As you speak each word, the `ForwardDictationMatcher` calculates the precise mathematical distance between the sounds you made and the target Arabic word. Based on the Levenshtein-like distance, words are instantly assigned:
- **Green** → you said it correctly.
- **Red** → you skipped or mispronounced it entirely.
- **Yellow** → you said it correctly but violated a Tajweed rule (e.g., missed a Ghunnah, or mispronounced a Madd).

---

## Data Files — The JSON Assets

### `assets/model/ordered_quran_phonemes.json`

**~8.6 MB.** The most important file in the entire project. Contains **all 6,236 Ayahs** of the Quran in this schema:

```json
"6:137": {
    "aya_text": "وَكَذَٰلِكَ زَيَّنَ ...",
    "aya_phoneme": "وَكَذَاالِكَزَييَنَلِكَثِۦۦرِم...",
    "aya_ui": "  invisible Unicode word-boundary markers  ",
    "aya_phonemes_list": [
        "وَكَذَاالِكَ",
        "زَييَنَ",
        "لِكَثِۦۦرِ",
        ...
    ]
}
```

| Field | What it is |
|---|---|
| `aya_text` | The official Uthmani Hafs script shown in the UI |
| `aya_phoneme` | **CTC model output format** — what the ASR model actually outputs when it hears this Ayah. It is length-encoded phonetic text. |
| `aya_ui` | Special Unicode characters that encode word boundaries for the Uthmani display text. |
| `aya_phonemes_list` | `aya_phoneme` pre-split into one string per word. |

### `assets/model/ph_index.txt` & `assets/model/ph_index.npy`

These files power the Voice Navigation feature.
- **`ph_index.txt` (~350 KB):** A continuous string of the bare phonetic characters for the entire Quran.
- **`ph_index.npy` (~2.4 MB):** A binary NumPy array mapping every character index back to its exact `(Surah, Ayah, Word)`.

---

## The Audio Pipeline

**File:** `lib/audio/audio_processor.dart`

The `AudioProcessor` captures PCM 16-bit, 16kHz mono audio. To efficiently detect when you are speaking, it uses **Silero VAD** (a fast, lightweight ONNX Voice Activity Detection neural network) rather than primitive amplitude tracking. 

When you start speaking, it chunks audio into perfectly sized 160ms arrays and ships them to the ASR model. Raw PCM audio is passed to ensure no artificial volume distortions destroy the Mel-spectrogram energy contours that the ASR relies on.

---

## The ASR Engine (Sherpa-ONNX)

**File:** `lib/engine/sherpa_engine.dart`

Sherpa-ONNX runs the `zipformer_p_arabic_v3.int8.onnx` model inside a **Dart Isolate**. 

### Length-Aware Phonetic Encoding
The advanced Zipformer model is trained to be **Tajweed and Madd aware**. It does NOT output clean text. It outputs frame-level phonetic alignments where **time duration is encoded as repeated characters**. 

If you speak `بِسمِ` slowly and hold the Madd, the model outputs raw frames like:
```
Raw output: "بسسسممللااهرررحمننرحييم"
```
Our DP matching algorithm expects these duplicates, allowing it to mathematically verify that you held a Madd or a Ghunnah for the correct length of time!

---

## The Tracking Pipeline — Real-Time

### `lib/tracking/word/phoneme_alignment_isolate.dart`
This isolate handles continuous streaming of new text from the ASR. It intelligently merges chunks, detects backtracking/corrections from the ASR, and distributes phonetic durations across the text characters.

### `lib/tracking/word/dictation_matcher.dart`
The **ForwardDictationMatcher** is the mathematical core of the engine. It uses a highly optimized Dynamic Programming algorithm (a variant of Smith-Waterman/Levenshtein) to align the noisy ASR text against the reference Quran text.

Key optimizations:
- **O(N) Memory footprint:** Uses a "Rolling Rows" technique instead of a massive 2D matrix.
- **Targeted Substring Matching:** Rejects early-commit errors on held Madds (the Edge-Bound Tail Stability Rule).
- **Phoneme Matrix Penalties:** Looks up substitution costs dynamically from `PhonemeMatrix`. Emphatic pairs cost less to swap than completely disjoint letters.
- **1-Byte Traceback:** Constructs a highly compressed 1-byte matrix mapping exact insertions, deletions, and substitutions to feed into the Tajweed engine.

---

## Instant Tajweed Evaluation

**File:** `lib/tracking/tajweed/error_explainer.dart`

Tajweed evaluation happens **instantly** per-word. As soon as `ForwardDictationMatcher` successfully mathematically aligns a word, the precise traceback path is passed to `ErrorExplainer`. 

The explainer looks at the exact edits required to align the ASR to the reference:
- Was an emphatic letter (Tafkheem) whispered?
- Was a Qalqalah missing?
- Did the user hold a Madd/Ghunnah for too short a time? (Detected via character length mismatch)
- Were the wrong Harakat used?

If an error is found, the word instantly highlights **Yellow**, and the error type is registered.

---

## Voice Navigation — "Recite to Find"

**Files:** `lib/tracking/ayah_search/`

Press the record button on the Surah Selection screen and recite any verse. The app will automatically navigate to that Surah and Ayah.
It uses a highly optimized **Levenshtein Fuzzy Search** over the `ph_index.txt` to find the closest match. It allows up to a 10% error margin to handle noisy environments and minor stuttering elegantly.

---

## The Phonetic Representation System

This project uses a custom phonetic encoding specifically matched to the Arabic ASR model's output vocabulary.

| Character | Meaning |
|---|---|
| ا | Short alef sound (or extended vowel) |
| و | Waw vowel |
| ي | Ya vowel |
| ۥ | Small waw (used for diphthong/madd ending) |
| ۦ | Small ya (used for diphthong/madd ending) |
| Repeated chars | Length encoding. `ییی` = longer "ee" sound than `ی` |

---

## Directory Structure

```
lib/
├── main.dart                          # App entry point
├── audio/
│   └── audio_processor.dart           # Microphone + Silero VAD + chunking
├── data/
│   └── quran_data.dart                # JSON parsing and dataset access
├── engine/
│   └── sherpa_engine.dart             # Sherpa-ONNX ASR (Dart Isolate)
├── state/
│   └── app_state.dart                 # Persistent app settings
├── tracking/
│   ├── ayah_search/                   # "Recite to find" feature
│   │   ├── fuzzy_search.dart
│   │   ├── phonetic_search.dart
│   │   └── voice_search_controller.dart
│   ├── tajweed/
│   │   ├── error_explainer.dart       # Instant Tajweed violation detection
│   │   └── tajweed_rules.dart
│   └── word/
│       ├── dictation_matcher.dart     # DP Math Engine (Levenshtein alignment)
│       ├── highlighting_controller.dart # Bridging ASR and isolate logic
│       ├── phoneme_alignment_isolate.dart # Text stream/tail stability logic
│       ├── phoneme_matrix.dart        # Acoustic similarity scoring
│       └── quran_normalizer.dart      # Standardizes Arabic text
├── ui/
│   ├── tracking_screen.dart
│   └── widgets/
assets/
├── model/                             # Core dataset, ONNX ASR, VAD, and Numpy
```

---

## Reference Repositories
Elhamdule Allah
This project is built on research and code from the following open-source projects:

| Project | Author / Source |
|---|---|
| [Quran-streaming-model](https://huggingface.co/Muno459/zipformer_p-arabic-v2) | Muno459 |
| [quran-transcript](https://github.com/OmarMuhammedAli/quran-transcript) | obadx |
| [qua_sdk](https://huggingface.co/spaces/hetchyy/quranic-universal-aligner) | Hetchy |

# هذا من فضل ربي - ربنا تقبل منا انك ان السميع العليم
