// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Xcode's SwiftPM build system can run the linker from an intermediates
// directory. Resolve the DSP archive relative to this manifest, not its cwd.
let dspLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../dsp/build")
    .standardizedFileURL.path

let package = Package(
    name: "RadioformHost",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [.package(path: "../configuration")],
    targets: [
        .target(
            name: "CRadioformAudio",
            path: "Sources/CRadioformAudio",
            publicHeadersPath: "include"
        ),
        .target(
            name: "CRadioformDSP",
            path: "Sources/CRadioformDSP",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "RadioformHost",
            dependencies: ["CRadioformAudio", "CRadioformDSP",
                .product(name: "RadioformConfiguration", package: "configuration")],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
                .linkedLibrary("c++"),
                .linkedLibrary("radioform_dsp"),
                .unsafeFlags(["-L\(dspLibraryDirectory)"])
            ]
        ),
    ]
)
