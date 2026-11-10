import Foundation

public enum DividendEventType: String, Codable, CaseIterable {
    // 1. 除權息與股利
    case exDividendDate = "除息日"
    case exRightsDate = "除權日"
    case paymentDate = "股利發放日"
    case lastBuyDate = "最後購買日"
    
    // 2. 台股重大行事曆 (股東會、財報、月營收、法說會)
    case shareholdersMeeting = "股東會"
    case financialReport = "財報公告"
    case monthlyRevenue = "月營收公告"
    case investorConference = "法說會"
    case bookClosure = "停止過戶"
    
    public var badgeColorHex: String {
        switch self {
        case .exDividendDate: return "#007AFF"        // 經典深藍
        case .exRightsDate: return "#5AC8FA"          // 天藍色
        case .paymentDate: return "#34C759"           // 綠色
        case .lastBuyDate: return "#00C7BE"           // 青綠色
        case .shareholdersMeeting: return "#AF52DE"   // 紫色 (股東會)
        case .financialReport: return "#FF9500"       // 橘色 (財報)
        case .monthlyRevenue: return "#30D158"        // 翠綠色 (月營收)
        case .investorConference: return "#FF2D55"    // 緋紅色 (法說會)
        case .bookClosure: return "#8E8E93"           // 灰色
        }
    }
    
    public var iconName: String {
        switch self {
        case .exDividendDate: return "dollarsign.circle.fill"
        case .exRightsDate: return "gift.fill"
        case .paymentDate: return "banknote.fill"
        case .lastBuyDate: return "cart.fill"
        case .shareholdersMeeting: return "person.3.fill"
        case .financialReport: return "chart.bar.doc.horizontal.fill"
        case .monthlyRevenue: return "chart.line.uptrend.xyaxis"
        case .investorConference: return "mic.fill"
        case .bookClosure: return "lock.fill"
        }
    }
    
    public var isDividendRelated: Bool {
        self == .exDividendDate || self == .exRightsDate || self == .paymentDate || self == .lastBuyDate
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
    public var note: String                 // 行事曆補充備註 (如: Q3法說會, 114年常會, 10月合併營收)
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        frequency: FrequencyType = .quarterly,
        eventType: DividendEventType = .exDividendDate,
        targetDate: Date,
        cashPerShare: Double = 0.0,
        stockPerShare: Double = 0.0,
        sharesSnapshot: Int = 0,
        note: String = ""
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
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, symbol, name, frequency, eventType, targetDate, cashPerShare, stockPerShare, sharesSnapshot, note
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.symbol = try c.decode(String.self, forKey: .symbol)
        self.name = try c.decode(String.self, forKey: .name)
        self.frequency = try c.decodeIfPresent(FrequencyType.self, forKey: .frequency) ?? .quarterly
        self.eventType = try c.decodeIfPresent(DividendEventType.self, forKey: .eventType) ?? .exDividendDate
        self.targetDate = try c.decode(Date.self, forKey: .targetDate)
        self.cashPerShare = try c.decodeIfPresent(Double.self, forKey: .cashPerShare) ?? 0.0
        self.stockPerShare = try c.decodeIfPresent(Double.self, forKey: .stockPerShare) ?? 0.0
        self.sharesSnapshot = try c.decodeIfPresent(Int.self, forKey: .sharesSnapshot) ?? 0
        self.note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
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

public typealias StockCalendarEvent = DividendEvent

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
