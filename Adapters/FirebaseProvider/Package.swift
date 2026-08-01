// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusGrowthAnalyticsAdFirebaseProvider",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "NexusGrowthAnalyticsAdFirebase", targets: ["NexusGrowthAnalyticsAdFirebase"])
    ],
    dependencies: [
        .package(url: "https://github.com/harden-l/nexus-sdk-ios.git", exact: "0.0.5"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "NexusGrowthAnalyticsAdFirebase",
            dependencies: [
                .product(name: "NexusGrowthAnalyticsAd", package: "nexus-sdk-ios"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk")
            ]
        )
    ]
)
