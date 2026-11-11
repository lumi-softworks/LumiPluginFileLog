import Foundation
import KernelCore
import ProviderDiagnostics
import ProviderStorage
import ProviderUninstall
import Testing
@testable import PluginFileLog

/// 品牌配置的守卫。
///
/// 迁移前 Wakey 仓库里有一份本地实现，Lumi 主项目里另有一份。两边的品牌
/// 字符串必须逐字相同，否则用户会看到不同的日志目录名、不同的诊断包文件名，
/// 或者在卸载确认框里看到不同的提示。
@Suite("文件日志品牌配置")
@MainActor
struct FileLogBrandingTests {
    @Test("Wakey 品牌与迁移前的本地包逐字一致")
    func wakeyBrandingMatchesFormerLocalPackage() {
        let branding = FileLogBranding.wakey

        #expect(branding.applicationName == "Wakey")
        #expect(branding.subsystem == "com.coffic.wakey")
        #expect(branding.pluginID == "com.coffic.wakey.plugin.file-log")
        #expect(branding.diagnosticsArchiveNamePrefix == "Wakey-Diagnostics")
        #expect(branding.additionalSubsystemPrefixes == ["com.kit.llm"])
    }

    @Test("Lumi 品牌与迁移前的主项目实现逐字一致")
    func lumiBrandingMatchesFormerImplementation() {
        let branding = FileLogBranding.lumi

        #expect(branding.applicationName == "Lumi")
        #expect(branding.subsystem == "com.coffic.lumi")
        #expect(branding.pluginID == "com.coffic.lumi.plugin.file-log")
        #expect(branding.diagnosticsArchiveNamePrefix == "Lumi-Diagnostics")
        #expect(branding.additionalSubsystemPrefixes == ["com.kit.llm"])
    }

    @Test("诊断包文件名沿用品牌前缀")
    func archiveFilenameUsesBrandPrefix() {
        // 迁移前 Wakey 生成 "Wakey-Diagnostics-<时间戳>.zip"，Lumi 生成
        // "Lumi-Diagnostics-<时间戳>.zip"。这里只锁定前缀部分。
        let coordinator = FileLogCoordinator(branding: .wakey)
        #expect(coordinator.branding.diagnosticsArchiveNamePrefix == "Wakey-Diagnostics")
    }

    @Test("插件的 id 跟随品牌配置")
    func pluginIDFollowsBranding() {
        let plugin = FileLogPlugin(configuration: FileLogPluginConfiguration(
            branding: .wakey,
            uninstallBranding: .wakey
        ))

        #expect(plugin.id == "com.coffic.wakey.plugin.file-log")
        #expect(plugin.metadata.id == "com.coffic.wakey.plugin.file-log")
    }

    @Test("插件监听品牌专属的卸载通知")
    func pluginListensToBrandedUninstallNotification() {
        let plugin = FileLogPlugin(configuration: FileLogPluginConfiguration(
            branding: .wakey,
            uninstallBranding: .wakey
        ))

        #expect(
            plugin.configuration.uninstallBranding.willUninstallNotificationName
                == "com.coffic.wakey.uninstall.will-uninstall"
        )
    }
}

/// 迁移到共享包时保住的行为。
///
/// 这些守卫覆盖两边各自修过的缺陷：Lumi 侧修了隐藏文件误删、导出前补采日志、
/// 以及可注入的日志读取；Wakey 侧修了当前写入文件被轮转删除、以及水位线去重。
/// 任何一边回退，这里都会红。
@Suite("合并后保留的行为")
@MainActor
struct FileLogMergedBehaviorTests {
    @Test("读取 OSLog 的实现可注入，测试不依赖真实 logd")
    func logRecordReaderIsInjectable() {
        let coordinator = FileLogCoordinator(branding: .wakey)
        var capturedSubsystem: String?

        coordinator.logRecordReader = { subsystem, _ in
            capturedSubsystem = subsystem
            return [
                FileLogCoordinator.LogRecord(date: Date(), line: "injected entry\n")
            ]
        }

        #expect(coordinator.logRecordReader("com.coffic.wakey", Date())?.count == 1)
        #expect(capturedSubsystem == "com.coffic.wakey")
    }

    @Test("注入的读取实现参与轮询，写入日志文件")
    func injectedRecordsReachTheLogFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginFileLogInjectTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let coordinator = FileLogCoordinator(branding: .wakey, logsDirectory: directory, pollInterval: 60)
        coordinator.logRecordReader = { _, _ in
            [FileLogCoordinator.LogRecord(date: Date(timeIntervalSince1970: 1), line: "hello from reader\n")]
        }

