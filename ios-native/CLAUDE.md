# ReciteQuran — Native iOS (SwiftUI)

## What this is

A **native SwiftUI implementation** of ReciteQuran — a **real-time Quran recitation tracker**
that runs **fully on-device, with no internet**. The user picks a surah/ayah and taps the mic;
as they recite, each word highlights **green** (correct), **red** (wrong/skipped), or **yellow**
(Tajweed mistake), auto-advancing verse to verse. It also supports "recite to find any ayah"
voice search.

This folder is a **self-contained Xcode project** that lives alongside the Flutter app in this
repo. It shares no code or build steps with the Flutter app — the two are independent
implementations of the same product. The Flutter source (`../lib/`) and the architecture docs
(`../docs/`) describe the same algorithms and remain the behavioral reference.

> Under the hood this is a C++ speech library (`sherpa-onnx`) plus a set of pure string
> algorithms. The UI layer is thin; the substance is in the phoneme aligner, the Tajweed pass,
> and the voice-search index.

---

## Building it

Two sets of large binary assets are **deliberately not committed** — a 178 MB set of prebuilt
XCFrameworks and a 69 MB license-gated ASR model. Fetch them first:

```sh
./scripts/fetch-vendor-assets.sh
```

Then open `ReciteQuran-iOS-Native.xcodeproj` and build. **See [SETUP.md](SETUP.md)** for the
full story, including the manual Hugging Face step for the gated model.

- **iOS 17.0**, Swift 5.0, bundle id `com.iphoneislam.ReciteQuran-iOS-Native`.
- No `DEVELOPMENT_TEAM` is committed — set your own team in Signing & Capabilities.
- The app target is a **file-system-synchronized group** (`objectVersion = 110`): any file
  placed under `ReciteQuran-iOS-Native/` is added to the target automatically. **You never need
  to edit the pbxproj to add a source file or resource.**

---

## Layout

```
ios-native/
├── CLAUDE.md                        ← this file
├── SETUP.md                         ← how to fetch the uncommitted binary assets
├── scripts/fetch-vendor-assets.sh   ← does that fetching, checksum-verified
├── LocalSherpaOnnx/                 ← local SwiftPM package wrapping sherpa-onnx
│   ├── Package.swift                  binary targets → XCFrameworks/ (not committed)
│   └── Sources/SherpaOnnx/            the upstream Swift wrapper (see the Vendor gotcha below)
├── ReciteQuran-iOS-Native.xcodeproj
└── ReciteQuran-iOS-Native/          ← APP TARGET (synchronized group)
    ├── ReciteQuran_iOS_NativeApp.swift, ContentView.swift
    ├── Audio/        mic capture, VAD chunking, audio-session config
    ├── Engine/       sherpa-onnx recognizer actor + result types
    ├── Tracking/     normalizer, phoneme aligner, Tajweed/
    ├── Search/       voice search (phonetic + fuzzy) over the whole-Quran index
    ├── Data/         ordered_quran_phonemes.json → verse models
    ├── State/        settings, theme, localization
    ├── ViewModels/   coordinator + tracking view model
    ├── UI/           SwiftUI views (verse rows, mic bar, pickers, sheets)
    ├── Support/      bundle lookup, font registration, diagnostics, self-test
    ├── Vendor/       SherpaOnnxAPI.swift — required; see gotchas
    └── Resources/
        ├── Models/   ASR + data assets (the 69 MB model is not committed)
        └── Fonts/    HafsSmart_08.ttf
```

### Where things live

