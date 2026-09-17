// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenBaseball",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenBaseball", targets: ["TokenBaseball"])],
    targets: [
        .target(name: "TokenBaseballCore"),
        .executableTarget(name: "TokenBaseball", dependencies: ["TokenBaseballCore"],
                          resources: [.process("Resources")]),
        .testTarget(name: "TokenBaseballCoreTests", dependencies: ["TokenBaseballCore"])
    ]
)
