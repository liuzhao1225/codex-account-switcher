// swift-tools-version: 6.2

import PackageDescription

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
    targets: [
        .executableTarget(
            name: "CodexAccountSwitcher",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "CodexAccountSwitcherTests",
            dependencies: ["CodexAccountSwitcher"],
            swiftSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
                .linkedFramework("Testing"),
            ]
        ),
    ]
)
