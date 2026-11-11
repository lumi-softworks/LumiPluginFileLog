// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumiPluginFileLog",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "PluginFileLog",
            targets: ["PluginFileLog"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/lumi-softworks/LumiLogging.git", from: "1.0.1"),
        .package(url: "https://github.com/lumi-softworks/LumiKernel.git", from: "1.1.0"),
        .package(url: "https://github.com/lumi-softworks/LumiProviders.git", from: "1.23.0"),
    ],
    targets: [
        .target(
            name: "PluginFileLog",
            dependencies: [
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "LumiLoggingKit", package: "LumiLogging"),
                .product(name: "ProviderDiagnostics", package: "LumiProviders"),
                .product(name: "ProviderUninstall", package: "LumiProviders"),
                .product(name: "ProviderStorage", package: "LumiProviders"),
            ],
            path: "Sources/PluginFileLog"
        ),
        .testTarget(
            name: "PluginFileLogTests",
            dependencies: [
                "PluginFileLog",
                .product(name: "KernelCore", package: "LumiKernel"),
                .product(name: "ProviderDiagnostics", package: "LumiProviders"),
                .product(name: "ProviderStorage", package: "LumiProviders"),
            ],
            path: "Tests/PluginFileLogTests"
        )
    ]
)
