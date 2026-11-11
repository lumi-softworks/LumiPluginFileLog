import Foundation

/// 文件日志插件的品牌配置。
///
/// 磁盘日志采集要订阅哪个 subsystem、写到哪个插件目录、诊断包叫什么名字，
/// 这些都随宿主品牌而变。共享远程包不写死任何宿主品牌信息，由宿主在装配时
/// 注入本类型。
///
/// `FileLogBranding.lumi` 保持 Lumi 的既有取值，默认构造即为 Lumi 行为，
/// 同族应用无需改动现有调用。
public struct FileLogBranding: Sendable, Equatable {
    /// 应用显示名，例如 "Lumi"、"Wakey"。
    ///
    /// 出现在日志文件头的 `=== <名字> Log ===` 一行里。
    public let applicationName: String

    /// 订阅的根 subsystem，例如 "com.coffic.lumi"。
    ///
    /// 插件自身的子系统（`<subsystem>.plugin.file-log`）以及所有以它为前缀的
    /// 子 subsystem 都会被采集。
    public let subsystem: String

    /// 插件 id，同时也是日志目录名，例如 "com.coffic.lumi.plugin.file-log"。
    public let pluginID: String

    /// 诊断包的文件名前缀，例如 "Lumi-Diagnostics"。
    ///
    /// 最终文件名形如 `Lumi-Diagnostics-2026-05-02_10-36-00.zip`。
    public let diagnosticsArchiveNamePrefix: String

    /// 额外纳入采集的 subsystem 前缀。
    ///
    /// 根 subsystem 始终被采集；这里放的是与品牌无关的公共前缀
    /// （例如 LLM 相关的 "com.kit.llm"）。
    public let additionalSubsystemPrefixes: [String]

    public init(
        applicationName: String,
        subsystem: String,
        pluginID: String,
        diagnosticsArchiveNamePrefix: String,
        additionalSubsystemPrefixes: [String] = []
    ) {
        self.applicationName = applicationName
        self.subsystem = subsystem
        self.pluginID = pluginID
        self.diagnosticsArchiveNamePrefix = diagnosticsArchiveNamePrefix
        self.additionalSubsystemPrefixes = additionalSubsystemPrefixes
    }

    /// Lumi 品牌的默认值。
    public static let lumi = Self(
        applicationName: "Lumi",
        subsystem: "com.coffic.lumi",
        pluginID: "com.coffic.lumi.plugin.file-log",
        diagnosticsArchiveNamePrefix: "Lumi-Diagnostics",
        additionalSubsystemPrefixes: ["com.kit.llm"]
    )

    /// Wakey 品牌的默认值。
    ///
    /// 与 Wakey 仓库里迁移前的本地包逐字一致：订阅 "com.coffic.wakey"，
    /// 写入 "com.coffic.wakey.plugin.file-log" 目录，诊断包名为
    /// "Wakey-Diagnostics-<时间戳>.zip"。
    public static let wakey = Self(
        applicationName: "Wakey",
        subsystem: "com.coffic.wakey",
        pluginID: "com.coffic.wakey.plugin.file-log",
        diagnosticsArchiveNamePrefix: "Wakey-Diagnostics",
        additionalSubsystemPrefixes: ["com.kit.llm"]
    )
}
