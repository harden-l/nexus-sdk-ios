// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NexusCoreUser", targets: ["NexusCoreUser"]),
        .library(name: "NexusGrowthAnalyticsAd", targets: ["NexusGrowthAnalyticsAd"]),
        .library(name: "NexusPayment", targets: ["NexusPayment"]),
        .library(name: "NexusCrossPromo", targets: ["NexusCrossPromo"]),
        .library(name: "NexusGrowthAnalyticsAdDataEye", targets: ["NexusGrowthAnalyticsAdDataEye"])
    ],
    dependencies: [],
    targets: [
        .target(name: "NexusCoreUser"),
        .target(name: "NexusGrowthAnalyticsAd", dependencies: ["NexusCoreUser"]),
        .target(
            name: "NexusPayment",
            dependencies: ["NexusCoreUser", "NexusGrowthAnalyticsAd"],
            resources: [.process("Resources")]
        ),
        .target(name: "NexusCrossPromo", dependencies: ["NexusCoreUser", "NexusGrowthAnalyticsAd"]),
        .target(
            name: "NexusGrowthAnalyticsAdDataEye",
            dependencies: ["NexusGrowthAnalyticsAd"],
            path: "Adapters/DataEyeProvider/Sources/NexusGrowthAnalyticsAdDataEye"
        ),
        .testTarget(name: "NexusCoreUserTests", dependencies: ["NexusCoreUser"]),
        .testTarget(name: "NexusGrowthAnalyticsAdTests", dependencies: ["NexusGrowthAnalyticsAd"]),
        .testTarget(name: "NexusPaymentTests", dependencies: ["NexusPayment"]),
        .testTarget(name: "NexusCrossPromoTests", dependencies: ["NexusCrossPromo"])
    ]
)
