// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusGrowthAnalyticsAdAppsFlyerProvider",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "NexusGrowthAnalyticsAdAppsFlyer", targets: ["NexusGrowthAnalyticsAdAppsFlyer"])
    ],
    dependencies: [
        .package(name: "NexusSDK", path: "../.."),
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Static.git", from: "6.17.0")
    ],
    targets: [
        .target(
            name: "NexusGrowthAnalyticsAdAppsFlyer",
            dependencies: [
                .product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK"),
                .product(name: "AppsFlyerLib-Static", package: "AppsFlyerFramework-Static")
            ]
        )
    ]
)
