// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AURA",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AURA", targets: ["AURA"])
    ],
    targets: [
        .executableTarget(
            name: "AURA",
            path: "Sources/AURA"
        )
    ]
)

