// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tagwell",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Tagwell", targets: ["Tagwell"]),
        .library(name: "ID3Kit", targets: ["ID3Kit"]),
    ],
    dependencies: [
        // In-app updates, the same framework many Mac apps outside the App Store use.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "ID3Kit"),
        .executableTarget(
            name: "Tagwell",
            dependencies: ["ID3Kit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // build-app.sh puts Sparkle.framework in Tagwell.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ID3KitTests", dependencies: ["ID3Kit"]),
        .testTarget(
            name: "TagwellTests",
            dependencies: ["Tagwell", "ID3Kit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
