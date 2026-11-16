// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "UmbraKit",
  platforms: [.macOS(.v26)],
  products: [.library(name: "UmbraKit", targets: ["UmbraKit"])],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.4"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.4"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.4.0"),
  ],
  targets: [
    // The generated client; the build plugin writes it from openapi.yaml.
    .target(
      name: "UmbraAPI",
      dependencies: [.product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")],
      exclude: ["openapi.ref"],
      plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    ),
    .target(
      name: "UmbraKit",
      dependencies: [
        "UmbraAPI",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ]
    ),
    .testTarget(name: "UmbraKitTests", dependencies: ["UmbraKit", "UmbraAPI"]),
  ]
)
