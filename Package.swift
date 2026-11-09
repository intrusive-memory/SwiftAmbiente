// swift-tools-version: 6.2

import PackageDescription

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
      name: "AmbienteCLICore",
      targets: ["AmbienteCLICore"]
    ),
    .executable(
      name: "ambiente",
      targets: ["ambiente"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.8.2")),

    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.25.0")),

    // GLOSA notation: the `ambience` and `foley` directives (`GlosaCore.Ambience`,
    // `GlosaCore.Foley`) that `AmbienteGenerator.render(ambience:to:)` and
    // `render(foley:to:)` render. GlosaCore only.
    .package(
      url: "https://github.com/intrusive-memory/glosa-av.git", .upToNextMajor(from: "0.12.0")),

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
        .product(name: "GlosaCore", package: "glosa-av"),
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
      name: "AmbienteCLICore",
      dependencies: [
        "SwiftAmbiente",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "ambiente",
      dependencies: [
        "AmbienteCLICore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/ambiente",
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftAmbienteTests",
      dependencies: [
        "SwiftAmbiente",
        .product(name: "GlosaCore", package: "glosa-av"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "AmbienteCLITests",
      dependencies: [
        "AmbienteCLICore",
        "SwiftAmbiente",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
