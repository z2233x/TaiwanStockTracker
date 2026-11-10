import Foundation
import WidgetKit

public struct MonthlyTimelineSummary: Identifiable, Codable {
    public var id: String { monthKey }
    public let monthKey: String          // e.g. "2025年 2月"
    public let totalMarketValue: Double  // 總價值
    public let totalCost: Double         // 總成本
    public let priceGainProfit: Double   // 價差獲利
    public let totalFee: Double          // 手續費
    public let monthDividend: Double     // 當月股息
    
    public init(
        monthKey: String,
        totalMarketValue: Double,
        totalCost: Double,
        priceGainProfit: Double,
        totalFee: Double,
        monthDividend: Double
    ) {
        self.monthKey = monthKey
        self.totalMarketValue = totalMarketValue
        self.totalCost = totalCost
        self.priceGainProfit = priceGainProfit
        self.totalFee = totalFee
        self.monthDividend = monthDividend
    }
}

public struct WidgetDataSummary: Codable {
    public let totalMarketValue: Double
    public let totalCost: Double
    public let unrealizedProfit: Double
    public let returnRate: Double
    public let totalDividendsReceived: Double
    public let nextEventTitle: String       // e.g. "00929 除息"
    public let nextEventCountdown: String   // e.g. "剩 2 天"
    public let topHoldingName: String
    public let lastUpdated: Date
}

public struct AppBackupPayload: Codable {
    public let version: String
    public let exportDate: Date
    public let holdings: [StockHolding]
    public let journals: [JournalEntry]
    public let events: [DividendEvent]
    public let histories: [HoldingDividendHistory]
}

public final class StorageService {
    public static let shared = StorageService()
    public static let appGroupId = "group.com.twstock.tracker"
    
    private let userDefaults = UserDefaults(suiteName: appGroupId)
    private let holdingsKey = "saved_stock_holdings_v2"
    private let journalsKey = "saved_journals_v2"
    private let eventsKey = "saved_dividend_events_v2"
    private let historiesKey = "saved_holding_histories_v2"
    private let privacyKey = "is_privacy_masked_v2"
    private let seededKey = "has_seeded_sample_data_v2"
    private let widgetSummaryKey = "widget_summary_data"
    
    private init() {
        if !UserDefaults.standard.bool(forKey: seededKey) {
            seedSampleData()
            UserDefaults.standard.set(true, forKey: seededKey)
        }
    }
    
    // MARK: - 持股管理 (CRUD)
    public func saveHoldings(_ holdings: [StockHolding]) {
        if let encoded = try? JSONEncoder().encode(holdings) {
            userDefaults?.set(encoded, forKey: holdingsKey)
        }
        updateWidgetSummary(holdings: holdings)
    }
    
    public func loadHoldings() -> [StockHolding] {
        guard let data = userDefaults?.data(forKey: holdingsKey),
              let list = try? JSONDecoder().decode([StockHolding].self, from: data) else {
            return []
        }
        return list
    }
    
    // 新增或加碼存股
    public func addOrUpdateHolding(_ newHolding: StockHolding, isDCA: Bool = false, autoAddJournal: Bool = true) {
        var current = loadHoldings()
        if let idx = current.firstIndex(where: { $0.symbol == newHolding.symbol }) {
            if isDCA {
                // 定期定額加碼存股：加權重新計算均價與總股數
                current[idx].addDCA(newShares: newHolding.shares, buyPrice: newHolding.averageCost)
            } else {
                // 直接更新或覆蓋
                current[idx] = newHolding
            }
        } else {
            current.append(newHolding)
        }
        saveHoldings(current)
        
        // 若勾選自動建立日記
        if autoAddJournal && newHolding.shares > 0 {
            var journals = loadJournals()
            let journal = JournalEntry(
                symbol: newHolding.symbol,
                name: newHolding.name,
                type: .buy,
                date: Date(),
                price: newHolding.averageCost,
                shares: newHolding.shares,
                fee: newHolding.buyFee,
                note: isDCA ? "定期定額加碼存股" : "建立初始持股"
            )
            journals.insert(journal, at: 0)
            saveJournals(journals)
        }
    }
    
    // 修改持股資料
    public func updateHolding(_ updated: StockHolding) {
        var current = loadHoldings()
        if let idx = current.firstIndex(where: { $0.id == updated.id || $0.symbol == updated.symbol }) {
            current[idx] = updated
            saveHoldings(current)
        }
    }
    
