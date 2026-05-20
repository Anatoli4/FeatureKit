// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FeatureKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "FeatureKit",
            targets: ["FeatureKit"]
        ),
    ],
    targets: [
        .target(
            name: "FeatureKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
