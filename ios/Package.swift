// swift-tools-version: 6.0

import PackageDescription

// `OCTO_KIT_ONLY=1 swift test` drops the app target so OctoKit's tests run on a Linux host,
// where SwiftUI and AVFoundation do not exist. xtool also reads this manifest on Linux, so the
// switch is an environment variable, never `#if os(Linux)`.
let kitOnly = Context.environment["OCTO_KIT_ONLY"] == "1"

let package = Package(
    name: "Octo",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: kitOnly ? [] : [
        // xtool builds the product named in xtool.yml as the app, and each extension product
        // listed there as an app extension.
        .library(name: "Octo", targets: ["Octo"]),
        .library(name: "OctoShare", targets: ["OctoShare"]),
        .library(name: "OctoWidgets", targets: ["OctoWidgets"]),
        // The modules the Xcode project (project.yml) links into its app and extension targets.
        .library(name: "OctoKit", targets: ["OctoKit"]),
        .library(name: "ShareInbox", targets: ["ShareInbox"]),
        .library(name: "OctoSystem", targets: ["OctoSystem"]),
        .library(name: "OctoIntents", targets: ["OctoIntents"]),
    ],
    targets: [
        // SQLite for the library database where Apple's own SQLite3 module is missing (Linux,
        // for the tests). Apple platforms import SQLite3.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        // Talking to the server, the models and the queue rules. Foundation only.
        .target(name: "OctoKit", dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux]))]),
        // The inbox the share extension leaves a shared list in for the app. Foundation only.
        .target(name: "ShareInbox"),
        // What the app leaves for its widgets, the links the widgets open it with, and the
        // shapes they draw. Foundation only.
        .target(name: "OctoSystem", dependencies: ["ShareInbox"]),
        .testTarget(name: "OctoKitTests", dependencies: ["OctoKit", "ShareInbox", "OctoSystem"]),
    ] + (kitOnly ? [] : [
        // The iPhone app: SwiftUI, AVFoundation and Apple's Liquid Glass.
        .target(name: "Octo", dependencies: ["OctoKit", "ShareInbox", "OctoSystem", "OctoIntents"], resources: [.copy("CoverArt")]),
        // The App Intents that Siri, Shortcuts and the widgets' buttons use. Linked into the app
        // and the widgets, so both know the same intents.
        .target(name: "OctoIntents", dependencies: ["OctoSystem"]),
        // "Share to Octo": the share extension that hands a shared list to Import.
        // Nothing names the extension's view controller when it is linked (the system finds it
        // by name), so the linker is told to keep the file it is in.
        .target(name: "OctoShare", dependencies: ["ShareInbox"],
                linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_octo_share_extension"])]),
        // The home screen widgets. A widget extension starts at the `main` its widget bundle
        // makes, not at the entry point other app extensions are given, so the linker is told
        // to start there, which also keeps the widgets' code.
        .target(name: "OctoWidgets", dependencies: ["OctoSystem", "OctoIntents"],
                linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_main"])]),
    ])
)
