import Foundation
import KernelCore
import ProviderDiagnostics
import ProviderUninstall
import ProviderStorage
import LumiLoggingKit
import os

// MARK: - Configuration

/// 磁盘日志插件的装配配置。
///
/// 插件要订阅哪个 subsystem、写到哪个目录、诊断包叫什么名字，由
/// `branding` 决定；卸载前要收听哪个通知，由 `uninstallBranding` 决定
/// （通知名的权威来源是 `ProviderUninstall` 里的 `UninstallBranding`）。
public struct FileLogPluginConfiguration: Sendable {
    /// 文件日志的品牌配置。
    public let branding: FileLogBranding

    /// 卸载流程的品牌配置。
    public let uninstallBranding: UninstallBranding

    public init(
        branding: FileLogBranding = .lumi,
        uninstallBranding: UninstallBranding = .lumi
    ) {
        self.branding = branding
        self.uninstallBranding = uninstallBranding
    }
}

// MARK: - File Log SuperPlugin

/// 磁盘日志插件
///
/// 通过 OSLogStore 订阅宿主根 subsystem 的日志条目，异步写入磁盘文件。
/// 支持自动轮转和过期清理。
///
/// 插件启动时从 `StorageProviding` 获取日志目录，并启动 `FileLogCoordinator`。
/// 插件关闭时停止协调器。
@MainActor
public final class FileLogPlugin: SuperPlugin, PluginDataMigrating, SuperLog {
    nonisolated public static let emoji = "📝"

    /// Lumi 品牌的默认插件 id，同时是日志目录名。
    nonisolated public static let pluginID = FileLogBranding.lumi.pluginID

    /// 装配配置。
    public let configuration: FileLogPluginConfiguration

    /// 插件 id，同时是日志目录名。
    public let id: String

    public let legacyDataDirectoryNames = ["FileLog"]
    public let order = 1
    public let metadata: PluginMetadata

    private var uninstallObserver: NSObjectProtocol?

    /// 本插件的日志协调器。
    nonisolated public let coordinator: FileLogCoordinator

    public init(configuration: FileLogPluginConfiguration = FileLogPluginConfiguration()) {
        self.configuration = configuration
        self.id = configuration.branding.pluginID
        self.metadata = PluginMetadata(
            id: configuration.branding.pluginID,
            name: "File Log",
            description: "",
            category: .system,
            stage: .stable,
            policy: .required
        )
        self.coordinator = FileLogCoordinator(branding: configuration.branding)
    }

    public func onBoot(kernel: KernelCoreContainer) throws {
        // 从 StorageProviding 获取日志目录
        if let storage = kernel.resolveProvider((any StorageProviding).self) {
            let currentDirectory = storage.pluginDataDirectory(for: id)
            let legacyDirectory = currentDirectory.deletingLastPathComponent()
                .appendingPathComponent("FileLog", isDirectory: true)
            try? FileLogCoordinator.migrateLegacyDirectory(
                from: legacyDirectory,
                to: currentDirectory
            )
            FileLogRuntimeBridge.logsDirectory = currentDirectory
        }
        coordinator.start()
        uninstallObserver = NotificationCenter.default.addObserver(
            forName: .willUninstall(branding: configuration.uninstallBranding),
            object: nil,
            queue: nil
        ) { [coordinator] _ in
            coordinator.stopAndWait()
        }
        kernel.unregisterProvider((any DiagnosticsProviding).self)
        try kernel.registerProvider((any DiagnosticsProviding).self, coordinator)
    }

    public func onShutdown(kernel: KernelCoreContainer) throws {
        if let uninstallObserver {
            NotificationCenter.default.removeObserver(uninstallObserver)
            self.uninstallObserver = nil
        }
        coordinator.stop()
    }
}

// MARK: - Runtime Bridge

/// 运行时桥接：持有日志目录路径
enum FileLogRuntimeBridge {
    nonisolated(unsafe) static var logsDirectory: URL?
}
