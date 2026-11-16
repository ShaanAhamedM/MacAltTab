// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacAltTab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacAltTab", targets: ["MacAltTab"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacAltTab",
            dependencies: [],
            path: "Sources/MacAltTab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
