@echo off
setlocal enabledelayedexpansion
pushd "%~dp0\.."

echo === [1/4] Building Landing Page (React + Vite) ===
pushd "landing_page"
call npm ci || call npm install --legacy-peer-deps
call npm run build
popd

echo === [2/4] Building Flutter Web (Release) ===
call flutter build web --release --base-href "/recite/" --pwa-strategy=none --no-web-resources-cdn
if %errorlevel% neq 0 (
    popd
    exit /b %errorlevel%
)

echo === [3/4] Copying Flutter App into landing_page\dist\recite and landing_page\recite ===
if exist "landing_page\dist\recite" rmdir /s /q "landing_page\dist\recite"
mkdir "landing_page\dist\recite"
xcopy /E /I /Y "build\web" "landing_page\dist\recite"

if exist "landing_page\recite" rmdir /s /q "landing_page\recite"
mkdir "landing_page\recite"
xcopy /E /I /Y "build\web" "landing_page\recite"

del /f /q "landing_page\dist\recite\build.sh" 2>nul
del /f /q "landing_page\dist\recite\build_web.bat" 2>nul
del /f /q "landing_page\recite\build.sh" 2>nul
del /f /q "landing_page\recite\build_web.bat" 2>nul

echo // Neutralized to protect custom sw.js > "landing_page\dist\recite\flutter_service_worker.js"
echo // Neutralized to protect custom sw.js > "landing_page\recite\flutter_service_worker.js"

echo === [4/4] Downleveling JS & Configuring CanvasKit ===
node -e "const fs = require('fs'); for (const p of ['landing_page/recite/flutter_bootstrap.js', 'landing_page/dist/recite/flutter_bootstrap.js']) { if (fs.existsSync(p)) { let s = fs.readFileSync(p, 'utf8'); s = s.replace(/serviceWorkerSettings:\s*\{[\s\S]*?\}\s*,?/g, ''); s = s.replace('if (!window._flutter) {\n  window._flutter = {};\n}\n_flutter.buildConfig', 'var _flutter = window._flutter = window._flutter || {};\n_flutter.buildConfig'); s = s.replace(/\"builds\":/, '\"useLocalCanvasKit\":true,\"builds\":'); s = s.replace(/_flutter\.loader\.load\(\);?/, '_flutter.loader.load({config:{canvasKitBaseUrl:\"canvaskit/\"}});'); fs.writeFileSync(p, s, 'utf8'); } }"
call npx --yes esbuild "landing_page\dist\recite\flutter_bootstrap.js" --target=es2018 --outfile="landing_page\dist\recite\flutter_bootstrap.js" --allow-overwrite
call npx --yes esbuild "landing_page\dist\recite\flutter.js" --target=es2018 --outfile="landing_page\dist\recite\flutter.js" --allow-overwrite
call npx --yes esbuild "landing_page\dist\recite\sherpa-onnx-wasm-main-asr.js" --target=es2020 --outfile="landing_page\dist\recite\sherpa-onnx-wasm-main-asr.js" --allow-overwrite
call npx --yes esbuild "landing_page\recite\flutter_bootstrap.js" --target=es2018 --outfile="landing_page\recite\flutter_bootstrap.js" --allow-overwrite
call npx --yes esbuild "landing_page\recite\flutter.js" --target=es2018 --outfile="landing_page\recite\flutter.js" --allow-overwrite
call npx --yes esbuild "landing_page\recite\sherpa-onnx-wasm-main-asr.js" --target=es2020 --outfile="landing_page\recite\sherpa-onnx-wasm-main-asr.js" --allow-overwrite

echo === [5/5] Updating Service Worker Cache Versions ===
node web\update_cache_version.js

if not exist "functions" mkdir "functions"
if not exist "landing_page\functions" mkdir "landing_page\functions"
if not exist "landing_page\dist\functions" mkdir "landing_page\dist\functions"
copy /Y "web\download-model.js" "functions\download-model.js" >nul
copy /Y "web\download-model.js" "landing_page\functions\download-model.js" >nul
copy /Y "web\download-model.js" "landing_page\dist\functions\download-model.js" >nul

echo === Build Complete! Output is in landing_page\dist ===
popd
