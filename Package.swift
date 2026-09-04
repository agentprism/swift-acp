// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "swift-acp",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "ACPModel", targets: ["ACPModel"]),
        .library(name: "ACPCore", targets: ["ACPCore"]),
        .library(name: "ACP", targets: ["ACP"]),
        .library(name: "ACPHTTP", targets: ["ACPHTTP"]),
        .library(name: "ACPRegistry", targets: ["ACPRegistry"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/SimplyDanny/SwiftLintPlugins",
            exact: "0.65.1"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-subprocess",
            exact: "1.0.0"
        ),
    ],
    targets: [
        // Core model types (platform-independent)
        .target(
            name: "ACPModel",
            path: "Sources/ACPModel"
        ),
        // Transport-independent ACP client/agent runtime
        .target(
            name: "ACPCore",
            dependencies: ["ACPModel"],
            path: "Sources/ACPCore"
        ),
        // macOS stdio transport and compatibility module
        .target(
            name: "ACP",
            dependencies: [
                "ACPCore",
                "ACPModel",
                .product(
                    name: "Subprocess",
                    package: "swift-subprocess",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            path: "Sources/ACP"
        ),
        // HTTP/WebSocket transport (optional)
        .target(
            name: "ACPHTTP",
            dependencies: ["ACPCore", "ACPModel"],
            path: "Sources/ACPHTTP"
        ),
        // Agent registry (macOS only)
        .target(
            name: "ACPRegistry",
            path: "Sources/ACPRegistry"
        ),
        // Tests
        .testTarget(
            name: "ACPTests",
            dependencies: ["ACP", "ACPCore", "ACPModel"]
        ),
        .testTarget(
            name: "ACPModelTests",
            dependencies: ["ACPModel"]
        ),
        .testTarget(
            name: "ACPHTTPTests",
            dependencies: ["ACPHTTP", "ACPCore", "ACPModel"]
        ),
        .testTarget(
            name: "ACPRegistryTests",
            dependencies: ["ACPRegistry"]
        ),
    ]
)
