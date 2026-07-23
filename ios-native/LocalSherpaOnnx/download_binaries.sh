#!/bin/bash
set -e

# Download the custom compiled iOS binaries from your GitHub release
echo "Downloading Custom Sherpa-ONNX iOS binaries..."
curl -L -o ios-binaries.zip "https://github.com/Iam-Muslim/ReciteQuran/releases/download/custom-engine-latest/ios-binaries.zip"

echo "Extracting..."
unzip -q ios-binaries.zip
rm ios-binaries.zip

# Ensure the XCFrameworks directory exists
mkdir -p XCFrameworks

# Move the downloaded frameworks into the XCFrameworks folder
if [ -d "sherpa-onnx.xcframework" ]; then
    rm -rf XCFrameworks/sherpa-onnx.xcframework
    mv sherpa-onnx.xcframework XCFrameworks/
fi

if [ -d "build-ios/ios-onnxruntime/onnxruntime.xcframework" ]; then
    rm -rf XCFrameworks/onnxruntime.xcframework
    mv build-ios/ios-onnxruntime/onnxruntime.xcframework XCFrameworks/
fi

# Clean up
rm -rf build-ios

echo "Successfully installed sherpa-onnx.xcframework and onnxruntime.xcframework into Native Swift Package!"