    // 刪除持股
    public func deleteHolding(id: UUID) {
        var current = loadHoldings()
        current.removeAll { $0.id == id }
        saveHoldings(current)
    }
    
    public func deleteHolding(symbol: String) {
        var current = loadHoldings()
        current.removeAll { $0.symbol == symbol }
        saveHoldings(current)
    }
    
    // MARK: - 即時報價更新 (Yahoo Finance 批次查詢)
    public func refreshAllStockQuotes() async -> (successCount: Int, failedCount: Int) {
        var current = loadHoldings()
        guard !current.isEmpty else { return (0, 0) }
        
        var success = 0
        var failed = 0
        
        for i in 0..<current.count {
            let symbol = current[i].symbol
            do {
                let quote = try await StockQuoteService.shared.fetchQuote(symbol: symbol)
                if quote.currentPrice > 0 {
                    current[i].currentPrice = quote.currentPrice
                    if quote.previousClose > 0 {
                        current[i].previousClose = quote.previousClose
                    }
                    current[i].updatedAt = Date()
                    success += 1
                }
            } catch {
                failed += 1
            }
        }
        
        if success > 0 {
            saveHoldings(current)
        }
        return (success, failed)
    }
    
    // MARK: - 日記紀錄
    public func saveJournals(_ journals: [JournalEntry]) {
        if let encoded = try? JSONEncoder().encode(journals) {
            userDefaults?.set(encoded, forKey: journalsKey)
        }
    }
    
    public func loadJournals() -> [JournalEntry] {
        guard let data = userDefaults?.data(forKey: journalsKey),
              let list = try? JSONDecoder().decode([JournalEntry].self, from: data) else {
            return []
        }
        return list
    }
    
    public func addJournal(_ entry: JournalEntry) {
        var current = loadJournals()
        current.insert(entry, at: 0)
        saveJournals(current)
    }
    
    public func deleteJournal(id: UUID) {
        var current = loadJournals()
        current.removeAll { $0.id == id }
        saveJournals(current)
    }
    
    // MARK: - 除息日曆事件
    public func saveEvents(_ events: [DividendEvent]) {
        if let encoded = try? JSONEncoder().encode(events) {
            userDefaults?.set(encoded, forKey: eventsKey)
        }
        updateWidgetSummary(events: events)
    }
    
    public func loadEvents() -> [DividendEvent] {
        guard let data = userDefaults?.data(forKey: eventsKey),
              let list = try? JSONDecoder().decode([DividendEvent].self, from: data) else {
            return []
        }
        return list
    }
    
    public func addEvent(_ event: DividendEvent) {
        var current = loadEvents()
        current.append(event)
        saveEvents(current)
    }
    
    public func deleteEvent(id: UUID) {
        var current = loadEvents()
        current.removeAll { $0.id == id }
        saveEvents(current)
    }
    
    // MARK: - 個股歷史除息紀錄 (對應截圖4)
    public func saveHoldingHistories(_ histories: [HoldingDividendHistory]) {
        if let encoded = try? JSONEncoder().encode(histories) {
            userDefaults?.set(encoded, forKey: historiesKey)
        }
    }
    
    public func loadHoldingHistories(symbol: String? = nil) -> [HoldingDividendHistory] {
        guard let data = userDefaults?.data(forKey: historiesKey),
              let list = try? JSONDecoder().decode([HoldingDividendHistory].self, from: data) else {
            return []
        }
        if let sym = symbol {
            return list.filter { $0.symbol == sym }
        }
        return list
    }
    
    // MARK: - 隱私遮蔽設定
    public var isPrivacyMasked: Bool {
        get { userDefaults?.bool(forKey: privacyKey) ?? false }
        set { userDefaults?.set(newValue, forKey: privacyKey) }
    }
    
    // MARK: - 領息頻率分佈統計 (對應截圖1)
    public func getFrequencyDistribution(holdings: [StockHolding]? = nil) -> [FrequencyType: Int] {
        let list = holdings ?? loadHoldings()
        var dict: [FrequencyType: Int] = [
            .monthly: 0,
            .bimonthly: 0,
            .quarterly: 0,
            .semiannual: 0,
            .annual: 0
        ]
        for item in list {
            dict[item.frequency, default: 0] += 1
        }
        return dict
    }
    
