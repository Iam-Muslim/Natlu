@echo off
setlocal enabledelayedexpansion
pushd "%~dp0\.."

echo === [1/3] Building Flutter Web (Release) ===
call flutter build web --release --base-href "/recite/" --pwa-strategy=none
if %errorlevel% neq 0 (
    popd
    exit /b %errorlevel%
)

echo === [2/3] Copying Flutter App into landing_page/recite ===
if exist "landing_page\recite" rmdir /s /q "landing_page\recite"
mkdir "landing_page\recite"
xcopy /E /I /Y "build\web" "landing_page\recite"
del /f /q "landing_page\recite\build.sh" 2>nul
del /f /q "landing_page\recite\build_web.bat" 2>nul

echo // Neutralized to protect custom sw.js > "landing_page\recite\flutter_service_worker.js"

echo === [3/3] Downleveling JS to ES2018 for Legacy Browser Compatibility ===
node -e "const fs = require('fs'); const p = 'landing_page/recite/flutter_bootstrap.js'; if (fs.existsSync(p)) { let s = fs.readFileSync(p, 'utf8'); s = s.replace(/serviceWorkerSettings:\s*\{[\s\S]*?\}\s*,?/g, ''); s = s.replace('if (!window._flutter) {\n  window._flutter = {};\n}\n_flutter.buildConfig', 'var _flutter = window._flutter = window._flutter || {};\n_flutter.buildConfig'); fs.writeFileSync(p, s, 'utf8'); }"
call npx esbuild "landing_page\recite\flutter_bootstrap.js" --target=es2018 --outfile="landing_page\recite\flutter_bootstrap.js" --allow-overwrite
call npx esbuild "landing_page\recite\flutter.js" --target=es2018 --outfile="landing_page\recite\flutter.js" --allow-overwrite
call npx esbuild "landing_page\recite\sherpa-onnx-wasm-main-asr.js" --target=es2020 --outfile="landing_page\recite\sherpa-onnx-wasm-main-asr.js" --allow-overwrite

echo === Build Complete! Output is in landing_page\recite ===
popd
