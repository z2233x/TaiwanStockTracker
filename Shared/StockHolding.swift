import Foundation

public enum FrequencyType: String, Codable, CaseIterable {
    case monthly = "月配"
    case bimonthly = "雙月配"
    case quarterly = "季配"
    case semiannual = "半年配"
    case annual = "年配"
    
    public var badgeColorHex: String {
        switch self {
        case .monthly: return "#007AFF"     // 藍色
        case .bimonthly: return "#5856D6"   // 紫色
        case .quarterly: return "#FF9500"   // 橘色
        case .semiannual: return "#34C759"  // 綠色
        case .annual: return "#AF52DE"      // 深紫
        }
    }
}

public enum StockType: String, Codable, CaseIterable {
    case stock = "一般個股"
    case etf = "ETF指數型"
    
    public var taxRate: Double {
        switch self {
        case .stock: return 0.003  // 證交稅 0.3%
        case .etf: return 0.001    // ETF 證交稅 0.1%
        }
    }
}

public struct StockHolding: Identifiable, Codable, Equatable {
    public var id: UUID
    public var symbol: String              // 代號 (如 0056, 00878, 2330)
    public var name: String                // 名稱 (如 元大高股息)
    public var frequency: FrequencyType    // 配息頻率
    public var shares: Int                 // 總股數
    public var averageCost: Double         // 買入均價
    public var currentPrice: Double        // 目前現價
    public var previousClose: Double       // 昨收價
    public var stockType: StockType
    public var brokerFeeDiscount: Double   // 手續費折讓 (預設 0.6 代表 6 折)
    public var totalDividendsReceived: Double // 累計已領股息
    public var dividendCount: Int          // 累計領息次數
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        frequency: FrequencyType = .quarterly,
        shares: Int,
        averageCost: Double,
        currentPrice: Double,
        previousClose: Double = 0.0,
        stockType: StockType = .etf,
        brokerFeeDiscount: Double = 0.6,
        totalDividendsReceived: Double = 0.0,
        dividendCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frequency = frequency
        self.shares = max(0, shares)
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.previousClose = previousClose > 0 ? previousClose : currentPrice
        self.stockType = stockType
        self.brokerFeeDiscount = brokerFeeDiscount
        self.totalDividendsReceived = totalDividendsReceived
        self.dividendCount = dividendCount
        self.updatedAt = updatedAt
    }
    
    // 總成本本金 (不含買進手續費)
    public var totalCostPrincipal: Double { Double(shares) * averageCost }
    
    // 買進手續費 (低消 20 元)
    public var buyFee: Double {
        guard shares > 0 else { return 0.0 }
        return max(20.0, (totalCostPrincipal * 0.001425 * brokerFeeDiscount).rounded())
    }
    
    // 含手續費總成本
    public var totalCostWithFee: Double { totalCostPrincipal + buyFee }
    
    // 現前市值
    public var marketValue: Double { Double(shares) * currentPrice }
    
    // 預估賣出手續費與證交稅
    public var estimatedSellFee: Double {
        guard shares > 0 && marketValue > 0 else { return 0.0 }
        return max(20.0, (marketValue * 0.001425 * brokerFeeDiscount).rounded())
    }
    
    public var estimatedTax: Double {
        guard shares > 0 else { return 0.0 }
        return (marketValue * stockType.taxRate).rounded()
    }
    
    // 未實現價差獲利 (市值 - 成本 - 賣出手續費 - 證交稅)
    public var unrealizedProfit: Double {
        guard shares > 0 else { return 0.0 }
        return marketValue - totalCostWithFee - estimatedSellFee - estimatedTax
    }
    
    // 報酬率 (%)
    public var returnRate: Double {
        guard totalCostWithFee > 0 else { return 0.0 }
        return (unrealizedProfit / totalCostWithFee) * 100.0
    }
    
    // 今日損益與漲跌幅
    public var todayProfitAmount: Double {
        guard shares > 0 && previousClose > 0 else { return 0.0 }
        return Double(shares) * (currentPrice - previousClose)
    }
    
    public var todayChangePercentage: Double {
        guard previousClose > 0 else { return 0.0 }
        return ((currentPrice - previousClose) / previousClose) * 100.0
    }
}