    // MARK: - 股息歷程時間軸數據 (對應截圖3)
    public func getMonthlyTimelineSummaries() -> [MonthlyTimelineSummary] {
        return [
            MonthlyTimelineSummary(monthKey: "2025年 2月", totalMarketValue: 244490, totalCost: 240420, priceGainProfit: 4070, totalFee: 0, monthDividend: 390),
            MonthlyTimelineSummary(monthKey: "2025年 1月", totalMarketValue: 207400, totalCost: 206630, priceGainProfit: 770, totalFee: 0, monthDividend: 320),
            MonthlyTimelineSummary(monthKey: "2024年 12月", totalMarketValue: 206280, totalCost: 206630, priceGainProfit: -350, totalFee: 0, monthDividend: 1935),
            MonthlyTimelineSummary(monthKey: "2024年 11月", totalMarketValue: 203890, totalCost: 206630, priceGainProfit: -2740, totalFee: 0, monthDividend: 1250)
        ]
    }
    
    // MARK: - 資料備份 (JSON 匯出/匯入)
    public func exportAllDataAsJSON() -> String? {
        let payload = AppBackupPayload(
            version: "2.1",
            exportDate: Date(),
            holdings: loadHoldings(),
            journals: loadJournals(),
            events: loadEvents(),
            histories: loadHoldingHistories()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    public func importDataFromJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(AppBackupPayload.self, from: data) else {
            return false
        }
        saveHoldings(payload.holdings)
        saveJournals(payload.journals)
        saveEvents(payload.events)
        saveHoldingHistories(payload.histories)
        return true
    }
    
    // MARK: - Widget 資料同步
    public func updateWidgetSummary(holdings: [StockHolding]? = nil, events: [DividendEvent]? = nil) {
        let curHoldings = holdings ?? loadHoldings()
        let curEvents = events ?? loadEvents()
        
        let totalCost = curHoldings.reduce(0.0) { $0 + $1.totalCostWithFee }
        let totalMarketValue = curHoldings.reduce(0.0) { $0 + $1.marketValue }
        let unrealizedProfit = curHoldings.reduce(0.0) { $0 + $1.unrealizedProfit }
        let returnRate = totalCost > 0 ? (unrealizedProfit / totalCost) * 100.0 : 0.0
        let totalDividends = curHoldings.reduce(0.0) { $0 + $1.totalDividendsReceived }
        
        let sortedEvents = curEvents.filter { $0.daysRemaining >= 0 }.sorted { $0.daysRemaining < $1.daysRemaining }
        let nextEvent = sortedEvents.first
        let topHolding = curHoldings.sorted { $0.marketValue > $1.marketValue }.first
        
        let summary = WidgetDataSummary(
            totalMarketValue: totalMarketValue,
            totalCost: totalCost,
            unrealizedProfit: unrealizedProfit,
            returnRate: returnRate,
            totalDividendsReceived: totalDividends,
            nextEventTitle: nextEvent != nil ? "\(nextEvent!.symbol) \(nextEvent!.eventType.rawValue)" : "近期無除息",
            nextEventCountdown: nextEvent != nil ? nextEvent!.countdownBadgeText : "--",
            topHoldingName: topHolding?.name ?? "無持股",
            lastUpdated: Date()
        )
        
        if let encoded = try? JSONEncoder().encode(summary) {
            userDefaults?.set(encoded, forKey: widgetSummaryKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    public func loadWidgetSummary() -> WidgetDataSummary {
        guard let data = userDefaults?.data(forKey: widgetSummaryKey),
              let summary = try? JSONDecoder().decode(WidgetDataSummary.self, from: data) else {
            return WidgetDataSummary(
                totalMarketValue: 244490, totalCost: 240420, unrealizedProfit: 4070, returnRate: 1.69,
                totalDividendsReceived: 3895, nextEventTitle: "00929 除息日", nextEventCountdown: "剩 2 天",
                topHoldingName: "0056 元大高股息", lastUpdated: Date()
            )
        }
        return summary
    }
    
    // MARK: - 預設範例資料導入 (精準吻合截圖)
    public func seedSampleData() {
        let calendar = Calendar.current
        let today = Date()
        
        let sampleHoldings: [StockHolding] = [
            StockHolding(symbol: "0056", name: "元大高股息", frequency: .quarterly, shares: 3000, averageCost: 37.84, currentPrice: 37.05, previousClose: 36.80, totalDividendsReceived: 1070, dividendCount: 1),
            StockHolding(symbol: "00929", name: "復華台灣科技優息", frequency: .monthly, shares: 4000, averageCost: 19.85, currentPrice: 19.90, previousClose: 19.75, totalDividendsReceived: 1590, dividendCount: 4),
            StockHolding(symbol: "00919", name: "群益台灣精選高息", frequency: .quarterly, shares: 2000, averageCost: 23.50, currentPrice: 24.10, previousClose: 24.05, totalDividendsReceived: 720, dividendCount: 1),
            StockHolding(symbol: "00936", name: "台新永續高息中小", frequency: .monthly, shares: 2000, averageCost: 16.20, currentPrice: 16.50, previousClose: 16.40, totalDividendsReceived: 380, dividendCount: 2),
            StockHolding(symbol: "00915", name: "凱基優選高股息30", frequency: .quarterly, shares: 1500, averageCost: 26.80, currentPrice: 27.20, previousClose: 27.00, totalDividendsReceived: 450, dividendCount: 1),
            StockHolding(symbol: "00717", name: "富邦美國特別股", frequency: .quarterly, shares: 1000, averageCost: 15.60, currentPrice: 15.80, previousClose: 15.75, totalDividendsReceived: 160, dividendCount: 1)
        ]
        saveHoldings(sampleHoldings)
        
        let sampleJournals: [JournalEntry] = [
            JournalEntry(symbol: "0056", name: "元大高股息", type: .buy, date: calendar.date(byAdding: .day, value: -14, to: today) ?? today, price: 36.67, shares: 1000, fee: 31),
            JournalEntry(symbol: "0056", name: "元大高股息", type: .buy, date: calendar.date(byAdding: .month, value: -3, to: today) ?? today, price: 35.58, shares: 1000, fee: 30),
            JournalEntry(symbol: "0056", name: "元大高股息", type: .buy, date: calendar.date(byAdding: .month, value: -4, to: today) ?? today, price: 41.26, shares: 1000, fee: 35)
        ]
        saveJournals(sampleJournals)
        
        let sampleHistories: [HoldingDividendHistory] = [
            HoldingDividendHistory(symbol: "00929", paymentDate: calendar.date(byAdding: .day, value: -10, to: today) ?? today, dividendPerShare: 0.11, sharesSnapshot: 3000),
            HoldingDividendHistory(symbol: "00929", paymentDate: calendar.date(byAdding: .month, value: -1, to: today) ?? today, dividendPerShare: 0.14, sharesSnapshot: 3000),
            HoldingDividendHistory(symbol: "00929", paymentDate: calendar.date(byAdding: .month, value: -2, to: today) ?? today, dividendPerShare: 0.16, sharesSnapshot: 3000),
            HoldingDividendHistory(symbol: "00929", paymentDate: calendar.date(byAdding: .month, value: -3, to: today) ?? today, dividendPerShare: 0.18, sharesSnapshot: 2000)
        ]
        saveHoldingHistories(sampleHistories)
        
        let sampleEvents: [DividendEvent] = [
            DividendEvent(symbol: "00939", name: "統一台灣高息", frequency: .monthly, eventType: .exDividendDate, targetDate: today, cashPerShare: 0.063, sharesSnapshot: 1000),
            DividendEvent(symbol: "00940", name: "元大台灣價值", frequency: .monthly, eventType: .lastBuyDate, targetDate: today, cashPerShare: 0.04, sharesSnapshot: 2000),
            DividendEvent(symbol: "00940", name: "元大台灣價值", frequency: .monthly, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, cashPerShare: 0.04, sharesSnapshot: 2000),
            DividendEvent(symbol: "00959B", name: "大華投等美債", frequency: .monthly, eventType: .lastBuyDate, targetDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, cashPerShare: 0.05, sharesSnapshot: 1000),
            DividendEvent(symbol: "00940", name: "元大台灣價值", frequency: .monthly, eventType: .paymentDate, targetDate: calendar.date(byAdding: .day, value: 3, to: today) ?? today, cashPerShare: 0.04, sharesSnapshot: 2000),
            DividendEvent(symbol: "00936", name: "台新永續高息", frequency: .monthly, eventType: .paymentDate, targetDate: calendar.date(byAdding: .day, value: 6, to: today) ?? today, cashPerShare: 0.08, sharesSnapshot: 2000),
            DividendEvent(symbol: "00717", name: "富邦美國特別", frequency: .quarterly, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 12, to: today) ?? today, cashPerShare: 0.16, sharesSnapshot: 1000),
            DividendEvent(symbol: "00733", name: "富邦臺灣中小", frequency: .semiannual, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 18, to: today) ?? today, cashPerShare: 1.30, sharesSnapshot: 500)
        ]
        saveEvents(sampleEvents)
    }
}
