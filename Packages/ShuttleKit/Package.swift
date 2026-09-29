// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShuttleKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ShuttleKit", targets: ["ShuttleKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.1"),
        // Same fork Citadel pins, so the NIOSSH types line up.
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
    ],
    targets: [
        .target(
            name: "CCurl",
            linkerSettings: [.linkedLibrary("curl")]
        ),
        .target(
            name: "ShuttleKit",
            dependencies: [
                "CCurl",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(name: "ShuttleKitTests", dependencies: ["ShuttleKit"]),
    ]
)
