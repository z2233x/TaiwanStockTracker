import Foundation

// MARK: - 股息四大法定來源類別
public enum DividendIncomeSourceType: String, CaseIterable, Codable {
    case optionPremium76 = "選擇權權利金 (76國內財產交易)" // 掩護性買權 (Covered Call) 權利金收入 + 資本利得
    case dividend54C = "股利所得 (54C)"             // 上市櫃公司發放之現金股利
    case capitalReserve = "收益平準金"             // 本金返還
    case capitalSurplus = "資本公積"               // 公司資本公積發放
    
    public var shortName: String {
        switch self {
        case .optionPremium76: return "76 權利金/財產交易"
        case .dividend54C: return "54C 股利所得"
        case .capitalReserve: return "收益平準金"
        case .capitalSurplus: return "資本公積"
        }
    }
    
    public var badgeColorHex: String {
        switch self {
        case .optionPremium76: return "#AF52DE" // 紫色 (選擇權權利金)
        case .dividend54C: return "#007AFF"     // 藍色 (54C 股利)
        case .capitalReserve: return "#FF9500"  // 橘色 (平準金)
        case .capitalSurplus: return "#34C759"  // 綠色 (公積)
        }
    }
    
    public var isTaxExempt: Bool {
        // 76 國內財產交易停徵所得稅、收益平準金(本金)、資本公積均免綜所稅與二代健保
        switch self {
        case .optionPremium76, .capitalReserve, .capitalSurplus: return true
        case .dividend54C: return false
        }
    }
    
    public var taxDescription: String {
        switch self {
        case .optionPremium76:
            return "停徵所得稅・免計入個人綜所稅・免扣 2.11% 二代健保補充保費"
        case .dividend54C:
            return "計入個人綜所稅 (可抵減 8.5% 或 28% 分開計稅)・單筆滿 2 萬扣 2.11% 補充保費"
        case .capitalReserve:
            return "屬於投資本金返還・免綜所稅・免扣二代健保補充保費"
        case .capitalSurplus:
            return "法定資本公積・免綜所稅・免扣二代健保補充保費"
        }
    }
}

// MARK: - 標的配息策略類型
public enum DividendStrategyType: String, CaseIterable, Codable {
    case coveredCall = "掩護性買權 (Covered Call)"
    case highDividend = "高股息 (含平準金)"
    case marketWeight = "市值指數型"
    case equityStock = "一般個股 (純54C)"
    
    public var badgeColorHex: String {
        switch self {
        case .coveredCall: return "#AF52DE"
        case .highDividend: return "#FF9500"
        case .marketWeight: return "#007AFF"
        case .equityStock: return "#5856D6"
        }
    }
}

// MARK: - 單一持股股息成分畫像
public struct HoldingDividendProfile: Identifiable, Codable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let strategy: DividendStrategyType
    public let estimatedYield: Double // 年化預估殖利率 (如 0.22 代表 22%)
    public let defaultCashDividendPerShare: Double? // 每股單次預估配息 (如 00406A 預設 0.138 元/股)
    public let ratio76: Double        // 選擇權權利金與財產交易 (76) 佔比 (0.0 ~ 1.0)
    public let ratio54C: Double       // 股利所得 (54C) 佔比
    public let ratioReserve: Double   // 收益平準金佔比
    public let ratioSurplus: Double   // 資本公積佔比
    public let notes: String          // 特色說明
    
    public init(
        symbol: String,
        name: String,
        strategy: DividendStrategyType,
        estimatedYield: Double,
        defaultCashDividendPerShare: Double? = nil,
        ratio76: Double,
        ratio54C: Double,
        ratioReserve: Double,
        ratioSurplus: Double,
        notes: String
    ) {
        self.symbol = symbol
        self.name = name
        self.strategy = strategy
        self.estimatedYield = estimatedYield
        self.defaultCashDividendPerShare = defaultCashDividendPerShare
        self.ratio76 = ratio76
        self.ratio54C = ratio54C
        self.ratioReserve = ratioReserve
        self.ratioSurplus = ratioSurplus
        self.notes = notes
    }
}

