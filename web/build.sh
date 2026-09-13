#!/bin/bash
set -e

# Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# 1. Install Flutter if not present (Cloudflare Pages runner)
if ! command -v flutter &> /dev/null; then
    echo "=== Installing Flutter SDK ==="
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
    export PATH="$PATH:$HOME/flutter/bin"
    git config --global --add safe.directory "$HOME/flutter" || true
    flutter config --no-analytics
fi

# 2. Build Flutter Web
echo "=== Building Flutter Web ==="
mkdir -p assets/model
touch assets/model/zipformer_p_arabic_v3.int8.onnx
flutter pub get
flutter build web --release --base-href "/recite/"

# 3. Copy Web App to landing_page/recite
echo "=== Copying Flutter App into landing_page/recite ==="
mkdir -p landing_page/recite
cp -R build/web/* landing_page/recite/
rm -f landing_page/recite/build.sh landing_page/recite/build_web.bat

# 4. Copy Cloudflare Functions
echo "=== Setting up Cloudflare Functions ==="
mkdir -p landing_page/functions functions
cp web/download-model.js landing_page/functions/
cp web/download-model.js functions/

echo "=== Build Complete! Output is in landing_page/recite ==="