| Concern | Swift | Dart counterpart (`../lib/`) |
|---|---|---|
| Streaming CTC recognizer, wrapped in an `actor` | `Engine/SherpaEngine.swift` | `engine/sherpa_engine.dart` (a Dart isolate) |
| Mic capture, Silero VAD, pre-roll, endpointing | `Audio/AudioProcessor.swift` | `audio/audio_processor.dart` |
| iOS audio-session setup | `Audio/AudioSessionConfigurator.swift` | `main.dart` (via `audio_session`) |
| Arabic normalization + phoneme chunking | `Tracking/QuranNormalizer.swift` | `tracking/word/quran_normalizer.dart` |
| **The core matcher** — Wagner-Fischer DP + sliding window | `Tracking/PhonemeAligner.swift` | `tracking/word/phoneme_alignment_isolate.dart` |
| Tajweed rules + explanations | `Tracking/Tajweed/*.swift` | `tracking/tajweed/*.dart` |
| Voice search over the phonetic index | `Search/*.swift` | `tracking/ayah_search/*.dart` |
| Verse data loading | `Data/QuranData.swift` | `data/quran_data.dart` |
| Settings, theme palette | `State/AppState.swift` | `state/app_state.dart` |
| ASR → aligner → UI orchestration, auto-advance | `ViewModels/TrackingViewModel.swift`, `RecitationCoordinator.swift` | `tracking/word/highlighting_controller.dart` |

---

## How it works

```
Mic (16 kHz mono Float32)
  → Silero VAD (endpointing + madd protection)          [sherpa-onnx]
  → Zipformer2-CTC phoneme ASR (streaming)              [sherpa-onnx]
  → continuous phoneme string  "بِسمِللَاهِ..."   (NO spaces, NO word boundaries)
  → Phoneme aligner (Wagner-Fischer sliding window)
  → per-word green/red highlight + auto-advance
  → (Tajweed mode) strict char-by-char ErrorExplainer → yellow words + explanations
```

**The core insight** (see `../docs/phonetic_matching_architecture.md`): the ASR emits a
*space-less stream of phonemes*, not words. Matching is a **forgiving real-time Levenshtein
sliding window** that tolerates stutters, hallucinations, and madd-length variation. A
**separate strict Tajweed pass** runs afterward over the raw buffer. That separation of duties
is deliberate — the forgiving pass drives the UI, the strict pass drives the diagnostics.

Voice search is a fully **isolated** path: accumulate ASR phonemes → normalize → fuzzy
Levenshtein over `ref_norm_ph.txt` → map the winning span back through `ph_index.npy` → jump to
that ayah. See `../docs/voice_navigation.md`.

---

## Asset inventory

All under `ReciteQuran-iOS-Native/Resources/`. Loaded via `BundleResources` — the synchronized
group flattens them into the bundle, so the subfolder path doesn't matter for lookup.

| File | Size | Purpose | Committed? |
|---|---|---|---|
| `Models/quran_phoneme_zipformer.int8.onnx` | 69 MB | **Streaming phoneme ASR model** (Zipformer2-CTC, int8). Emits a space-less phoneme stream. | ❌ fetched |
| `Models/tokens.txt` | 2.3 KB | ASR token vocabulary for the model above | ✅ |
| `Models/silero_vad.onnx` | 2.2 MB | Silero voice-activity detection — endpointing + madd protection | ✅ |
| `Models/ordered_quran_phonemes.json` | 8.1 MB | Per-verse Uthmani text (`aya_ui`), phoneme string (`aya_phoneme`), per-word phonemes | ✅ |
| `Models/ph_index.npy` | 4.2 MB | Binary index: char → (surah, ayah, word, char), for voice search | ✅ |
| `Models/ref_norm_ph.txt` | 609 KB | Whole Quran as one normalized phonetic string — the voice-search haystack | ✅ |
| `Fonts/HafsSmart_08.ttf` | 294 KB | Mushaf display font, registered at runtime by `FontRegistrar` | ✅ |

`ordered_quran_phonemes.json`, `ph_index.npy`, `ref_norm_ph.txt`, and `tokens.txt` are
byte-identical to the Flutter app's `../assets/model/`. `silero_vad.onnx` is bundled only here —
the Flutter app no longer tracks it in `assets/model/`.

> [!IMPORTANT]
> The ASR model is a **gated** Hugging Face download (`Muno459/zipformer_p-quran`) under a
> **custom license restricting commercial use**. Check its LICENSE before shipping or
> monetizing. Expected: 72,705,392 bytes, valid ONNX protobuf, producer `onnx.quantize`.

