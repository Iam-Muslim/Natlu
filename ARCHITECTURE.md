# ReciteQuran — System Architecture & AI Knowledge Base

> **AI Reader Guide**: This document provides a complete technical roadmap of the ReciteQuran real-time Quranic recitation tracking and Tajweed diagnosis engine. Read this before modifying any tracking, speech recognition, or alignment logic.

---

## 1. System Pipeline Overview

```
[ MICROPHONE ]
      │ (16kHz PCM audio stream)
      ▼
[ AudioProcessor ] (lib/audio/audio_processor.dart)
      │ • Bypasses OS noise cancellation (preserves Arabic breathy letters like "هـ")
      │ • Software AGC + Tanh soft limiter (avoids digital clipping)
      │ • Emits 480ms Float32 audio chunks
      ▼
[ SherpaEngine ] (lib/engine/sherpa_engine.dart)
      │ • Background Isolate running Zipformer2 Causal Streaming CTC model
      │ • Emits: TranscriptionResult(tokens, timestamps, ysProbs [log probabilities])
      ▼
[ HighlightingController ] (lib/tracking/word/highlighting_controller.dart)
      │ • Main UI Thread state manager & bridge
      │ • Receives ASR stream and syncs to PhonemeAlignmentIsolate via IsolateCommand
      ▼
[ PhonemeAlignmentIsolate ] (lib/tracking/word/phoneme_alignment_isolate.dart)
      │ • Background Isolate managing unconsumed audio buffers
      │ • Slices strict monotonic single-word target windows from reference Surah
      ▼
[ ForwardDictationMatcher ] (lib/tracking/word/dictation_matcher.dart)
      │ • Monotonic Viterbi / Levenshtein Trellis over integer phoneme IDs
      │ • Complexity: O(M * N) time, O(N) space (zero heap allocations in hot loop)
      │ • Returns: AlignmentResult(score, Levenshtein trace, verifiedWords)
      ▼
[ ErrorExplainer ] (lib/tracking/tajweed/error_explainer.dart)
      │ • Evaluates phonetic trace against length-encoded Tajweed rules
      │ • Classifies errors: ErrorCategory.tajweed, normal, tashkeel
      ▼
[ HighlightingController ➔ UI ] (lib/ui/tracking_screen.dart & widgets/verse_row.dart)
      • Highlights word: Green (correct), Yellow (tashkeel / tajweed minor), Red (wrong / skipped)
      • Shows interactive error explanation dialog on user tap
```

---

## 2. Key Directories & File Responsibilities

| File Path | Role & Architectural Responsibility | Key Invariants & Rules |
| :--- | :--- | :--- |
| `lib/audio/audio_processor.dart` | Captures raw audio, applies AGC and soft limiting. | Never enable OS hardware echo cancellation or noise suppression. |
| `lib/engine/sherpa_engine.dart` | Wraps ONNX Zipformer streaming CTC model in an isolate. | Passes `ysProbs` (acoustic confidence) downstream for ASR fault mitigation. |
| `lib/tracking/word/dictation_matcher.dart` | Pure mathematical DP alignment trellis. | **Zero UI/State logic**. Must be pure math. Zero heap allocations per frame. |
| `lib/tracking/word/phoneme_matrix.dart` | Substitution cost matrix between Arabic phonemes. | Pre-computes $O(1)$ integer penalty lookup table. |
| `lib/tracking/word/phoneme_alignment_isolate.dart` | Background thread orchestrator. | Enforces monotonic forward movement. Never jump backward. |
| `lib/tracking/word/models/alignment_models.dart` | Strongly typed domain models for DP. | Defines `AlignmentOp`, `AlignmentConfig`, `AlignmentResult`. |
| `lib/tracking/word/models/isolate_protocol.dart` | Sealed Dart 3 isolate communication protocol. | `IsolateCommand` (UI ➔ Isolate), `IsolateEvent` (Isolate ➔ UI). |
| `lib/tracking/tajweed/tajweed_rules.dart` | Rule definitions (Madd, Ghunnah, Qalqalah, Shaddah). | Uses character length encoding (e.g. length 2 = 2 beats, length >= 4 = 4 beats). |
| `lib/tracking/tajweed/error_explainer.dart` | Multi-phase error categorizer. | Evaluates base letters first, then tashkeel, then duration. |
| `lib/tracking/ayah_search/phonetic_search.dart` | Fast verse locator using pre-compiled NPY index. | Searches global Quranic phonetic text via isolated worker. |
| `lib/tracking/word/highlighting_controller.dart` | UI state coordinator. | Manages active Ayah, word status maps, and error mappings. |

---

## 3. The Length Protocol Dictionary (Tajweed Encoding)

The app encodes Tajweed duration rules directly into phoneme string lengths in `ordered_quran_phonemes.json`:

1. **QALQALAH (Bounce)**: Contains `ڇ` marker (e.g. `بڇ`). Reciter must not hold the letter.
2. **MADD (Prolongation)**: Base character `ا`, `ۥ`, or `ۦ`.
   - Length 2–3: `NormalMaddRule` (2 beats / ~0.40s)
   - Length 4–5: `Monfasel`/`Mottasel`/`Aared` Madd (4 beats / ~0.80s)
   - Length 6+: `LazemMaddRule` (6 beats / ~1.20s)
3. **GHUNNAH (Nasalization)**: Nasal letters (`ن`, `م`, `ں`, `۾`, `ي`, `و`) with length $\ge 3$. Expects $\approx 0.80\text{s}$ nasal hold.
4. **SHADDAH (Doubling)**: Any doubled consonant with length $= 2$ (e.g. `رر`, `بب`). Expects $\approx 0.40\text{s}$ closure.
5. **NORMAL**: Single consonant (length $= 1$). No duration checking.

---

## 4. Alignment Engine Constraints & Math

- **Algorithm**: Monotonic forward-only Smith-Waterman / Levenshtein variant.
- **Complexity**: $O(M \cdot N)$ where $M$ is unconsumed ASR chunk count and $N$ is target word phoneme count.
- **Memory**: $O(N)$ flat typed buffers (`Float64List`, `Int32List`, `Uint8List`).
- **Acoustic Shielding**: If a word fails strictness but Sherpa log-probability shows low acoustic confidence ($\min < 80\%$), the word is shielded from turning red to protect against cheap microphone distortion.
