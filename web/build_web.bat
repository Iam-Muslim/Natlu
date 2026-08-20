@echo off
echo === [1/3] Building Flutter Web (Release) ===
call flutter build web --release --base-href "/recite/"
if %errorlevel% neq 0 exit /b %errorlevel%

echo === [2/3] Copying Flutter App into React Landing Page ===
if not exist "landing_page\public\recite" mkdir "landing_page\public\recite"
xcopy /E /I /Y "build\web" "landing_page\public\recite"

echo === [3/3] Building React Landing Page ===
cd landing_page
call node ./node_modules/vite/bin/vite.js build
if %errorlevel% neq 0 exit /b %errorlevel%

echo === Build Complete! Output is in landing_page/dist ===
echo Preview at: http://localhost:3000
call node ./node_modules/vite/bin/vite.js preview
