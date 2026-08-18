// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "KokoroSwift",
  platforms: [
    .iOS(.v18), .macOS(.v15)
  ],
  products: [
    .library(
      name: "KokoroSwift",
      type: .dynamic,
      targets: ["KokoroSwift"]
    ),
    // On-device automation server. StarkKit is the umbrella: it wires the
    // transport-agnostic core, the MLX language-model runtime and the UI.
    .library(
      name: "StarkKit",
      targets: ["StarkKit"]
    ),
    // Core only: HTTP server, scheduler, connectors, persona, metrics.
    // Has no MLX dependency, so it builds and tests on any Apple platform.
    .library(
      name: "StarkCore",
      targets: ["StarkCore"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.0"),
    .package(url: "https://github.com/mlalma/MisakiSwift", exact: "1.0.6"),
    .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
  ],
  targets: [
    .target(
      name: "KokoroSwift",
      dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXRandom", package: "mlx-swift"),
        .product(name: "MLXFFT", package: "mlx-swift"),
        // .product(name: "eSpeakNGLib", package: "eSpeakNGSwift"),
        .product(name: "MisakiSwift", package: "MisakiSwift"),
        .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary")
      ],
      resources: [
       .copy("../../Resources/")
      ]
    ),
    .target(
      name: "StarkCore"
    ),
    .target(
      name: "StarkLLM",
      dependencies: [
        "StarkCore",
        "KokoroSwift",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
      ]
    ),
    .target(
      name: "StarkUI",
      dependencies: ["StarkCore"]
    ),
    .target(
      name: "StarkKit",
      dependencies: ["StarkCore", "StarkLLM", "StarkUI"]
    ),
    .testTarget(
      name: "KokoroSwiftTests",
      dependencies: ["KokoroSwift"]
    ),
    .testTarget(
      name: "StarkCoreTests",
      dependencies: ["StarkCore"]
    ),
  ]
)
