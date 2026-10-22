// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DailyWorkspace",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DailyWorkspace", targets: ["DailyWorkspace"]),
        .library(name: "DailyCore", targets: ["DailyCore"]),
    ],
    targets: [
        // Pure Foundation logic: caret physics, vault file layer, tasks, date templates.
        .target(name: "DailyCore"),
        // SwiftUI + AppKit app. Info.plist is embedded so EventKit's usage string
        // is present even when launched with `swift run`; Scripts/bundle.sh builds a real .app.
        .executableTarget(
            name: "DailyWorkspace",
            dependencies: ["DailyCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"]),
    ]
)
