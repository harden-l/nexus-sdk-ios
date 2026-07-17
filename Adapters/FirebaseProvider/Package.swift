// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusGrowthAnalyticsAdFirebaseProvider",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "NexusGrowthAnalyticsAdFirebase", targets: ["NexusGrowthAnalyticsAdFirebase"])
    ],
    dependencies: [
        .package(name: "NexusSDK", path: "../.."),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "NexusGrowthAnalyticsAdFirebase",
            dependencies: [
                .product(name: "NexusGrowthAnalyticsAd", package: "NexusSDK"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk")
            ]
        )
    ]
)
