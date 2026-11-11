import Foundation
import Testing
@testable import PluginFileLog

/// 日志采集水位线的去重行为。
@Suite("LogWatermark 水位线")
struct LogWatermarkTests {
    private func position(_ time: TimeInterval, _ ordinal: Int = 0) -> LogWatermark.Position {
        LogWatermark.Position(time: time, ordinal: ordinal)
    }

    @Test("初始状态不认为任何位置已被消费")
    func startsEmpty() {
        let watermark = LogWatermark()

        #expect(!watermark.isConsumed(position(100)))
    }

    @Test("推进水位线后该位置被视为已消费")
    func advancesWatermark() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100))

        #expect(watermark.isConsumed(position(100)))
    }

    @Test("早于水位线的位置视为已消费")
    func earlierPositionsAreConsumed() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100))

        #expect(watermark.isConsumed(position(50)))
    }

    @Test("晚于水位线的位置未消费")
    func laterPositionsAreNotConsumed() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100))

        #expect(!watermark.isConsumed(position(150)))
    }

    @Test("同一时间戳的不同序号是不同位置")
    func sameTimestampDifferentOrdinals() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100, 0))

        #expect(watermark.isConsumed(position(100, 0)))
        #expect(!watermark.isConsumed(position(100, 1)), "内容相同但确实是另一条的日志不应被吞掉")
    }

    @Test("重叠轮询读到同一条目不会被重复消费")
    func overlappingPollDoesNotDuplicate() {
        var watermark = LogWatermark()

        // 第一轮：读到 3 条
        for (ordinal, record) in [position(100, 0), position(100, 1), position(100, 2)].enumerated() {
            let p = LogWatermark.Position(time: record.time, ordinal: ordinal)
            if !watermark.isConsumed(p) {
                watermark.advance(to: p)
            }
        }

        // 第二轮：重叠窗口又读到同样 3 条
        var duplicated = 0
        for (ordinal, record) in [position(100, 0), position(100, 1), position(100, 2)].enumerated() {
            let p = LogWatermark.Position(time: record.time, ordinal: ordinal)
            if !watermark.isConsumed(p) {
                watermark.advance(to: p)
                duplicated += 1
            }
        }

        #expect(duplicated == 0, "重叠读取不应产生重复写入")
    }

    @Test("重叠窗口内的新条目仍会被消费")
    func newEntriesInOverlapWindowAreConsumed() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100, 0))
        watermark.advance(to: position(100, 1))

        // 新增一条同时间戳的条目
        #expect(!watermark.isConsumed(position(100, 2)))
    }

    @Test("reset 清空水位线")
    func resetClearsWatermark() {
        var watermark = LogWatermark()
        watermark.advance(to: position(100))
        #expect(watermark.isConsumed(position(100)))

        watermark.reset()

        #expect(!watermark.isConsumed(position(100)))
    }

    @Test("重叠窗口容量有界")
    func overlapWindowIsBounded() {
        var watermark = LogWatermark(capacity: 4)

        // 推进水位线，旧位置被挤出重叠窗口
        for index in 0 ..< 100 {
            watermark.advance(to: position(Double(index), 0))
        }

        // 容量有界意味着记忆不会无限增长：水位线本身仍能判断历史位置
        #expect(watermark.isConsumed(position(50)))
        #expect(!watermark.isConsumed(position(1000)))
    }
}
