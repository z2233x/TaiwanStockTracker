import Foundation

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
    public var symbol: String          // 代號 (如 2330, 00878)
    public var name: String            // 名稱
    public var shares: Int             // 股數 (1張 = 1,000股)
    public var averageCost: Double     // 買入均價
    public var currentPrice: Double    // 目前市價
    public var previousClose: Double   // 昨收價
    public var stockType: StockType
    public var brokerFeeDiscount: Double // 手續費折讓 (0.6 代表 6 折)
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        shares: Int,
        averageCost: Double,
        currentPrice: Double,
        previousClose: Double = 0.0,
        stockType: StockType = .stock,
        brokerFeeDiscount: Double = 0.6,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shares = max(0, shares)
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.previousClose = previousClose
        self.stockType = stockType
        self.brokerFeeDiscount = brokerFeeDiscount
        self.updatedAt = updatedAt
    }
    
    // 買進本金與手續費 (低消 20 元，0 股時手續費為 0)
    public var totalCostPrincipal: Double { Double(shares) * averageCost }
    public var buyFee: Double {
        guard shares > 0 else { return 0.0 }
        return max(20.0, (totalCostPrincipal * 0.001425 * brokerFeeDiscount).rounded())
    }
    public var totalCostWithFee: Double { totalCostPrincipal + buyFee }
    
    // 現前市值與預估賣出成本
    public var marketValue: Double { Double(shares) * currentPrice }
    public var estimatedSellFee: Double {
        guard shares > 0 && marketValue > 0 else { return 0.0 }
        return max(20.0, (marketValue * 0.001425 * brokerFeeDiscount).rounded())
    }
    public var estimatedTax: Double {
        guard shares > 0 else { return 0.0 }
        return (marketValue * stockType.taxRate).rounded()
    }
    
    // 淨未實現損益 (扣除賣出手續費與證交稅)
    public var unrealizedProfit: Double {
        guard shares > 0 else { return 0.0 }
        return marketValue - totalCostWithFee - estimatedSellFee - estimatedTax
    }
    
    // 報酬率 (%)
    public var returnRate: Double {
        guard totalCostWithFee > 0 else { return 0.0 }
        return (unrealizedProfit / totalCostWithFee) * 100.0
    }
    
    // 今日單日損益金額與漲跌幅
    public var dailyProfitAmount: Double {
        guard shares > 0 && previousClose > 0 else { return 0.0 }
        return Double(shares) * (currentPrice - previousClose)
    }
    public var dailyChangePercentage: Double {
        guard previousClose > 0 else { return 0.0 }
        return ((currentPrice - previousClose) / previousClose) * 100.0
    }
}
