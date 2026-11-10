import Foundation

public struct InvestorRank: Identifiable, Equatable {
    public var id: Int { level }
    public let level: Int
    public let title: String
    public let badge: String
    public let colorHex: String
    public let minAmount: Double
    public let maxAmount: Double
    
    public static let allRanks: [InvestorRank] = [
        InvestorRank(level: 1, title: "存股見習生", badge: "🥉", colorHex: "#CD7F32", minAmount: 0, maxAmount: 100_000),
        InvestorRank(level: 2, title: "存股築基者", badge: "🥈", colorHex: "#8E8E93", minAmount: 100_000, maxAmount: 500_000),
        InvestorRank(level: 3, title: "被動現金流行家", badge: "🥇", colorHex: "#FFD700", minAmount: 500_000, maxAmount: 1_000_000),
        InvestorRank(level: 4, title: "百萬存股達人", badge: "💎", colorHex: "#007AFF", minAmount: 1_000_000, maxAmount: 3_000_000),
        InvestorRank(level: 5, title: "穩健資本家", badge: "👑", colorHex: "#AF52DE", minAmount: 3_000_000, maxAmount: 5_000_000),
        InvestorRank(level: 6, title: "財富自由領航員", badge: "🏆", colorHex: "#FF9500", minAmount: 5_000_000, maxAmount: 10_000_000),
        InvestorRank(level: 7, title: "傳奇存股巨擘", badge: "⭐", colorHex: "#FF2D55", minAmount: 10_000_000, maxAmount: Double.infinity)
    ]
    
    public static func currentRank(for amount: Double) -> InvestorRank {
        for rank in allRanks.reversed() {
            if amount >= rank.minAmount {
                return rank
            }
        }
        return allRanks[0]
    }
    
    public static func nextRank(for current: InvestorRank) -> InvestorRank? {
        allRanks.first { $0.level == current.level + 1 }
    }
    
    public static func progress(for amount: Double) -> Double {
        let rank = currentRank(for: amount)
        guard rank.maxAmount.isFinite else { return 1.0 }
        let currentInTier = max(0.0, amount - rank.minAmount)
        let tierRange = rank.maxAmount - rank.minAmount
        guard tierRange > 0 else { return 1.0 }
        return min(1.0, currentInTier / tierRange)
    }
    
    public static func remainingToNext(for amount: Double) -> Double? {
        let rank = currentRank(for: amount)
        guard rank.maxAmount.isFinite else { return nil }
        return max(0.0, rank.maxAmount - amount)
    }
}
