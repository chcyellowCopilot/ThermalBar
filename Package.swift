// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ThermalBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ThermalBar", targets: ["ThermalBar"]),
        .executable(name: "ThermalBarSMC", targets: ["ThermalBarSMC"])
    ],
    targets: [
        .executableTarget(
            name: "ThermalBar",
            path: "Sources/ThermalBar",
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "ThermalBarSMC",
            path: "Sources/ThermalBarSMC",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)
