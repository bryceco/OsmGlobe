// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlobeRenderer",
    platforms: [
        .iOS(.v14),
        .macCatalyst(.v14)
    ],
    products: [
        .library(name: "GlobeRenderer", targets: ["GlobeRenderer"])
    ],
    targets: [
        .target(
            name: "GlobeRenderer",
            path: "Sources/GlobeRenderer"
        )
    ]
)
