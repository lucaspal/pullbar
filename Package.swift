// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pullbar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "pullbar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/pullbar",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "pullbarTests",
            dependencies: ["pullbar"],
            path: "Tests/pullbarTests"
        ),
    ]
)
