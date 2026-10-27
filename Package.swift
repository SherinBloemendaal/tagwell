// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tagwell",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Tagwell", targets: ["Tagwell"]),
        .library(name: "ID3Kit", targets: ["ID3Kit"]),
    ],
    targets: [
        .target(name: "ID3Kit"),
        .executableTarget(
            name: "Tagwell",
            dependencies: ["ID3Kit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ID3KitTests", dependencies: ["ID3Kit"]),
        .testTarget(
            name: "TagwellTests",
            dependencies: ["Tagwell", "ID3Kit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
