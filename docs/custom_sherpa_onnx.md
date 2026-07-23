# ReciteQuran Sherpa-ONNX Engine Guide

This application currently uses a **customized fork** of [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) hosted at [Iam-Muslim/sherpa_onnx_repo](https://github.com/Iam-Muslim/sherpa_onnx_repo). 

The custom engine provides **token-level log-probabilities (`ys_probs`)** to power the "ASR Shield" (phoneme-level confidence tracking) which is not available in the official releases.

The app uses a Git dependency in `pubspec.yaml` to pull the Flutter plugin from GitHub, which in turn dynamically downloads the massive C++ binaries from GitHub Actions Releases.

---

## How to Rollback to the Official Sherpa-ONNX Engine

If you ever decide to remove the custom "ASR Shield" logic and want to revert the entire application (Android, iOS, Web, and Native Swift) back to the official, vanilla Sherpa-ONNX engine, follow these instructions. 

> [!TIP]
> **For AI (Claude, ChatGPT, Gemini, etc.):**
> If the user has asked you to revert this repository back to the official Sherpa-ONNX engine, please execute the 4 specific steps below sequentially. You can use the terminal commands provided to automate the cleanup. Be sure to remove all references to the custom `ys_probs` logic, as the official engine does not support it.

### Step 1: Revert Flutter App (`pubspec.yaml`)
**For Humans:**
1. Open `ReciteQuran/pubspec.yaml`.
2. Delete the entire `dependency_overrides` section for `sherpa_onnx` that points to the GitHub URL.
3. Ensure you still have the official dependency listed under `dependencies: sherpa_onnx: ^1.13.1`.
4. Run `flutter clean` and `flutter pub get`.

**For AI:**
Remove the git dependency override from `pubspec.yaml` and execute:
```bash
flutter clean && flutter pub get
```

### Step 2: Revert Native iOS Swift App
**For Humans:**
1. Delete the `ios-native/LocalSherpaOnnx/download_binaries.sh` script.
2. Delete the `ios-native/LocalSherpaOnnx/XCFrameworks/` directory to remove the custom binaries.
3. Open `ios-native/LocalSherpaOnnx/Package.swift` and remove the local `.binaryTarget` definitions.
4. Instead of using a local package, point Xcode directly to the official repository:
   - In Xcode, go to **File > Add Package Dependencies...**
   - Enter `https://github.com/k2-fsa/sherpa-onnx`
   - Xcode will automatically fetch the official `.xcframework` releases for you!

**For AI:**
Execute the following commands to purge the local Native Swift packages:
```bash
rm ios-native/LocalSherpaOnnx/download_binaries.sh
rm -rf ios-native/LocalSherpaOnnx/XCFrameworks/
```
Then rewrite `Package.swift` to use the remote dependency: `.package(url: "https://github.com/k2-fsa/sherpa-onnx", from: "1.10.0")`

### Step 3: Revert the Web App (`.wasm`)
**For Humans & AI:**
If you deployed custom `.wasm` and `.js` files for the web:
1. Go to the official [Sherpa-ONNX WebAssembly Releases](https://github.com/k2-fsa/sherpa-onnx/releases) page.
2. Download the latest `sherpa-onnx-wasm-main-*.tar.bz2`.
3. Extract it and replace your current `sherpa-onnx.wasm` and Javascript files inside your web assets folder with the official ones.

### Step 4: Remove Custom App Logic
Because the official engine does **not** expose `ys_probs`, your app will crash if you try to read those arrays.
**For Humans & AI:**
1. Open your Dart files (e.g., `lib/engine/sherpa_engine.dart`, `lib/tracking/word/dictation_matcher.dart`, `lib/tracking/word/phoneme_matrix.dart`).
2. Remove any code that attempts to read, parse, or process `ys_probs`.
3. Open your Native iOS file: `ios-native/LocalSherpaOnnx/Sources/SherpaOnnx/SherpaOnnx.swift`.
4. Delete the custom `private lazy var _ys_probs: [Float]` array parsing logic from the `SherpaOnnxRecognizerResult` mapping.

Once you complete these 4 steps, your application will be 100% restored to the official, unmodified k2-fsa Sherpa-ONNX engine!
