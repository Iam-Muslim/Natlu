#!/bin/bash
set -e

echo "=== [1/3] Building Flutter Web ==="
flutter pub get
flutter build web --release --base-href "/recite/"

echo "=== [2/3] Copying Flutter App into React Landing Page ==="
mkdir -p landing_page/public/recite
cp -R build/web/* landing_page/public/recite/

echo "=== [3/3] Building React Landing Page ==="
cd landing_page
npm ci
npm run build
echo "=== Build Complete! Output is in landing_page/dist ==="