// MARK: - 單一持股推算結果
public struct HoldingDividendCalculation: Identifiable {
    public var id: String { holding.symbol }
    public let holding: StockHolding
    public let profile: HoldingDividendProfile
    public let eligibleSharesNow: Int        // 本月已趕上除息基準日之有效股數
    public let pendingNextMonthShares: Int   // 本月除息後加碼、須待下月配息公布領取之股數
    public let monthlyDividend: Double       // 本月實際可領預估月股息 (依 eligibleSharesNow，含當月已除權息配息)
    public let fullMonthlyDividend: Double   // 下期含新加碼滿倉預估月股息
    public let annualDividend: Double        // 滿倉推算年化股息
    public let effectiveAnnualYield: Double  // 實質年化殖利率
    public let amount76Monthly: Double       // 每月 76 權利金金額
    public let amount54CMonthly: Double      // 每月 54C 股利金額
    public let amountReserveMonthly: Double  // 每月平準金金額
    public let amountSurplusMonthly: Double  // 每月公積金額
    public let taxExemptPercentage: Double   // 免稅比例 (%)
    public let singleDistribution54C: Double // 單次配息推算 54C 金額 (檢測二代健保)
    public let isAboveNhiThreshold: Bool     // 是否單筆 54C 達 2 萬二代健保門檻
    public let announcedExDateString: String?          // 本月公告之除權息日 (如 "2026-11-17")
    public let announcedCashPerShare: Double?          // 本月公告之每股配息金額 (如 3.88)
    public let isExDividendReachedInMonth: Bool        // 本月除權息日是否已到並計入當月股息
    public let upcomingExDividendAmountInMonth: Double // 本月已公告但尚未到達除權息日之待除息金額
}

// MARK: - 全體持股投資組合股息來源彙整報告
public struct PortfolioDividendSourceSummary {
    public let totalMonthlyDividend: Double             // 本月實際可領預估月配息總額
    public let totalFullPositionMonthlyDividend: Double // 含本月新加碼後之滿倉預估月配息
    public let totalPendingMonthlyDividend: Double      // 須待下月配息公布才領取之新加碼預估月配息
    public let totalPendingShares: Int                  // 須待下月配息公布之總股數
    public let totalAnnualDividend: Double              // 總預估年被動股息
    public let total76Amount: Double                    // 選擇權權利金(76)總金額
    public let total54CAmount: Double                   // 54C股利總金額
    public let totalReserveAmount: Double               // 收益平準金總金額
    public let totalSurplusAmount: Double               // 資本公積總金額
    
    public let total76Percent: Double            // 76 佔比 (%)
    public let total54CPercent: Double           // 54C 佔比 (%)
    public let totalReservePercent: Double       // 平準金佔比 (%)
    public let totalSurplusPercent: Double       // 公積佔比 (%)
    public let taxExemptPercent: Double          // 總免稅/免二代健保比例 (%)
    
    public let hasCoveredCallHoldings: Bool      // 是否持有掩護性買權標的 (如 00406)
    public let coveredCallMonthlyAmount: Double  // 掩護性買權標的貢獻之月息
    public let estimatedAnnualNhiSaved: Double   // 藉由 76 權利金與平準金免除之二代健保保費推估 (2.11%)
    public let holdingsCalculations: [HoldingDividendCalculation]
}

// MARK: - 股息來源分析引擎服務
public final class DividendSourceService {
    public static let shared = DividendSourceService()
    
    private init() {}
    
