# LumiPluginFileLog

[English](README.md) | 📖 中文版

「磁盘日志」插件的共享远程包，由 Lumi、Wakey 等 CofficLab 同族应用装配。

> 本插件不依赖任何其它插件：状态栏、设置、存储与诊断界面均通过 Provider 契约接入。

## 包信息

- Manifest 包名：`LumiPluginFileLog`（与仓库名一致）
- Product / Target：`PluginFileLog`
- 平台：macOS 14+
- Swift tools：6.0

## 提供的能力

- 磁盘日志：轮询 `OSLogStore` 采集宿主 subsystem 的日志，写入轮转的日志文件。
- 保留策略：单文件大小上限、目录总容量上限、按时间过期清理。
- 诊断导出：把日志文件与 `manifest.json` 打包成 zip，供用户导出。
- 遗留目录迁移：把旧目录结构下的日志搬到当前目录。

## 依赖与接入

```swift
dependencies: [
    .package(url: "https://github.com/lumi-softworks/LumiPluginFileLog.git", from: "1.0.0")
]
```

在宿主的 Factory target 中加入 product：

```swift
.product(name: "PluginFileLog", package: "LumiPluginFileLog")
```

并在插件装配处创建实例：

```swift
import PluginFileLog

FileLogPlugin()
```

## 品牌配置

插件订阅哪个 subsystem、写入哪个插件目录、诊断包叫什么名字，都随宿主而变。
注入 `FileLogBranding` 与对应的卸载品牌配置：

```swift
FileLogPlugin(
    configuration: FileLogPluginConfiguration(
        branding: FileLogBranding(
            applicationName: "Wakey",
            subsystem: "com.coffic.wakey",
            pluginID: "com.coffic.wakey.plugin.file-log",
            diagnosticsArchiveNamePrefix: "Wakey-Diagnostics",
            additionalSubsystemPrefixes: ["com.kit.llm"]
        ),
        uninstallBranding: .wakey
    )
)
```

`FileLogBranding.lumi` 与 `FileLogBranding.wakey` 已为两个现有宿主备好。插件 id
同时也是日志目录名，因此宿主应保留自己的历史 id，以免用户的既有日志与插件数据目录
换位置。

卸载品牌配置来自 `LumiProviders` 里的 `ProviderUninstall`——它决定插件监听哪个通知，
以便宿主清除数据前插件能 flush 并关闭文件句柄。

## 测试

```sh
swift test
```
