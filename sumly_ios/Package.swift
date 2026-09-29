// swift-tools-version: 6.0
import PackageDescription

// Runs the authentication state-machine tests without simulator services.
let package = Package(
    name: "SumlyAuthentication",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Sumly", targets: ["Sumly"])],
    targets: [
        .target(name: "Sumly", path: "Sumly/Sources/Features/Account/Core"),
        .testTarget(name: "AuthTests", dependencies: ["Sumly"], path: "Tests/Authentication")
    ]
)