    /// 取得標的股息畫像 (含 00406 掩護性買權及主流高股息、市值型、個股)
    public func getProfile(for symbol: String, name: String = "", stockType: StockType = .etf) -> HoldingDividendProfile {
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 掩護性買權 (Covered Call) 標的辨識 (以 00406A / 00406 或關鍵字為首)
        if sym == "00406A" ||
           sym == "00406" ||
           cleanName.contains("中信台灣收益") ||
           cleanName.contains("掩護性買權") ||
           cleanName.contains("選擇權") ||
           cleanName.contains("Covered Call") ||
           cleanName.contains("權利金") ||
           cleanName.contains("CC") {
            return HoldingDividendProfile(
                symbol: sym,
                name: cleanName.isEmpty ? "主動中信台灣收益" : cleanName,
                strategy: .coveredCall,
                estimatedYield: 0.22, // 最新每股配息 0.138 元，年化殖利率約 22%
                defaultCashDividendPerShare: 0.138, // 最新預計每股月配 0.138 元 (140,433 股約 19,380 元/月)
                ratio76: 0.65,         // 65% 賣出買權權利金收入 (76 財產交易所得)
                ratio54C: 0.15,        // 15% 傳統 54C 股票股利
                ratioReserve: 0.18,    // 18% 收益平準金
                ratioSurplus: 0.02,    // 2% 資本公積
                notes: "最新預計每股月配 0.138 元！賣出選擇權權利金收入佔 65%，屬 76 國內財產交易所得，停徵所得稅且免扣二代健保！"
            )
        }
        
        // 2. 知名高股息 ETF (含收益平準金與資本利得拆解，提供最新每股配息)
        switch sym {
        case "00919":
            return HoldingDividendProfile(symbol: sym, name: "群益台灣精選高息", strategy: .highDividend, estimatedYield: 0.102, defaultCashDividendPerShare: 1.10, ratio76: 0.28, ratio54C: 0.32, ratioReserve: 0.38, ratioSurplus: 0.02, notes: "收益平準金與已實現資本利得佔比達 68%，有效降低 54C 綜所稅負擔")
        case "00929":
            return HoldingDividendProfile(symbol: sym, name: "復華台灣科技優息", strategy: .highDividend, estimatedYield: 0.082, defaultCashDividendPerShare: 0.38, ratio76: 0.20, ratio54C: 0.40, ratioReserve: 0.38, ratioSurplus: 0.02, notes: "月月配息，平準金機制平衡發放穩定度")
        case "0056":
            return HoldingDividendProfile(symbol: sym, name: "元大高股息", strategy: .highDividend, estimatedYield: 0.085, defaultCashDividendPerShare: 1.72, ratio76: 0.30, ratio54C: 0.35, ratioReserve: 0.33, ratioSurplus: 0.02, notes: "老牌高股息，資本利得與平準金合計免稅達 65%")
        case "00878":
            return HoldingDividendProfile(symbol: sym, name: "國泰永續高股息", strategy: .highDividend, estimatedYield: 0.078, defaultCashDividendPerShare: 1.25, ratio76: 0.22, ratio54C: 0.42, ratioReserve: 0.34, ratioSurplus: 0.02, notes: "ESG 兼顧穩健息收與平準金保護")
        case "00915":
            return HoldingDividendProfile(symbol: sym, name: "凱基優選高股息30", strategy: .highDividend, estimatedYield: 0.095, defaultCashDividendPerShare: 0.60, ratio76: 0.35, ratio54C: 0.28, ratioReserve: 0.35, ratioSurplus: 0.02, notes: "高資本利得成分，免稅比重高")
        case "00713":
            return HoldingDividendProfile(symbol: sym, name: "元大台灣高息低波", strategy: .highDividend, estimatedYield: 0.072, defaultCashDividendPerShare: 1.25, ratio76: 0.25, ratio54C: 0.40, ratioReserve: 0.33, ratioSurplus: 0.02, notes: "低波動防禦型，配息平準金兼備")
        case "00940":
            return HoldingDividendProfile(symbol: sym, name: "元大台灣價值高息", strategy: .highDividend, estimatedYield: 0.065, defaultCashDividendPerShare: 0.06, ratio76: 0.15, ratio54C: 0.45, ratioReserve: 0.38, ratioSurplus: 0.02, notes: "巴菲特價值選股月配")
        case "00939":
            return HoldingDividendProfile(symbol: sym, name: "統一台灣高息動能", strategy: .highDividend, estimatedYield: 0.062, defaultCashDividendPerShare: 0.063, ratio76: 0.18, ratio54C: 0.44, ratioReserve: 0.36, ratioSurplus: 0.02, notes: "夏普值動能選股月配")
            
        // 3. 市值型 ETF (如 0050, 006208)
        case "0050", "006208", "00692", "00850":
            let dps: Double? = (sym == "006208" ? 3.88 : (sym == "0050" ? 1.0 : nil))
            return HoldingDividendProfile(symbol: sym, name: cleanName.isEmpty ? "市值指數ETF" : cleanName, strategy: .marketWeight, estimatedYield: 0.035, defaultCashDividendPerShare: dps, ratio76: 0.08, ratio54C: 0.90, ratioReserve: 0.0, ratioSurplus: 0.02, notes: "以成分股現股現金股利 (54C) 為主要收益來源")
            
        default:
            // 4. 一般個股 / 金融股 / 科技股 (2330, 2454, 金融股等)
            if stockType == .stock || (!sym.hasPrefix("00") && sym.count == 4) {
                let estYield: Double
                if sym.hasPrefix("28") {
                    estYield = 0.048 // 金融股平均約 4.8%
                } else if sym == "2330" {
                    estYield = 0.018 // 台積電約 1.8%
                } else if sym == "2454" {
                    estYield = 0.042 // 聯發科約 4.2%
                } else {
                    estYield = 0.045 // 一般現股預設 4.5%
                }
                return HoldingDividendProfile(
                    symbol: sym,
                    name: cleanName.isEmpty ? "上市櫃現股" : cleanName,
                    strategy: .equityStock,
                    estimatedYield: estYield,
                    defaultCashDividendPerShare: nil,
                    ratio76: 0.0,
                    ratio54C: 1.0, // 個股 100% 均為 54C 股利所得
                    ratioReserve: 0.0,
                    ratioSurplus: 0.0,
                    notes: "個別上市公司發放之現金股利，100% 全額屬 54C 股利所得"
                )
            } else {
                // 一般其他 ETF 預設
                return HoldingDividendProfile(
                    symbol: sym,
                    name: cleanName.isEmpty ? "ETF" : cleanName,
                    strategy: .highDividend,
                    estimatedYield: 0.070,
                    defaultCashDividendPerShare: nil,
                    ratio76: 0.20,
                    ratio54C: 0.45,
                    ratioReserve: 0.33,
                    ratioSurplus: 0.02,
                    notes: "ETF 綜合收益分配 (含 54C 股利、平準金與資本利得)"
                )
            }
        }
    }
    
