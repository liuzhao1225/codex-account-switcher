// swift-tools-version: 6.2

import Foundation
import PackageDescription

func xcrunFind(_ tool: String) -> URL? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--find", tool]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !path.isEmpty
    else {
        return nil
    }
    return URL(fileURLWithPath: path)
}

let testingCompatibilitySettings: ([SwiftSetting], [LinkerSetting]) = {
    guard let swiftExecutable = xcrunFind("swift") else { return ([], []) }

    let selectedToolchainRoot = swiftExecutable
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let frameworksDirectory = selectedToolchainRoot
        .appending(path: "Library/Developer/Frameworks", directoryHint: .isDirectory)
    let librariesDirectory = selectedToolchainRoot
        .appending(path: "Library/Developer/usr/lib", directoryHint: .isDirectory)
    let testingFramework = frameworksDirectory
        .appending(path: "Testing.framework", directoryHint: .isDirectory)
    let testingInteropLibrary = librariesDirectory.appending(path: "lib_TestingInterop.dylib")

    guard FileManager.default.fileExists(atPath: testingFramework.path),
          FileManager.default.fileExists(atPath: testingInteropLibrary.path)
    else {
        return ([], [])
    }

    return (
        [.unsafeFlags(["-F", frameworksDirectory.path])],
        [
            .unsafeFlags([
                "-F", frameworksDirectory.path,
                "-Xlinker", "-rpath", "-Xlinker", frameworksDirectory.path,
                "-Xlinker", "-rpath", "-Xlinker", librariesDirectory.path,
            ]),
            .linkedFramework("Testing"),
        ]
    )
}()

let package = Package(
    name: "CodexAccountSwitcher",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "CodexAccountSwitcher",
            targets: ["CodexAccountSwitcher"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "CodexAccountSwitcher",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "CodexAccountSwitcherTests",
            dependencies: ["CodexAccountSwitcher"],
            swiftSettings: testingCompatibilitySettings.0,
            linkerSettings: testingCompatibilitySettings.1
        ),
    ]
)
