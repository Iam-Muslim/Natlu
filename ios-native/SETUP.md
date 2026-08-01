# Setup — Native iOS build

This folder is a standalone Xcode project. Two sets of large binary assets are
**intentionally not committed** and must be fetched locally before the first build.

```sh
./ios-native/scripts/fetch-vendor-assets.sh
```

The script is safe to re-run — it skips anything already present and checksum-verified.

---

## What the script fetches

### 1. sherpa-onnx / onnxruntime XCFrameworks (~178 MB) — automatic

Prebuilt static libraries for the ASR engine, pulled from
[`willwade/sherpa-onnx-spm`](https://github.com/willwade/sherpa-onnx-spm) **1.13.2**
and unpacked into `LocalSherpaOnnx/XCFrameworks/`.

The script applies two fixes to the stock archives:

- **Removes `onnxruntime`'s headers** (and its `HeadersPath` keys). They ship an
  `include/module.modulemap` that collides with sherpa-onnx's during the build.
  onnxruntime's symbols are consumed only through sherpa-onnx's C API, so its
  headers are unnecessary.
- **Prunes the macOS slices.** The package targets iOS only; keeping them roughly
  triples the on-disk size.

### 2. Zipformer2-CTC phoneme ASR model (69 MB) — manual, license-gated

`ReciteQuran-iOS-Native/Resources/Models/zipformer_p_arabic_v2.int8.onnx`

> [!IMPORTANT]
> This is a **gated** Hugging Face download under a **custom license that restricts
> commercial use**. Read the LICENSE on the model repo before shipping or monetizing.

1. Sign in and accept the license at
   [`Muno459/zipformer_p-arabic-v2`](https://huggingface.co/Muno459/zipformer_p-arabic-v2).
2. Download `zipformer_p_arabic_v2.int8.onnx` into
   `ReciteQuran-iOS-Native/Resources/Models/`.

   With the Hugging Face CLI (`hf auth login`):

   ```sh
   hf download Muno459/zipformer_p-arabic-v2 \
     zipformer_p_arabic_v2.int8.onnx \
     --local-dir ios-native/ReciteQuran-iOS-Native/Resources/Models
   ```

3. Re-run the script to verify it (expects 72,705,392 bytes,
   sha256 `dfe997f7…23d62b`).

The parent Flutter app excludes its own copy of this same model for the same reason
— see `assets/model/` in the repo root `.gitignore`.

---

## Then

Open `ReciteQuran-iOS-Native.xcodeproj` and build. The app target is a
**file-system-synchronized group**, so any file added under
`ReciteQuran-iOS-Native/` is picked up automatically without editing the project file.

### Code signing

The project has a `DEVELOPMENT_TEAM` baked in. Set it to your own team in
**Signing & Capabilities**, or override it without dirtying the project file:

```sh
xcodebuild -project ReciteQuran-iOS-Native.xcodeproj \
           -scheme ReciteQuran-iOS-Native \
           DEVELOPMENT_TEAM=YOURTEAMID
```

---

## What *is* committed

The smaller data assets stay in git so the project remains self-contained:

| File | Size | Purpose |
|---|---|---|
| `ordered_quran_phonemes.json` | 8.1 MB | Per-verse Uthmani text + phoneme strings |
| `ph_index.npy` | 4.2 MB | Char → (surah, ayah, word, char) index for voice search |
| `ref_norm_ph.txt` | 609 KB | Whole Quran as one normalized phonetic string |
| `silero_vad.onnx` | 2.2 MB | Silero voice-activity detection |
| `tokens.txt` | 2.3 KB | ASR token vocabulary |
| `Resources/Fonts/HafsSmart_08.ttf` | 294 KB | Mushaf display font |

All but `silero_vad.onnx` are byte-identical to the parent app's `assets/model/`, which already
tracks them. `silero_vad.onnx` is bundled only here — the Flutter app no longer tracks its copy.
