import Foundation

public enum DividendEventType: String, Codable {
    case lastBuyDate = "最後購買日"
    case exDividendDate = "除息日"
    case paymentDate = "股利發放日"
    
    public var badgeColorHex: String {
        switch self {
        case .lastBuyDate: return "#5AC8FA"  // 淺天藍
        case .exDividendDate: return "#007AFF" // 官方深藍
        case .paymentDate: return "#34C759"   // 綠色
        }
    }
}

public struct DividendEvent: Identifiable, Codable, Equatable {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var frequency: FrequencyType
    public var eventType: DividendEventType
    public var targetDate: Date
    public var cashPerShare: Double         // 每股配發現金 (元)
    public var stockPerShare: Double        // 每股股票股利 (元)
    public var sharesSnapshot: Int          // 除息當下持有股數
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        frequency: FrequencyType = .quarterly,
        eventType: DividendEventType = .exDividendDate,
        targetDate: Date,
        cashPerShare: Double = 0.0,
        stockPerShare: Double = 0.0,
        sharesSnapshot: Int = 0
    ) {
        self.id = id
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frequency = frequency
        self.eventType = eventType
        self.targetDate = targetDate
        self.cashPerShare = cashPerShare
        self.stockPerShare = stockPerShare
        self.sharesSnapshot = sharesSnapshot
    }
    
    // 預估領取總股息
    public var totalDividendAmount: Double {
        Double(sharesSnapshot) * cashPerShare
    }
    
    // 距離目標日期的剩餘天數 (倒數日計算)
    public var daysRemaining: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTarget = calendar.startOfDay(for: targetDate)
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget)
        return components.day ?? 0
    }
    
    // 倒數標籤文字 (例如：今天、剩 2 天、剩 6 天、已過期)
    public var countdownBadgeText: String {
        let days = daysRemaining
        if days == 0 {
            return "今天"
        } else if days > 0 {
            return "剩 \(days) 天"
        } else {
            return "已結束"
        }
    }
    
    public var countdownBadgeColorHex: String {
        let days = daysRemaining
        if days == 0 {
            return "#007AFF" // 今天用藍色高亮
        } else if days > 0 && days <= 3 {
            return "#5AC8FA" // 2-3天淺藍色
        } else if days > 3 && days <= 7 {
            return "#FFCC00" // 一週內金黃色
        } else {
            return "#8E8E93" // 其它灰色
        }
    }
    
    public var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: targetDate)
    }
}

// 單一標的歷史領息流水紀錄 (對應截圖 4「股息紀錄」)
public struct HoldingDividendHistory: Identifiable, Codable, Equatable {
    public var id: UUID
    public var symbol: String
    public var paymentDate: Date          // 股利發放日
    public var dividendPerShare: Double   // 配息金額 (元/股)
    public var sharesSnapshot: Int        // 除息股數
    public var totalReceived: Double      // 實領股息金額
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        paymentDate: Date,
        dividendPerShare: Double,
        sharesSnapshot: Int
    ) {
        self.id = id
        self.symbol = symbol
        self.paymentDate = paymentDate
        self.dividendPerShare = dividendPerShare
        self.sharesSnapshot = sharesSnapshot
        self.totalReceived = (Double(sharesSnapshot) * dividendPerShare).rounded()
    }
    
    public var paymentDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: paymentDate)
    }
}
