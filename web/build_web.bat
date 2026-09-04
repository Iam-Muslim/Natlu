@echo off
echo === [1/3] Building Flutter Web (Release) ===
call flutter build web --release --base-href "/recite/"
if %errorlevel% neq 0 exit /b %errorlevel%

echo === [2/2] Copying Flutter App into Landing Page ===
if not exist "landing_page\recite" mkdir "landing_page\recite"
xcopy /E /I /Y "build\web" "landing_page\recite"

echo === Build Complete! Output is in landing_page\ ===
