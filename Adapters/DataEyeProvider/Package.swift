// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusGrowthAnalyticsAdDataEyeProvider",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "NexusGrowthAnalyticsAdDataEye", targets: ["NexusGrowthAnalyticsAdDataEye"])
    ],
    dependencies: [
        .package(name: "NexusSDK", path: "../..")
    ],
    targets: [
        .target(
            name: "NexusGrowthAnalyticsAdDataEye",
            dependencies: [
                .product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK")
            ]
        )
    ]
)