    /// 依指定股數計算該標的等效單月股息（年化均攤基準）
    public func calculateMonthlyDividendAmount(for holding: StockHolding, shares: Int) -> Double {
        guard shares > 0 else { return 0.0 }
        let profile = getProfile(for: holding.symbol, name: holding.name, stockType: holding.stockType)
        if let dps = profile.defaultCashDividendPerShare, dps > 0 {
            switch holding.frequency {
            case .monthly:
                return Double(shares) * dps
            case .bimonthly:
                return (Double(shares) * dps * 6.0) / 12.0
            case .quarterly:
                return (Double(shares) * dps * 4.0) / 12.0
            case .semiannual:
                return (Double(shares) * dps * 2.0) / 12.0
            case .annual:
                return (Double(shares) * dps) / 12.0
            }
        }
        return (Double(shares) * holding.currentPrice * profile.estimatedYield) / 12.0
    }

    /// 依標的在特定 (year, month) 自己公布的除權息日與每股配息，計算當月實際配息金額
    /// - 當該月有公告除權息日（例如 006208 於 2026-11-17 除息 $3.88），且日期已到達除權息日 (`today >= exDate` 或過去月份)，當月直接計入實際除權息配息金額 `eligibleShares * cashPerShare`！
    public func calculateActualMonthDividend(
        for holding: StockHolding,
        year: Int,
        month: Int,
        eligibleShares: Int,
        events: [DividendEvent] = [],
        asOf today: Date = Date()
    ) -> (realizedInMonth: Double, upcomingInMonth: Double, exDateString: String?, cashPerShare: Double?, isExDateReached: Bool) {
        let cal = Calendar.current
        let todayY = cal.component(.year, from: today)
        let todayM = cal.component(.month, from: today)
        let isPastMonth = (year < todayY) || (year == todayY && month < todayM)

        if let announced = StockHolding.announcedDividendInMonth(for: holding.symbol, year: year, month: month, events: events),
           announced.cashPerShare > 0 {
            let amt = Double(max(0, eligibleShares)) * announced.cashPerShare
            let isReached = isPastMonth || (year == todayY && month == todayM && cal.startOfDay(for: today) >= cal.startOfDay(for: announced.exDate))
            if isReached {
                return (amt, 0.0, announced.exDateString, announced.cashPerShare, true)
            } else {
                return (0.0, amt, announced.exDateString, announced.cashPerShare, false)
            }
        }

        // 若該月無特定公告除息事件：月配息標的按單月常態配息計；季配/半年配/年配則該月無除息為 0
        if holding.frequency == .monthly {
            let profile = getProfile(for: holding.symbol, name: holding.name, stockType: holding.stockType)
            let amt = calculateMonthlyDividendAmount(for: holding, shares: eligibleShares)
            return (amt, 0.0, nil, profile.defaultCashDividendPerShare, true)
        }
        return (0.0, 0.0, nil, nil, false)
    }

