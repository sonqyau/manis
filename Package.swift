// swift-tools-version: 6.2

import Foundation
import PackageDescription

let package = Package(
    name: "manis",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "manis", targets: ["manis"]),
        .executable(name: "MainXPC", targets: ["MainXPC"]),
        .executable(name: "MainDaemon", targets: ["MainDaemon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams", from: "6.2.0"),
        .package(url: "https://github.com/ChimeHQ/Rearrange", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.2.6"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        // .package(url: "https://github.com/christophhagen/BinaryCodable", from: "3.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
        .package(url: "https://github.com/pointfreeco/swift-nonempty", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
        .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.6.0"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.23.1"),
    ],
    targets: [
        .executableTarget(
            name: "manis",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Rearrange", package: "Rearrange"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Perception", package: "swift-perception"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "SwiftNavigation", package: "swift-navigation"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
                .product(name: "STTextView", package: "STTextView"),
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "NonEmpty", package: "swift-nonempty"),
            ],
            path: "manis",
            exclude: [
                "XPC",
                "Daemon",
                "Supporting Files/Info.plist",
                "manis.entitlements",
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "MainXPC",
            dependencies: [],
            path: "manis/XPC",
            exclude: [
                "com.manis.XPC.plist",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .executableTarget(
            name: "MainDaemon",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "manis/Daemon",
            exclude: [
                "MainDaemon.entitlements",
                "Info.plist",
                "Launchd.plist",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ],
)
