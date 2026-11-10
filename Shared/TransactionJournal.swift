import Foundation

public enum TransactionType: String, Codable, CaseIterable {
    case buy = "買"
    case sell = "賣"
    case cashDividend = "息"
    case stockDividend = "股"
    
    public var badgeColorHex: String {
        switch self {
        case .buy: return "#FF9500"      // 橘色 (符合截圖橘色買字)
        case .sell: return "#34C759"     // 綠色
        case .cashDividend: return "#007AFF" // 藍色
        case .stockDividend: return "#AF52DE" // 紫色
        }
    }
}

public struct JournalEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var type: TransactionType
    public var date: Date
    public var price: Double          // 買入/賣出單價 (元)
    public var shares: Int            // 股數 (1,000 股 = 1 張)
    public var fee: Double            // 券商手續費
    public var tax: Double            // 證交稅
    public var note: String
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        type: TransactionType = .buy,
        date: Date = Date(),
        price: Double,
        shares: Int,
        fee: Double = 0.0,
        tax: Double = 0.0,
        note: String = ""
    ) {
        self.id = id
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.date = date
        self.price = price
        self.shares = max(0, shares)
        self.fee = fee
        self.tax = tax
        self.note = note
    }
    
    // 總交易金額
    public var totalAmount: Double {
        switch type {
        case .buy:
            return (price * Double(shares)) + fee
        case .sell:
            return (price * Double(shares)) - fee - tax
        case .cashDividend:
            return price * Double(shares)
        case .stockDividend:
            return 0.0
        }
    }
    
    // 張數顯示字串 (例如: 1張 或 500股)
    public var lotsText: String {
        let lots = shares / 1000
        let odd = shares % 1000
        if lots > 0 && odd > 0 {
            return "\(lots)張\(odd)股"
        } else if lots > 0 {
            return "\(lots)張"
        } else {
            return "\(odd)股"
        }
    }
    
    public var sharesDisplay: String { lotsText }
    
    public var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
