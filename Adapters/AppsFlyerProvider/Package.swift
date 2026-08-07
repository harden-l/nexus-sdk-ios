// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusGrowthAnalyticsAdAppsFlyerProvider",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "NexusGrowthAnalyticsAdAppsFlyer", targets: ["NexusGrowthAnalyticsAdAppsFlyer"])
    ],
    dependencies: [
        .package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.0.7"),
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static.git", from: "6.17.0")
    ],
    targets: [
        .target(
            name: "NexusGrowthAnalyticsAdAppsFlyer",
            dependencies: [
                .product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios"),
                .product(name: "AppsFlyerLib-Static", package: "AppsFlyerFramework-Static")
            ]
        )
    ]
)
