// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
//
// When this manifest is evaluated as a transitive dependency inside Xcode's
// `SourcePackages/checkouts/` or SwiftPM's `.build/checkouts/`, every other
// dependency lives as a sibling in the same directory. Treating those as
// in-development local paths produces conflicting package identities, so we
// must skip the sibling shortcut in that context.
let manifestDir = (#filePath as NSString).deletingLastPathComponent
let isSPMCheckout =
  manifestDir.contains("/SourcePackages/checkouts/")
  || manifestDir.contains("/.build/checkouts/")
let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
let useLocalSiblings = !isCI && !isSPMCheckout

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

let package = Package(
  name: "SwiftAmbiente",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(
      name: "SwiftAmbiente",
      targets: ["SwiftAmbiente"]
    ),
    .library(
      name: "AmbientaCLICore",
      targets: ["AmbientaCLICore"]
    ),
    .executable(
      name: "ambienta",
      targets: ["ambienta"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),

    sibling(
      "SwiftAcervo",
      remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
      from: "0.24.1"),

    // MLX Swift — the Stable Audio backend (WU2) translates Stability AI's
    // official Python-MLX reference op-for-op into MLX Swift (see
    // Sources/SwiftAmbiente/StableAudio/STRATEGY.md). It maps 1:1 to Python MLX
    // (ops + RNG), which the Sortie 9 golden-output parity gate requires.
    // Pinned to the exact revision the sibling `../mlx-audio-swift` package
    // locks (0.31.3) so a single mlx-swift identity resolves across the
    // collection graph. The open range `.upToNextMajor(from: "0.31.3")` drifts
    // up to 0.31.6, which ships a `CudaBuild` build-tool plugin that fails
    // xcodebuild's plugin validation on macOS; 0.31.3 predates it and builds
    // clean, matching mlx-audio-swift's resolved version exactly.
    .package(
      url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),
  ],
  targets: [
    .target(
      name: "SwiftAmbiente",
      dependencies: [
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        // MLX Swift primitives for the Stable Audio backend (WU2): arrays/ops,
        // NN layers, deterministic RNG (seed parity), and FFT.
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXRandom", package: "mlx-swift"),
        .product(name: "MLXFFT", package: "mlx-swift"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .target(
      name: "AmbientaCLICore",
      dependencies: [
        "SwiftAmbiente",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "ambienta",
      dependencies: [
        "AmbientaCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/ambienta",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftAmbienteTests",
      dependencies: ["SwiftAmbiente"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "AmbientaTests",
      dependencies: [
        "AmbientaCLICore",
        "SwiftAmbiente",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
