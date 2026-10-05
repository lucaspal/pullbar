import Foundation

enum RefreshPolicy {
    static let menuFreshnessInterval: TimeInterval = 30
    static let lowBudgetInterval: TimeInterval = 15 * 60
    static let unknownResetRetryInterval: TimeInterval = 15 * 60

    static func shouldRefreshOnMenuOpen(
        lastSuccess: Date?,
        lastError: Error?,
        now: Date = Date()
    ) -> Bool {
        guard lastError == nil, let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= menuFreshnessInterval
    }

    static func interval(configured: TimeInterval, usage: APIUsage?, now: Date = Date()) -> TimeInterval {
        guard let usage, usage.isLow, usage.resetAt > now else { return configured }
        let stretched = max(configured, lowBudgetInterval)
        return min(stretched, usage.resetAt.timeIntervalSince(now) + 1)
    }

    static func mayRefresh(blockedUntil: Date?, now: Date = Date()) -> Bool {
        guard let blockedUntil else { return true }
        return now >= blockedUntil
    }

    static func retryDate(resetAt: Date?, now: Date = Date()) -> Date {
        resetAt ?? now.addingTimeInterval(unknownResetRetryInterval)
    }
}