    /// 計算單一持股之預估股息與各項來源 (納入買入／加碼日期 + 該股自訂公告除權息日，當月到除權息日即增加當月配息金額)
    public func calculateHoldingDividend(
        holding: StockHolding,
        asOf date: Date = Date(),
        events: [DividendEvent] = []
    ) -> HoldingDividendCalculation {
        let profile = getProfile(for: holding.symbol, name: holding.name, stockType: holding.stockType)
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let eligibleShares = holding.eligibleSharesForMonth(year: y, month: m, events: events)
        let pendingShares = max(0, holding.shares - eligibleShares)
        let totalVal = holding.marketValue

        let actualMonth = calculateActualMonthDividend(
            for: holding,
            year: y,
            month: m,
            eligibleShares: eligibleShares,
            events: events,
            asOf: date
        )
        let runRateEligible = calculateMonthlyDividendAmount(for: holding, shares: eligibleShares)
        let runRateFull = calculateMonthlyDividendAmount(for: holding, shares: holding.shares)

        // 當月實際可領股息：
        // - 若當月有該股公告之除權息且已達除權息日 (如 006208 於 11/17 除息)，直接計入當月除息金額 (eligibleShares * cashPerShare)
        // - 若為月配息且本月除息日尚未到，仍顯示本月應領金額；若為季配/半年配/年配且本月無除息，當月實領為 0 (年化仍計入 annualDividend)
        let monthly: Double
        let fullMonthly: Double
        if actualMonth.exDateString != nil {
            if actualMonth.isExDateReached {
                monthly = actualMonth.realizedInMonth
                fullMonthly = Double(holding.shares) * (actualMonth.cashPerShare ?? 0)
            } else if holding.frequency == .monthly {
                monthly = actualMonth.upcomingInMonth
                fullMonthly = Double(holding.shares) * (actualMonth.cashPerShare ?? 0)
            } else {
                monthly = 0.0
                fullMonthly = runRateFull
            }
        } else {
            monthly = (holding.frequency == .monthly) ? runRateEligible : 0.0
            fullMonthly = (holding.frequency == .monthly) ? runRateFull : 0.0
        }

        let annual = runRateFull * 12.0
        let effYield = totalVal > 0 ? (annual / totalVal) : profile.estimatedYield

        let amt76 = monthly * profile.ratio76
        let amt54C = monthly * profile.ratio54C
        let amtReserve = monthly * profile.ratioReserve
        let amtSurplus = monthly * profile.ratioSurplus
        let exemptPct = (profile.ratio76 + profile.ratioReserve + profile.ratioSurplus) * 100.0

        let timesPerYear: Double
        switch holding.frequency {
        case .monthly: timesPerYear = 12.0
        case .bimonthly: timesPerYear = 6.0
        case .quarterly: timesPerYear = 4.0
        case .semiannual: timesPerYear = 2.0
        case .annual: timesPerYear = 1.0
        }
        let singleDist54C = (annual * profile.ratio54C) / timesPerYear
        let isAboveNhi = singleDist54C >= 20000.0

        return HoldingDividendCalculation(
            holding: holding,
            profile: profile,
            eligibleSharesNow: eligibleShares,
            pendingNextMonthShares: pendingShares,
            monthlyDividend: monthly,
            fullMonthlyDividend: fullMonthly,
            annualDividend: annual,
            effectiveAnnualYield: effYield,
            amount76Monthly: amt76,
            amount54CMonthly: amt54C,
            amountReserveMonthly: amtReserve,
            amountSurplusMonthly: amtSurplus,
            taxExemptPercentage: exemptPct,
            singleDistribution54C: singleDist54C,
            isAboveNhiThreshold: isAboveNhi,
            announcedExDateString: actualMonth.exDateString,
            announcedCashPerShare: actualMonth.cashPerShare,
            isExDividendReachedInMonth: actualMonth.isExDateReached,
            upcomingExDividendAmountInMonth: actualMonth.upcomingInMonth
        )
    }

