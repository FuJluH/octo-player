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
        // xtool builds the one library product as the app.
        .library(name: "Octo", targets: ["Octo"]),
    ],
    targets: [
        // Talking to the server, the models and the queue rules. Foundation only.
        .target(name: "OctoKit"),
        .testTarget(name: "OctoKitTests", dependencies: ["OctoKit"]),
    ] + (kitOnly ? [] : [
        // The iPhone app: SwiftUI, AVFoundation and Apple's Liquid Glass.
        .target(name: "Octo", dependencies: ["OctoKit"]),
    ])
)
