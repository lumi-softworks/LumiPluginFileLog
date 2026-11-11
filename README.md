# LumiPluginFileLog

📖 English | [中文版](README_zh.md)

Shared remote package for the "File Log" plugin, assembled by CofficLab sibling apps such as Lumi and Wakey.

> This plugin depends on no other plugins. The menu bar, settings, storage, and diagnostics surfaces are all accessed through Provider contracts.

## Package

- Manifest package name: `LumiPluginFileLog` (matches the repository name)
- Product / Target: `PluginFileLog`
- Platform: macOS 14+
- Swift tools: 6.0

## What It Provides

- Disk logging: polls `OSLogStore` for the host's subsystem and writes entries to rotated log files.
- Retention: per-file size cap, total directory size cap, and age-based expiry.
- Diagnostics export: packages the log files plus a `manifest.json` into a zip archive the user can save.
- Legacy directory migration: moves logs from an older directory layout into the current one.

## Dependencies and Integration

```swift
dependencies: [
    .package(url: "https://github.com/lumi-softworks/LumiPluginFileLog.git", from: "1.0.0")
]
```

Add the product to the host Factory target:

```swift
.product(name: "PluginFileLog", package: "LumiPluginFileLog")
```

And assemble it in the plugin factory:

```swift
import PluginFileLog

FileLogPlugin()
```

## Brand Configuration

The plugin subscribes to a subsystem, writes into a plugin directory, and names the diagnostics archive — all of which differ per host. Inject a `FileLogBranding` and the matching uninstall branding:

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

`FileLogBranding.lumi` and `FileLogBranding.wakey` are provided for the two existing hosts. The plugin id is also the log directory name, so hosts should keep their historical id to preserve existing logs and plugin data.

The uninstall branding comes from `ProviderUninstall` in `LumiProviders` — it determines which notification the plugin listens to so it can flush and close its file handles before the host removes its data.

## Testing

```sh
swift test
```
