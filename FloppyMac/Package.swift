// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FloppyMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "FloppyMac", targets: ["FloppyMac"]),
        .library(name: "FloppyCore", targets: ["FloppyCore"]),
        .library(name: "FloppyFileProvider", targets: ["FloppyFileProvider"])
    ],
    targets: [
        .target(
            name: "FloppyCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "FloppyMac",
            dependencies: ["FloppyCore"]
        ),
        .target(
            name: "FloppyFileProvider",
            dependencies: ["FloppyCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FloppyCoreTests",
            dependencies: ["FloppyCore"],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ])
            ]
        )
    ]
)
