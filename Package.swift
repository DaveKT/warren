// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Warren",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Automatic updates (Check for Updates…). build-app.sh copies
        // Sparkle.framework into the app bundle and signs it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Warren",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Warren",
            linkerSettings: [
                // Find Sparkle.framework in Warren.app/Contents/Frameworks,
                // or beside the binary in development builds.
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path",
                ])
            ]
        )
    ]
)
