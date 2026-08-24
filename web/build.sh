#!/bin/bash
set -e

# 1. Install Flutter if not present (for Cloudflare Pages runner)
if ! command -v flutter &> /dev/null; then
    echo "=== Installing Pre-bundled Flutter SDK on Cloudflare Runner ==="
    curl -fSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.0-stable.tar.xz" -o $HOME/flutter.tar.xz
    tar -xf $HOME/flutter.tar.xz -C $HOME
    rm -f $HOME/flutter.tar.xz
    export PATH="$PATH:$HOME/flutter/bin"
    git config --global --add safe.directory "$HOME/flutter" || true
    flutter config --no-analytics
    flutter --version
fi

# 2. Build Flutter Web
echo "=== [1/3] Building Flutter Web ==="
mkdir -p assets/model
touch assets/model/zipformer_p_arabic_v3.int8.onnx
flutter pub get
flutter build web --release --base-href "/recite/"

# 3. Copy Flutter App to Landing Page Public Folder
echo "=== [2/3] Copying Flutter App into React Landing Page ==="
mkdir -p landing_page/public/recite
cp -R build/web/* landing_page/public/recite/
rm -f landing_page/public/recite/build.sh

# 4. Copy Cloudflare Functions into place
echo "=== Copying Cloudflare Functions ==="
mkdir -p landing_page/functions
cp web/download-model.js landing_page/functions/download-model.js

mkdir -p functions
cp web/download-model.js functions/download-model.js

# 5. Build React Landing Page
echo "=== [3/3] Building React Landing Page ==="
cd landing_page
npm ci
npm run build
echo "=== Build Complete! Output is in landing_page/dist ==="
