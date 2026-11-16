import Foundation

/// 极简 ZIP 写入器（仅 store 模式，不压缩）。
///
/// macOS 的诊断导出依赖 `/usr/bin/ditto`，iOS 没有外部进程可调用，
/// 这里用纯 Foundation 生成标准 ZIP（本地文件头 + 中央目录 + EOCD），
/// 产物可被 Finder / unzip / 第三方工具正常解压。
///
/// 只做「把若干文件按相对路径打包」这一件事：日志是文本、体积有限，
/// 放弃压缩换取实现简单与跨平台确定性。
struct StoreOnlyZipWriter {
    enum WriteError: LocalizedError {
        case fileTooLarge(String)
        case cannotRead(String)
        case cannotOpenDestination(String)

        var errorDescription: String? {
            switch self {
            case let .fileTooLarge(name):
                return "文件过大，超出 ZIP 单文件 4GB 限制：\(name)"
            case let .cannotRead(name):
                return "无法读取待打包文件：\(name)"
            case let .cannotOpenDestination(path):
                return "无法写入 ZIP 文件：\(path)"
            }
        }
    }

    /// 将 `entries`（归档内相对路径 → 磁盘文件 URL）写入 `destination`。
    func write(entries: [(path: String, url: URL)], to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw WriteError.cannotOpenDestination(destination.path)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        var centralEntries: [CentralDirectoryEntry] = []

        for entry in entries {
            let name = entry.path
            guard let nameData = name.data(using: .utf8) else {
                throw WriteError.cannotRead(name)
            }
            guard let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe) else {
                throw WriteError.cannotRead(entry.url.lastPathComponent)
            }
            guard data.count <= Int(UInt32.max) else {
                throw WriteError.fileTooLarge(entry.url.lastPathComponent)
            }

            let crc = CRC32.checksum(of: data)
            let timestamp = Self.dosTimestamp(for: entry.url)
            let size = UInt32(data.count)

            var local = Data()
            local.appendLE(UInt32(0x0403_4B50)) // 本地文件头签名
            local.appendLE(UInt16(10)) // 解压所需版本（store）
            local.appendLE(UInt16(0x0800)) // 文件名按 UTF-8 编码
            local.appendLE(UInt16(0)) // 压缩方式：store
            local.appendLE(timestamp.time)
            local.appendLE(timestamp.date)
            local.appendLE(crc)
            local.appendLE(size) // 压缩后大小
            local.appendLE(size) // 原始大小
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0)) // extra 长度
            local.append(nameData)

            try handle.write(contentsOf: local)
            try handle.write(contentsOf: data)

            centralEntries.append(
                CentralDirectoryEntry(
                    name: nameData,
                    crc: crc,
                    size: size,
                    time: timestamp.time,
                    date: timestamp.date,
                    localHeaderOffset: UInt32(offset)
                )
            )
            offset += UInt64(local.count) + UInt64(data.count)
        }

        let centralDirectoryOffset = UInt32(offset)
        var central = Data()
        for entry in centralEntries {
            central.appendLE(UInt32(0x0201_4B50)) // 中央目录签名
            central.appendLE(UInt16(20)) // 创建版本
            central.appendLE(UInt16(10)) // 解压所需版本
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0)) // store
            central.appendLE(entry.time)
            central.appendLE(entry.date)
            central.appendLE(entry.crc)
            central.appendLE(entry.size)
            central.appendLE(entry.size)
            central.appendLE(UInt16(entry.name.count))
            central.appendLE(UInt16(0)) // extra
            central.appendLE(UInt16(0)) // comment
            central.appendLE(UInt16(0)) // 起始磁盘号
            central.appendLE(UInt16(0)) // 内部属性
            central.appendLE(UInt32(0o100644) << 16) // 外部属性：普通文件 rw-r--r--
            central.appendLE(entry.localHeaderOffset)
            central.append(entry.name)
        }
        try handle.write(contentsOf: central)

        var end = Data()
        end.appendLE(UInt32(0x0605_4B50)) // EOCD 签名
        end.appendLE(UInt16(0)) // 当前磁盘号
        end.appendLE(UInt16(0)) // 中央目录起始磁盘号
        end.appendLE(UInt16(centralEntries.count))
        end.appendLE(UInt16(centralEntries.count))
        end.appendLE(UInt32(central.count))
        end.appendLE(centralDirectoryOffset)
        end.appendLE(UInt16(0)) // 注释长度
        try handle.write(contentsOf: end)
    }

    private struct CentralDirectoryEntry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let time: UInt16
        let date: UInt16
        let localHeaderOffset: UInt32
    }

    private static func dosTimestamp(for url: URL) -> (time: UInt16, date: UInt16) {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(clamping: (components.year ?? 1980) - 1980)
        let month = UInt16(clamping: components.month ?? 1)
        let day = UInt16(clamping: components.day ?? 1)
        let hour = UInt16(clamping: components.hour ?? 0)
        let minute = UInt16(clamping: components.minute ?? 0)
        let second = UInt16(clamping: (components.second ?? 0) / 2)
        // DOS 时间戳：日期 1980 年起，秒精度 2 秒。
        let dosTime = (hour << 11) | (minute << 5) | second
        let dosDate = (year << 9) | (month << 5) | day
        return (dosTime, dosDate)
    }
}

/// ZIP 所需的 CRC-32（IEEE 802.3），store 模式也必须携带校验值。
private enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
