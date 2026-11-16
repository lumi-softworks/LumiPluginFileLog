import Foundation
import Testing
@testable import PluginFileLog

/// store-only ZIP 写入器的产物必须能被系统解压工具正确识别并校验 CRC。
@Suite("StoreOnlyZipWriter")
struct StoreOnlyZipWriterTests {
    @Test("打包后的 ZIP 可被系统工具解压且内容一致")
    func roundTripsThroughSystemUnzip() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("zip-writer-tests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("logs", isDirectory: true)
        let destination = root.appendingPathComponent("archive.zip")
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let first = source.appendingPathComponent("app.log")
        let second = source.appendingPathComponent("manifest.json")
        let firstBody = "hello wakey\n"
        let secondBody = "{\"version\":\"1.0\"}\n"
        try firstBody.write(to: first, atomically: true, encoding: .utf8)
        try secondBody.write(to: second, atomically: true, encoding: .utf8)

        try StoreOnlyZipWriter().write(
            entries: [("logs/app.log", first), ("manifest.json", second)],
            to: destination
        )

        #expect(runProcess("/usr/bin/unzip", ["-t", destination.path]).status == 0)

        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        #expect(runProcess("/usr/bin/ditto", ["-x", "-k", destination.path, extracted.path]).status == 0)

        let extractedLog = try String(contentsOf: extracted.appendingPathComponent("logs/app.log"), encoding: .utf8)
        let extractedManifest = try String(contentsOf: extracted.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(extractedLog == firstBody)
        #expect(extractedManifest == secondBody)
    }

    @Test("空文件列表生成只含 EOCD 的合法 ZIP")
    func writesEmptyArchive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-writer-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("empty.zip")

        try StoreOnlyZipWriter().write(entries: [], to: destination)

        // unzip 对空归档返回 warning + 退出码 1，这是标准行为；只含 22 字节 EOCD。
        #expect(try Data(contentsOf: destination).count == 22)
        let listing = runProcess("/usr/bin/unzip", ["-l", destination.path])
        #expect(listing.output.contains("zipfile is empty"))
    }

    private func runProcess(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
