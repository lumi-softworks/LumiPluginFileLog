import Foundation

/// 日志采集的水位线。
///
/// `OSLogStore` 允许从某个时间点之后重新读取日志，而轮询天然会重叠：
/// 每轮从「上一轮时刻 - writeDelay」开始读，必然把最近几条重读一遍。
///
/// 早期实现用一个无限增长的 `Set<String>` 记住「见过的 key」来去重，
/// 有两个问题：
///
/// 1. **内存无界增长**——key 含完整消息文本，菜单栏 App 常驻数天，
///    这个 Set 会累积几十万条；
/// 2. **误吞真实重复**——key 由「时间戳 + 分类 + 消息」构成，
///    同一毫秒内两条完全相同的消息 key 相同，第二条被静默丢弃，
///    诊断日志因此少报了实际发生的事。
///
/// 水位线的做法：只记住「已经消费到哪里」，不记住「见过什么」。
/// 因为 `OSLogStore` 按时间顺序返回条目，同一时间戳内的条目用序号区分，
/// 于是既不会重复写，也不会吞掉内容相同的不同条目，
/// 内存占用也只与「水位线附近的重叠窗口」成正比。
struct LogWatermark {
    /// 水位线位置：时间戳 + 该时间戳内的序号。
    struct Position: Hashable, Comparable {
        /// 条目的时间戳（秒级浮点，保留亚秒精度）。
        let time: TimeInterval
        /// 同一时间戳内的序号，用于区分内容相同但确实不同的条目。
        let ordinal: Int

        static func < (lhs: Position, rhs: Position) -> Bool {
            if lhs.time != rhs.time {
                return lhs.time < rhs.time
            }
            return lhs.ordinal < rhs.ordinal
        }
    }

    /// 已消费到的位置。
    private(set) var position: Position?

    /// 重叠窗口内记住的条目数上界。
    ///
    /// 只为防止「同一批条目被反复读取」而保留少量最近位置，
    /// 内存占用因此有界。
    private var recentPositions: Set<Position> = []
    private var recentOrder: [Position] = []
    private let capacity: Int

    /// - Parameter capacity: 重叠窗口容量。
    init(capacity: Int = 512) {
        self.capacity = capacity
    }

    /// 判断某个位置是否已被消费过。
    ///
    /// - Parameter candidate: 待判断的位置。
    /// - Returns: 若该位置早于或等于水位线，视为已消费。
    func isConsumed(_ candidate: Position) -> Bool {
        if let position, candidate <= position {
            return true
        }
        return recentPositions.contains(candidate)
    }

    /// 记录已消费的位置，并推进水位线。
    ///
    /// - Parameter consumed: 本轮消费到的位置。
    mutating func advance(to consumed: Position) {
        if let current = position {
            if consumed <= current {
                // 位置未前进，只补记到重叠窗口
                remember(consumed)
                return
            }
            position = consumed
        } else {
            position = consumed
        }
        remember(consumed)
    }

    /// 重置水位线（重新开始采集时调用）。
    mutating func reset() {
        position = nil
        recentPositions.removeAll()
        recentOrder.removeAll()
    }

    private mutating func remember(_ consumed: Position) {
        guard !recentPositions.contains(consumed) else { return }
        recentPositions.insert(consumed)
        recentOrder.append(consumed)
        while recentOrder.count > capacity, let oldest = recentOrder.first {
            recentOrder.removeFirst()
            recentPositions.remove(oldest)
        }
    }
}
