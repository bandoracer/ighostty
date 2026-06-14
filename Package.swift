// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iGhostty",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "iGhostty", targets: ["iGhostty"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.2.4"),
    ],
    targets: [
        .executableTarget(
            name: "iGhostty",
            dependencies: [
                .product(name: "GhosttyTerminal", package: "libghostty-spm"),
            ],
            path: "Sources/iGhostty",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