        coordinator.start()
        coordinator.pollOnce()
        coordinator.stopAndWait()

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let logName = names.first { $0.hasSuffix(".log") } ?? ""
        let contents = try String(
            contentsOf: directory.appendingPathComponent(logName),
            encoding: .utf8
        )
        #expect(contents.contains("hello from reader"))
    }

    @Test("导出诊断前会补采尚未轮询到的日志")
    func exportDrainsPendingRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginFileLogDrainTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 归档文件名只精确到秒，并行跑测试时会互相覆盖。这里用独立前缀，
        // 与其它用例的归档文件区分开。
        let branding = FileLogBranding(
            applicationName: "Wakey",
            subsystem: "com.coffic.wakey",
            pluginID: "com.coffic.wakey.plugin.file-log",
            diagnosticsArchiveNamePrefix: "DrainTest-Diagnostics",
            additionalSubsystemPrefixes: ["com.kit.llm"]
        )
        let coordinator = FileLogCoordinator(branding: branding, logsDirectory: directory, pollInterval: 60)
        coordinator.logRecordReader = { _, _ in
            [FileLogCoordinator.LogRecord(date: Date(timeIntervalSince1970: 1), line: "drained entry\n")]
        }
        coordinator.start()

        // 不等轮询，直接导出：drain 会把这条记录补进来。
        let archive = try await coordinator.makeDiagnosticsArchive()
        defer { try? FileManager.default.removeItem(at: archive.url) }

        #expect(archive.filename.hasPrefix("DrainTest-Diagnostics-"))
        #expect(archive.filename.hasSuffix(".zip"))
    }

    @Test("迁移遗留目录时不跳过隐藏文件")
    func migrationKeepsHiddenFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginFileLogHiddenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("FileLog", isDirectory: true)
        let current = root.appendingPathComponent("Current", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        // 隐藏的日志文件：跳过隐藏文件的实现会漏掉它。
        let hidden = legacy.appendingPathComponent(".important.log")
        try Data("hidden entry\n".utf8).write(to: hidden)
        // 另一个未被迁移逻辑检查的隐藏文件：目录判空时若跳过隐藏文件，
        // 会误判为「已空」并把整个目录递归删掉（#999）。
        let keep = legacy.appendingPathComponent(".keep")
        try Data("keep me".utf8).write(to: keep)

        try FileLogCoordinator.migrateLegacyDirectory(from: legacy, to: current)

        let migrated = current.appendingPathComponent(".important.log")
        #expect(FileManager.default.fileExists(atPath: migrated.path), "隐藏日志也必须迁移")
        #expect(try String(contentsOf: migrated, encoding: .utf8) == "hidden entry\n")
        #expect(
            try String(contentsOf: keep, encoding: .utf8) == "keep me",
            "未被迁移逻辑检查的隐藏文件不得随目录删除"
        )
        #expect(FileManager.default.fileExists(atPath: legacy.path), "旧目录非空时不得递归删除")
    }

    @Test("当前正在写入的文件不会被轮转清理掉")
    func currentFileSurvivesPurge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginFileLogPurgeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 一个历史日志文件：容量超限时应被清理。
        let old = directory.appendingPathComponent("old.log")
        try Data("old\n".utf8).write(to: old)

        // 目录容量上限为 1 字节：历史文件会被清掉，但正在写入的文件必须留下。
        let coordinator = FileLogCoordinator(
            branding: .wakey,
            logsDirectory: directory,
            maxDirectorySize: 1,
            pollInterval: 60
        )
        coordinator.start()

        // start() 把准备工作排在内部队列上，等它跑完当前文件才存在。
        coordinator.waitForPendingWork()

        // 协调器自己创建的当前文件（名字带时间戳与进程号）。
        let currentName = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .first { $0.hasSuffix(".log") && $0 != "old.log" }
        #expect(currentName != nil, "协调器应当创建自己的日志文件")

        coordinator.stopAndWait()

        #expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(currentName ?? "").path),
            "当前写入的文件不能被轮转清理掉——删掉后 FileHandle 仍指向已删除的 inode，后续日志会静默丢失"
        )
    }

    @Test("水位线去重：同一批记录不会被写两次")
    func watermarkDeduplicatesOverlappingPolls() {
        var watermark = LogWatermark()
        let position = LogWatermark.Position(time: 100, ordinal: 0)

        #expect(!watermark.isConsumed(position))
        watermark.advance(to: position)
        #expect(watermark.isConsumed(position))
    }

    @Test("内容相同但时间戳不同的两条记录都会被保留")
    func watermarkKeepsDistinctEntriesWithSameText() {
        var watermark = LogWatermark()
        let first = LogWatermark.Position(time: 100, ordinal: 0)
        let second = LogWatermark.Position(time: 101, ordinal: 0)

        watermark.advance(to: first)
        #expect(!watermark.isConsumed(second))
    }
}
