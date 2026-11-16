// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OptSwitch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OptSwitch", targets: ["OptSwitch"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OptSwitch",
            dependencies: [],
            path: "Sources/OptSwitch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
