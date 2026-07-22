// swift-tools-version: 5.9
// Local, fully-offline vendored copy of sherpa-onnx 1.13.2 (from willwade/sherpa-onnx-spm).
// onnxruntime.xcframework's Headers were removed to fix the duplicate
// `include/module.modulemap` build collision — its symbols are consumed only
// through sherpa-onnx's C API, so its headers are unnecessary.
import PackageDescription

let package = Package(
    name: "SherpaOnnx",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "SherpaOnnx",
            targets: ["SherpaOnnx"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "sherpa-onnx",
            path: "XCFrameworks/sherpa-onnx.xcframework"
        ),
        .binaryTarget(
            name: "onnxruntime",
            path: "XCFrameworks/onnxruntime.xcframework"
        ),
        .target(
            name: "SherpaOnnx",
            dependencies: ["sherpa-onnx", "onnxruntime"],
            path: "Sources/SherpaOnnx",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
