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

public struct PopularStockPreset: Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let frequency: FrequencyType
    public let stockType: StockType
    public let defaultPrice: Double
    
    public static let allPresets: [PopularStockPreset] = [
        PopularStockPreset(symbol: "00406", name: "富邦科技高息(掩護性買權)", frequency: .monthly, stockType: .etf, defaultPrice: 15.0),
        PopularStockPreset(symbol: "0056", name: "元大高股息", frequency: .quarterly, stockType: .etf, defaultPrice: 37.5),
        PopularStockPreset(symbol: "00878", name: "國泰永續高股息", frequency: .quarterly, stockType: .etf, defaultPrice: 22.8),
        PopularStockPreset(symbol: "00919", name: "群益台灣精選高息", frequency: .quarterly, stockType: .etf, defaultPrice: 24.2),
        PopularStockPreset(symbol: "00929", name: "復華台灣科技優息", frequency: .monthly, stockType: .etf, defaultPrice: 19.5),
        PopularStockPreset(symbol: "0050", name: "元大台灣50", frequency: .semiannual, stockType: .etf, defaultPrice: 195.0),
        PopularStockPreset(symbol: "006208", name: "富邦台50", frequency: .semiannual, stockType: .etf, defaultPrice: 115.0),
        PopularStockPreset(symbol: "00940", name: "元大台灣價值高息", frequency: .monthly, stockType: .etf, defaultPrice: 9.8),
        PopularStockPreset(symbol: "00939", name: "統一台灣高息動能", frequency: .monthly, stockType: .etf, defaultPrice: 14.5),
        PopularStockPreset(symbol: "00915", name: "凱基優選高股息30", frequency: .quarterly, stockType: .etf, defaultPrice: 26.8),
        PopularStockPreset(symbol: "00713", name: "元大台灣高息低波", frequency: .quarterly, stockType: .etf, defaultPrice: 57.0),
        PopularStockPreset(symbol: "2330", name: "台積電", frequency: .quarterly, stockType: .stock, defaultPrice: 1050.0),
        PopularStockPreset(symbol: "2454", name: "聯發科", frequency: .semiannual, stockType: .stock, defaultPrice: 1300.0),
        PopularStockPreset(symbol: "2881", name: "富邦金", frequency: .annual, stockType: .stock, defaultPrice: 92.0),
        PopularStockPreset(symbol: "2882", name: "國泰金", frequency: .annual, stockType: .stock, defaultPrice: 68.0),
        PopularStockPreset(symbol: "2891", name: "中信金", frequency: .annual, stockType: .stock, defaultPrice: 38.0)
    ]
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
    public var brokerage: String           // 所屬券商 (如 元大證券、國泰證券)
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
        brokerage: String = "元大證券",
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
        self.brokerage = brokerage
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, symbol, name, frequency, shares, averageCost, currentPrice, previousClose
        case stockType, brokerFeeDiscount, totalDividendsReceived, dividendCount, brokerage, updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.name = try container.decode(String.self, forKey: .name)
        self.frequency = try container.decodeIfPresent(FrequencyType.self, forKey: .frequency) ?? .quarterly
        self.shares = try container.decodeIfPresent(Int.self, forKey: .shares) ?? 0
        self.averageCost = try container.decodeIfPresent(Double.self, forKey: .averageCost) ?? 0.0
        self.currentPrice = try container.decodeIfPresent(Double.self, forKey: .currentPrice) ?? 0.0
        self.previousClose = try container.decodeIfPresent(Double.self, forKey: .previousClose) ?? self.currentPrice
        self.stockType = try container.decodeIfPresent(StockType.self, forKey: .stockType) ?? .etf
        self.brokerFeeDiscount = try container.decodeIfPresent(Double.self, forKey: .brokerFeeDiscount) ?? 0.6
        self.totalDividendsReceived = try container.decodeIfPresent(Double.self, forKey: .totalDividendsReceived) ?? 0.0
        self.dividendCount = try container.decodeIfPresent(Int.self, forKey: .dividendCount) ?? 0
        self.brokerage = try container.decodeIfPresent(String.self, forKey: .brokerage) ?? "元大證券"
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
    
    // 定期定額加碼存股試算：加權更新均價與股數
    public mutating func addDCA(newShares: Int, buyPrice: Double) {
        guard newShares > 0 else { return }
        let currentCost = Double(shares) * averageCost
        let addedCost = Double(newShares) * buyPrice
        let total = shares + newShares
        let newAverageCost = (currentCost + addedCost) / Double(total)
        
        self.shares = total
        self.averageCost = (newAverageCost * 100.0).rounded() / 100.0
        self.currentPrice = buyPrice
        self.updatedAt = Date()
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
    
    // 未實現報酬率別名
    public var unrealizedProfitRate: Double { returnRate }
    
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
