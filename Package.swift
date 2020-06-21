// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "SwiftyGPU",
    products: [
        .executable(name: "swifty-gpu", targets: ["SwiftyGPU"])
    ],
    targets: [
        .target(name: "SwiftyGPU", dependencies: [])
    ]
)
