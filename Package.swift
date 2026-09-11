// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BackAudioRecorder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BackAudioRecorder", targets: ["BackAudioRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "BackAudioRecorder",
            path: "Sources/BackAudioRecorder",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
