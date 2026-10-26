// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spectrum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Spectrum", targets: ["Spectrum"])
    ],
    targets: [
        .target(name: "SpectrumCore"),
        .executableTarget(name: "Spectrum", dependencies: ["SpectrumCore"]),
        .testTarget(name: "SpectrumCoreTests", dependencies: ["SpectrumCore"]),
    ]
)
