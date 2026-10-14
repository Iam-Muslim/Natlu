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

# 2. Build Landing Page (React + Vite)
echo "=== Building Landing Page (React + Vite) ==="
cd landing_page
npm ci || npm install --legacy-peer-deps
npm run build
cd ..

# 3. Build Flutter Web
echo "=== Building Flutter Web ==="
mkdir -p assets/model
touch assets/model/zipformer_p_arabic_v3.int8.onnx
flutter pub get
flutter build web --release --base-href "/recite/" --pwa-strategy=none --no-web-resources-cdn

# 4. Copy Web App to landing_page/dist/recite and landing_page/recite
echo "=== Copying Flutter App into landing_page/dist/recite and landing_page/recite ==="
rm -rf landing_page/dist/recite landing_page/recite/*
mkdir -p landing_page/dist/recite landing_page/recite
cp -R build/web/* landing_page/dist/recite/
cp -R build/web/* landing_page/recite/
rm -f landing_page/dist/recite/build.sh landing_page/dist/recite/build_web.bat
rm -f landing_page/recite/build.sh landing_page/recite/build_web.bat

# Neutralize unregistering stub to protect custom sw.js
echo "// Neutralized to protect custom sw.js" > landing_page/dist/recite/flutter_service_worker.js
echo "// Neutralized to protect custom sw.js" > landing_page/recite/flutter_service_worker.js

# 5. Downlevel JS & Configure CanvasKit
echo "=== Downleveling JS & Configuring CanvasKit ==="
node -e "const fs = require('fs'); for (const p of ['landing_page/recite/flutter_bootstrap.js', 'landing_page/dist/recite/flutter_bootstrap.js']) { if (fs.existsSync(p)) { let s = fs.readFileSync(p, 'utf8'); s = s.replace(/serviceWorkerSettings:\s*\{[\s\S]*?\}\s*,?/g, ''); s = s.replace('if (!window._flutter) {\n  window._flutter = {};\n}\n_flutter.buildConfig', 'var _flutter = window._flutter = window._flutter || {};\n_flutter.buildConfig'); s = s.replace(/\"builds\":/, '\"useLocalCanvasKit\":true,\"builds\":'); s = s.replace(/_flutter\.loader\.load\(\);?/, '_flutter.loader.load({config:{canvasKitBaseUrl:\"canvaskit/\"}});'); fs.writeFileSync(p, s, 'utf8'); } }"

for f in "landing_page/recite/flutter_bootstrap.js" "landing_page/dist/recite/flutter_bootstrap.js" "landing_page/recite/flutter.js" "landing_page/dist/recite/flutter.js"; do
  [ -f "$f" ] && npx --yes esbuild "$f" --target=es2018 --outfile="$f" --allow-overwrite || true
done

for f in "landing_page/recite/sherpa-onnx-wasm-main-asr.js" "landing_page/dist/recite/sherpa-onnx-wasm-main-asr.js"; do
  [ -f "$f" ] && npx --yes esbuild "$f" --target=es2020 --outfile="$f" --allow-overwrite || true
done

# 6. Automatic Cache Busting for Service Workers
echo "=== Updating Service Worker Cache Versions ==="
node web/update_cache_version.js

# 7. Copy Cloudflare Functions and inject token if SUBHAN_ALLAH is set
echo "=== Setting up Cloudflare Functions ==="
mkdir -p functions landing_page/functions landing_page/dist/functions
cp web/download-model.js functions/download-model.js
cp web/download-model.js landing_page/functions/download-model.js
cp web/download-model.js landing_page/dist/functions/download-model.js
if [ -n "${SUBHAN_ALLAH}" ]; then
  sed -i "s/INJECT_TOKEN_HERE/${SUBHAN_ALLAH}/g" functions/download-model.js 2>/dev/null || true
  sed -i "s/INJECT_TOKEN_HERE/${SUBHAN_ALLAH}/g" landing_page/functions/download-model.js 2>/dev/null || true
  sed -i "s/INJECT_TOKEN_HERE/${SUBHAN_ALLAH}/g" landing_page/dist/functions/download-model.js 2>/dev/null || true
fi

# 7. Ensure _headers and _redirects are in dist
cp landing_page/_headers landing_page/dist/_headers 2>/dev/null || true
cp landing_page/_redirects landing_page/dist/_redirects 2>/dev/null || true

# 8. Fail-safe: if Cloudflare Pages serves landing_page instead of landing_page/dist, ensure production files are there too in CI
if [ -n "$CF_PAGES" ] || [ -n "$CI" ]; then
  echo "=== Applying fail-safe production assets copy ==="
  cp landing_page/dist/index.html landing_page/index.html
  cp -R landing_page/dist/assets landing_page/ 2>/dev/null || true
fi

echo "=== Build Complete! Output is in landing_page/dist (and landing_page/recite) ==="
