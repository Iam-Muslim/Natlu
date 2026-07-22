#!/usr/bin/env bash
#
# Fetches the large binary assets that are deliberately not committed to git:
#
#   1. sherpa-onnx + onnxruntime XCFrameworks  (~178 MB, prebuilt static libs)
#   2. the Zipformer2-CTC phoneme ASR model    (69 MB, license-gated — manual)
#
# Run from anywhere:  ./ios-native/scripts/fetch-vendor-assets.sh
# Safe to re-run; it skips anything already present and verified.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

SHERPA_VERSION="1.13.2"
BASE_URL="https://github.com/willwade/sherpa-onnx-spm/releases/download/${SHERPA_VERSION}"

XCF_DIR="$ROOT/LocalSherpaOnnx/XCFrameworks"
MODELS_DIR="$ROOT/ReciteQuran-iOS-Native/Resources/Models"
MODEL_FILE="$MODELS_DIR/quran_phoneme_zipformer.int8.onnx"

# Known-good SHA-256 of the static libraries, after the header fix below.
SUM_ORT_SIM="6f8f3a9ee0cd259afa8cd5bd40384a09cbc6b8f536bdaa68637ea830a15971bf"
SUM_ORT_ARM="4be6fdddf53e8f48dc21d79f318822a5b033b99715a91bc524da414625a498f1"
SUM_SHERPA_SIM="93db3a11cad0980802ae47725479d8b2e9755c1f692356273b5451698d09af6d"
SUM_SHERPA_ARM="c1d3fa6931a711c40fc4602b433d805c3d2f986ecb1e6fef90f15ced37ee8875"
SUM_MODEL="dfe997f79df784827b479b9fb602e6221d8747f4dbce1b5e3a1414e46423d62b"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

check_sum() { # <file> <expected>
  [ -f "$1" ] || return 1
  [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ]
}

pb() { /usr/libexec/PlistBuddy "$@"; }

# Number of entries in the xcframework's AvailableLibraries array.
slice_count() { # <Info.plist>
  local i=0
  while pb -c "Print :AvailableLibraries:${i}:LibraryIdentifier" "$1" >/dev/null 2>&1; do
    i=$((i + 1))
  done
  printf '%s' "$i"
}

# Drops every non-iOS slice (the package is iOS-only, and the macOS slices
# roughly triple the on-disk size), and optionally strips HeadersPath.
# Iterates in reverse so deleting an entry never shifts a pending index.
prune_xcframework() { # <xcframework dir> <strip_headers: yes|no>
  local xcf="$1" strip="$2" plist="$1/Info.plist" i platform ident
  [ -f "$plist" ] || die "missing Info.plist in $xcf"

  for (( i = $(slice_count "$plist") - 1; i >= 0; i-- )); do
    platform="$(pb -c "Print :AvailableLibraries:${i}:SupportedPlatform" "$plist" 2>/dev/null || true)"
    ident="$(pb -c "Print :AvailableLibraries:${i}:LibraryIdentifier" "$plist" 2>/dev/null || true)"

    if [ "$platform" != "ios" ]; then
      pb -c "Delete :AvailableLibraries:${i}" "$plist"
      [ -n "$ident" ] && rm -rf "${xcf:?}/${ident:?}"
    elif [ "$strip" = "yes" ]; then
      pb -c "Delete :AvailableLibraries:${i}:HeadersPath" "$plist" 2>/dev/null || true
    fi
  done
}

# ---------------------------------------------------------------------------
# 1. XCFrameworks
# ---------------------------------------------------------------------------

xcframeworks_ok() {
  check_sum "$XCF_DIR/onnxruntime.xcframework/ios-arm64_x86_64-simulator/libonnxruntime.a" "$SUM_ORT_SIM" &&
  check_sum "$XCF_DIR/onnxruntime.xcframework/ios-arm64/libonnxruntime.a"                  "$SUM_ORT_ARM" &&
  check_sum "$XCF_DIR/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a" "$SUM_SHERPA_SIM" &&
  check_sum "$XCF_DIR/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a"                  "$SUM_SHERPA_ARM"
}

if xcframeworks_ok; then
  info "XCFrameworks already present and verified — skipping."
else
  info "Downloading sherpa-onnx ${SHERPA_VERSION} XCFrameworks (~180 MB)…"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  for name in onnxruntime sherpa-onnx; do
    info "  fetching ${name}.xcframework.zip"
    curl -fL --progress-bar -o "$tmp/${name}.zip" "${BASE_URL}/${name}.xcframework.zip" \
      || die "download failed for ${name}.xcframework.zip"
  done

  mkdir -p "$XCF_DIR"
  for name in onnxruntime sherpa-onnx; do
    rm -rf "$XCF_DIR/${name}.xcframework"
    unzip -q "$tmp/${name}.zip" -d "$tmp/unpacked-${name}"
    src="$(find "$tmp/unpacked-${name}" -maxdepth 2 -name "${name}.xcframework" -type d | head -1)"
    [ -n "$src" ] || die "could not find ${name}.xcframework inside the archive"
    mv "$src" "$XCF_DIR/${name}.xcframework"
  done

  # The onnxruntime headers ship their own `include/module.modulemap`, which
  # collides with sherpa-onnx's during the build. onnxruntime's symbols are
  # only ever consumed through sherpa-onnx's C API, so its headers are
  # unnecessary — strip them and drop HeadersPath from the Info.plist.
  info "Applying onnxruntime header fix (removes duplicate module.modulemap)…"
  find "$XCF_DIR/onnxruntime.xcframework" -type d -name Headers -exec rm -rf {} +

  info "Pruning non-iOS slices…"
  prune_xcframework "$XCF_DIR/onnxruntime.xcframework" yes
  prune_xcframework "$XCF_DIR/sherpa-onnx.xcframework" no

  # Some archives carry an unreferenced duplicate of the static lib
  # (`onnxruntime.a` alongside `libonnxruntime.a`) — pure dead weight.
  find "$XCF_DIR/onnxruntime.xcframework" -name "onnxruntime.a" -delete

  if xcframeworks_ok; then
    info "XCFrameworks verified."
  else
    warn "Checksums did not match the pinned values. The upstream release may"
    warn "have been re-published. The build may still work — verify manually."
  fi
fi

# ---------------------------------------------------------------------------
# 2. ASR model (gated — cannot be scripted)
# ---------------------------------------------------------------------------

if check_sum "$MODEL_FILE" "$SUM_MODEL"; then
  info "ASR model already present and verified — skipping."
else
  mkdir -p "$MODELS_DIR"
  cat <<EOF

--------------------------------------------------------------------------
  MANUAL STEP: the ASR model is a license-gated download.
--------------------------------------------------------------------------
  quran_phoneme_zipformer.int8.onnx is NOT in this repo. It is a gated
  Hugging Face download under a custom license that restricts commercial
  use — read the LICENSE on the model repo before shipping.

    1. Sign in and accept the license at:
         https://huggingface.co/Muno459/zipformer_p-quran

    2. Download 'quran_phoneme_zipformer.int8.onnx' and place it at:
         ReciteQuran-iOS-Native/Resources/Models/

       Or, with the Hugging Face CLI authenticated (\`hf auth login\`):

         hf download Muno459/zipformer_p-quran \\
           quran_phoneme_zipformer.int8.onnx \\
           --local-dir "$MODELS_DIR"

    3. Re-run this script to verify it.

  Expected: 72,705,392 bytes
  sha256:   $SUM_MODEL
--------------------------------------------------------------------------

EOF
  exit 1
fi

info "All assets present. Open ReciteQuran-iOS-Native.xcodeproj and build."