---

## sherpa-onnx configuration — these exact values matter

These are tuned for this specific model and for recitation rather than conversational speech.
Treat them as calibrated constants, not defaults to tidy up.

**Recognizer (Zipformer2-CTC)** — `Engine/SherpaEngine.swift`
- feature: `sampleRate: 16000`, `featureDim: 80`
- `numThreads: 1`, `modelType: "zipformer2_ctc"`, `provider: "cpu"`
  — CoreML struggles with this int8 model; CPU is stable and fast.
- `enableEndpoint: false` (endpoints are driven externally by Silero VAD),
  `rule1MinTrailingSilence: 2.4`
- Feed Float32 samples in [-1, 1] (int16 / 32768, gain 1.0). Loop `isReady` → `decode`, read
  `getResult()`. On final: `inputFinished`, then prime with ~300 ms (4800 samples) of silence —
  this is what fixes the "missing first word" bug.

**VAD (Silero)** — `Audio/AudioProcessor.swift`
- `threshold: 0.1` — lowered from the usual 0.5 so long vowels and madd stay classified as speech
- `minSilenceDuration: 0.1`, `minSpeechDuration: 0.15`, `maxSpeechDuration: 1000.0`
- `sampleRate: 16000`, `numThreads: 1`, `bufferSizeInSeconds: 10.0`

**Capture cadence:** fixed **320 ms** blocks (matches the model's `chunk_size=8`), with a
**640 ms pre-roll** (2×320) so consonant attacks aren't clipped. Silence endpoint at **2500 ms**.

**Audio session:** `playAndRecord`, mode **`.measurement`**, options
`defaultToSpeaker | allowBluetooth`. `.measurement` disables Apple's voice-processing DSP, which
otherwise mangles recognition. This is critical for accuracy, not a stylistic choice.

---

## Gotchas / decisions already made

- **`Vendor/SherpaOnnxAPI.swift` is required — do not "deduplicate" it.** It looks like a
  verbatim copy of `LocalSherpaOnnx/Sources/SherpaOnnx/SherpaOnnx.swift` (the two differ by one
  line: the import). It exists because the upstream package declares **zero `public` symbols**,
  so none of its Swift wrappers are visible outside the package module. The app re-declares them
  in its own module and consumes the C API that the package `@_exported import`s. Deleting this
  file breaks the build. The alternative — making the package's declarations `public` — means
  patching 1500+ lines of vendored upstream code on every version bump.
- **Output is PHONEMES, not text.** The matching, Tajweed, and voice-search layers are tuned to
  this model's phoneme vocabulary (zero-cost pairs, qalqalah `ڇ`, madd characters). Swapping in
  a text-output ASR model is a core rewrite, not a config change.
- **Keep `provider: "cpu"`** for the recognizer (int8 + CoreML = trouble).
- **Never run the DP aligner on the main thread** — it lives on a background actor, mirroring
  the Dart isolate.
- **Chunk sizing and `.measurement`** are deliberate accuracy choices. Replicate, don't
  "improve."
- **The XCFrameworks are vendored via a local SwiftPM `.binaryTarget(path:)`**, not a remote
  package — the build stays fully offline. `fetch-vendor-assets.sh` also strips onnxruntime's
  headers (their `module.modulemap` collides with sherpa-onnx's) and prunes the macOS slices.
- **iOS 17 / Swift 5** as set, so `@Observable` and friends are available.

---

## Further reading

The architecture docs in `../docs/` describe the algorithms this app implements:

1. `../docs/phonetic_matching_architecture.md` — the matching engine. **Read before touching
   `PhonemeAligner.swift`.**
2. `../docs/voice_navigation.md` — voice search.
3. `../docs/tajweed_error_analysis.md` — Tajweed checking.
4. `../lib/` — the Flutter implementation, useful as a behavioral cross-reference.
