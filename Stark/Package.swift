// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Separate from the KokoroSwift package on purpose: mlx-swift-lm requires
// mlx-swift 0.30.3 or newer, and MisakiSwift — which KokoroSwift needs for
// grapheme-to-phoneme conversion — pins mlx-swift to exactly 0.30.2. Nothing
// satisfies both, so an app links one package or the other, and Stark carries
// its own voice synthesis rather than depending on Kokoro.
let package = Package(
  name: "Stark",
  platforms: [
    .iOS(.v18), .macOS(.v15)
  ],
  products: [
    // Everything: server, model runtime, dashboard.
    .library(
      name: "StarkKit",
      targets: ["StarkKit"]
    ),
    // Core only: HTTP server, scheduler, connectors, persona, metrics.
    // No MLX dependency, so it builds and tests quickly.
    .library(
      name: "StarkCore",
      targets: ["StarkCore"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.30.3"),
  ],
  targets: [
    .target(
      name: "StarkCore"
    ),
    .target(
      name: "StarkLLM",
      dependencies: [
        "StarkCore",
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
      name: "StarkCoreTests",
      dependencies: ["StarkCore"]
    ),
  ]
)
