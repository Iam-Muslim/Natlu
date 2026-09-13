@echo off
setlocal enabledelayedexpansion
pushd "%~dp0\.."

echo === [1/2] Building Flutter Web (Release) ===
call flutter build web --release --base-href "/recite/" --pwa-strategy=none
if %errorlevel% neq 0 (
    popd
    exit /b %errorlevel%
)

echo === [2/2] Copying Flutter App into landing_page/recite ===
if exist "landing_page\recite" rmdir /s /q "landing_page\recite"
mkdir "landing_page\recite"
xcopy /E /I /Y "build\web" "landing_page\recite"
del /f /q "landing_page\recite\build.sh" 2>nul
del /f /q "landing_page\recite\build_web.bat" 2>nul

echo === Build Complete! Output is in landing_page\recite ===
popd
