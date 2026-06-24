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

    // ── Staged integration (see REQUIREMENTS-stable-audio-integration.md) ──────
    // SwiftAmbiente's real generation backend is Stable Audio 3 Small SFX, ported
    // to MLX Swift, with model distribution through SwiftAcervo's shared-models
    // CDN (the same convention as SwiftVoxAlta). Neither the MLX port nor the
    // Acervo wiring exists yet, so they are intentionally left out of the build
    // graph to keep `make build` green today. Uncomment when the MLX Stable Audio
    // generator lands; the model manager already documents the integration point.
    //
    // sibling(
    //   "SwiftAcervo",
    //   remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    //   from: "0.19.2"),
  ],
  targets: [
    .target(
      name: "SwiftAmbiente",
      dependencies: [],
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
