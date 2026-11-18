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
        PopularStockPreset(symbol: "00406A", name: "主動中信台灣收益", frequency: .monthly, stockType: .etf, defaultPrice: 6.85),
        PopularStockPreset(symbol: "00406", name: "主動中信台灣收益(掩護性買權)", frequency: .monthly, stockType: .etf, defaultPrice: 6.85),
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
        PopularStockPreset(symbol: "7781", name: "昕力資", frequency: .annual, stockType: .stock, defaultPrice: 19.9),
        PopularStockPreset(symbol: "2881", name: "富邦金", frequency: .annual, stockType: .stock, defaultPrice: 92.0),
        PopularStockPreset(symbol: "2882", name: "國泰金", frequency: .annual, stockType: .stock, defaultPrice: 68.0),
        PopularStockPreset(symbol: "2891", name: "中信金", frequency: .annual, stockType: .stock, defaultPrice: 38.0)
    ]
}

/// 單筆買入 / 加碼存股批次紀錄（用以精準計算各月份除息可參與股數）
public struct HoldingLot: Identifiable, Codable, Equatable {
    public var id: UUID
    public var buyDate: Date
    public var shares: Int
    public var price: Double
    public var note: String

    public init(
        id: UUID = UUID(),
        buyDate: Date = Date(),
        shares: Int,
        price: Double,
        note: String = "買入"
    ) {
        self.id = id
        self.buyDate = buyDate
        self.shares = max(0, shares)
        self.price = max(0.0, price)
        self.note = note
    }

