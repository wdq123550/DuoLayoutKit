// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DuoLayoutKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DuoLayoutKit",
            targets: ["DuoLayoutKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/devicekit/DeviceKit", from: "5.10.0"),
    ],
    targets: [
        .target(
            name: "DuoLayoutKit",
            dependencies: [
                .product(name: "DeviceKit", package: "DeviceKit"),
            ]
        ),
        .testTarget(
            name: "DuoLayoutKitTests",
            dependencies: ["DuoLayoutKit"]
        ),
    ]
)