    /// 計算全體持股組合之總體股息來源結構
    public func analyzePortfolio(
        holdings: [StockHolding],
        asOf date: Date = Date(),
        events: [DividendEvent]? = nil
    ) -> PortfolioDividendSourceSummary {
        let activeEvents = events ?? StorageService.shared.loadEvents()
        let calcs = holdings.map { calculateHoldingDividend(holding: $0, asOf: date, events: activeEvents) }

        let totalMonthly = calcs.reduce(0.0) { $0 + $1.monthlyDividend }
        let totalFullMonthly = calcs.reduce(0.0) { $0 + $1.fullMonthlyDividend }
        let totalPendingMonthly = max(0.0, totalFullMonthly - totalMonthly)
        let totalPendingShares = calcs.reduce(0) { $0 + $1.pendingNextMonthShares }
        let totalAnnual = totalFullMonthly * 12.0

        let total76 = calcs.reduce(0.0) { $0 + $1.amount76Monthly }
        let total54C = calcs.reduce(0.0) { $0 + $1.amount54CMonthly }
        let totalReserve = calcs.reduce(0.0) { $0 + $1.amountReserveMonthly }
        let totalSurplus = calcs.reduce(0.0) { $0 + $1.amountSurplusMonthly }

        let pct76 = totalMonthly > 0 ? (total76 / totalMonthly) * 100.0 : 0.0
        let pct54C = totalMonthly > 0 ? (total54C / totalMonthly) * 100.0 : 0.0
        let pctReserve = totalMonthly > 0 ? (totalReserve / totalMonthly) * 100.0 : 0.0
        let pctSurplus = totalMonthly > 0 ? (totalSurplus / totalMonthly) * 100.0 : 0.0
        let taxExemptPct = pct76 + pctReserve + pctSurplus

        let ccCalcs = calcs.filter { $0.profile.strategy == .coveredCall }
        let hasCC = !ccCalcs.isEmpty
        let ccMonthly = ccCalcs.reduce(0.0) { $0 + $1.monthlyDividend }

        let exemptAnnualAmount = (total76 + totalReserve + totalSurplus) * 12.0
        let nhiSaved = exemptAnnualAmount * 0.0211

        return PortfolioDividendSourceSummary(
            totalMonthlyDividend: totalMonthly,
            totalFullPositionMonthlyDividend: totalFullMonthly,
            totalPendingMonthlyDividend: totalPendingMonthly,
            totalPendingShares: totalPendingShares,
            totalAnnualDividend: totalAnnual,
            total76Amount: total76,
            total54CAmount: total54C,
            totalReserveAmount: totalReserve,
            totalSurplusAmount: totalSurplus,
            total76Percent: pct76,
            total54CPercent: pct54C,
            totalReservePercent: pctReserve,
            totalSurplusPercent: pctSurplus,
            taxExemptPercent: taxExemptPct,
            hasCoveredCallHoldings: hasCC,
            coveredCallMonthlyAmount: ccMonthly,
            estimatedAnnualNhiSaved: nhiSaved,
            holdingsCalculations: calcs
        )
    }
}