    public var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: buyDate)
    }

    public var shortDateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f.string(from: buyDate)
    }

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
    public var purchaseDate: Date          // 初始/最早買入日期
    public var lots: [HoldingLot]          // 買入與加碼批次明細
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
        purchaseDate: Date? = nil,
        lots: [HoldingLot]? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 自動校正 00406A / 00406 或包含中信台灣收益/掩護性買權為月配
        if self.symbol == "00406A" || self.symbol == "00406" || self.name.contains("中信台灣收益") || self.name.contains("掩護性買權") {
            self.frequency = .monthly
        } else {
            self.frequency = frequency
        }
        let initDate = purchaseDate ?? updatedAt
        let clampedShares = max(0, shares)
        if let providedLots = lots, !providedLots.isEmpty {
            let sorted = providedLots.sorted { $0.buyDate < $1.buyDate }
            self.lots = sorted
            let sumShares = sorted.reduce(0) { $0 + $1.shares }
            let sumCost = sorted.reduce(0.0) { $0 + Double($1.shares) * $1.price }
            self.shares = sumShares
            self.averageCost = sumShares > 0 ? ((sumCost / Double(sumShares)) * 100.0).rounded() / 100.0 : averageCost
            self.purchaseDate = sorted.first?.buyDate ?? initDate
        } else {
            self.shares = clampedShares
            self.averageCost = averageCost
            self.purchaseDate = initDate
            self.lots = clampedShares > 0
                ? [HoldingLot(buyDate: initDate, shares: clampedShares, price: averageCost, note: "初始買入")]
                : []
        }
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
        case stockType, brokerFeeDiscount, totalDividendsReceived, dividendCount, brokerage
        case purchaseDate, lots, updatedAt
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
        let upd = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.updatedAt = upd
        let pDate = try container.decodeIfPresent(Date.self, forKey: .purchaseDate) ?? upd
        let decodedLots = try container.decodeIfPresent([HoldingLot].self, forKey: .lots) ?? []
        if decodedLots.isEmpty && self.shares > 0 {
            self.lots = [HoldingLot(buyDate: pDate, shares: self.shares, price: self.averageCost, note: "既有庫存")]
            self.purchaseDate = pDate
        } else {
            self.lots = decodedLots.sorted { $0.buyDate < $1.buyDate }
            self.purchaseDate = self.lots.first?.buyDate ?? pDate
        }
    }
    
    // 定期定額加碼存股試算：寫入加碼日期批次並加權更新均價與總股數
    public mutating func addDCA(newShares: Int, buyPrice: Double, buyDate: Date = Date(), note: String = "加碼買進") {
        guard newShares > 0 else { return }
        if lots.isEmpty && shares > 0 {
            lots = [HoldingLot(buyDate: purchaseDate, shares: shares, price: averageCost, note: "初始買入")]
        }
        lots.append(HoldingLot(buyDate: buyDate, shares: newShares, price: buyPrice, note: note))
        lots.sort { $0.buyDate < $1.buyDate }
        syncFromLots()
        self.currentPrice = buyPrice
        self.updatedAt = Date()
    }

    /// 依批次明細重新計算總股數、加權均價與最早買入日期
    public mutating func syncFromLots() {
        lots = lots.filter { $0.shares > 0 }.sorted { $0.buyDate < $1.buyDate }
        let total = lots.reduce(0) { $0 + $1.shares }
        let cost = lots.reduce(0.0) { $0 + Double($1.shares) * $1.price }
        self.shares = total
        if total > 0 {
            self.averageCost = ((cost / Double(total)) * 100.0).rounded() / 100.0
            self.purchaseDate = lots.first?.buyDate ?? purchaseDate
        }
        self.updatedAt = Date()
    }

    // MARK: - 除息基準日與可參與配息股數計算
    /// 取得該標的於指定年月的除息截算日（須於此日「前」買進，才計入該月配息）
    public static func exDividendCutoffDate(
        for symbol: String,
        year: Int,
        month: Int,
        events: [DividendEvent] = []
    ) -> Date {
        let cal = Calendar.current
        if let exEvt = events.first(where: {
            $0.symbol == symbol &&
            $0.eventType == .exDividendDate &&
            cal.component(.year, from: $0.targetDate) == year &&
            cal.component(.month, from: $0.targetDate) == month
        }) {
            return cal.startOfDay(for: exEvt.targetDate)
        }
        if let lastEvt = events.first(where: {
            $0.symbol == symbol &&
            $0.eventType == .lastBuyDate &&
            cal.component(.year, from: $0.targetDate) == year &&
            cal.component(.month, from: $0.targetDate) == month
        }) {
            let dayAfter = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastEvt.targetDate)) ?? lastEvt.targetDate
            return dayAfter
        }
        // 預設月配 / ETF 月初除息截算：每月 3 號（3 號前買進計入當月，例如 10/20 計入 11 月；11/04 買進則順延至 12 月配息公布領取）
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 3
        return cal.date(from: comps) ?? Date()
    }

    /// 指定年月底為止實際持有總股數（含本月除息後新買加碼）
    public func ownedShares(asOfEndOfYear year: Int, month: Int) -> Int {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let monthStart = cal.date(from: comps),
              let interval = cal.dateInterval(of: .month, for: monthStart) else {
            return shares
        }
        let effectiveLots = lots.isEmpty && shares > 0
            ? [HoldingLot(buyDate: purchaseDate, shares: shares, price: averageCost)]
            : lots
        return effectiveLots
            .filter { cal.startOfDay(for: $0.buyDate) < interval.end }
            .reduce(0) { $0 + $1.shares }
    }

    /// 指定年月底為止實際持有本金成本（依各批次成交價累計）
    public func costPrincipal(asOfEndOfYear year: Int, month: Int) -> Double {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let monthStart = cal.date(from: comps),
              let interval = cal.dateInterval(of: .month, for: monthStart) else {
            return totalCostPrincipal
        }
        let effectiveLots = lots.isEmpty && shares > 0
            ? [HoldingLot(buyDate: purchaseDate, shares: shares, price: averageCost)]
            : lots
        return effectiveLots
            .filter { cal.startOfDay(for: $0.buyDate) < interval.end }
            .reduce(0.0) { $0 + Double($1.shares) * $1.price }
    }

    /// 指定年月真正「趕上除息截算日、可參與當月配息」的有效股數
    public func eligibleSharesForMonth(year: Int, month: Int, events: [DividendEvent] = []) -> Int {
        let cal = Calendar.current
        let cutoff = Self.exDividendCutoffDate(for: symbol, year: year, month: month, events: events)
        let effectiveLots = lots.isEmpty && shares > 0
            ? [HoldingLot(buyDate: purchaseDate, shares: shares, price: averageCost)]
            : lots
        return effectiveLots
            .filter { cal.startOfDay(for: $0.buyDate) < cutoff }
            .reduce(0) { $0 + $1.shares }
    }

    /// 本月已持有但錯過本月除息（須待下月配息公告才能領取）的股數
    public func pendingNextMonthShares(asOf date: Date = Date(), events: [DividendEvent] = []) -> Int {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let owned = ownedShares(asOfEndOfYear: y, month: m)
        let eligible = eligibleSharesForMonth(year: y, month: m, events: events)
        return max(0, owned - eligible)
    }

    public var earliestBuyDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: lots.first?.buyDate ?? purchaseDate)
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
