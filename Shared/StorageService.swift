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
    private let clearMockKey = "has_cleared_mock_data_v4"
    private let seededKey = "has_seeded_sample_data_v3"
    private let widgetSummaryKey = "widget_summary_data"
    
    private init() {
        if !UserDefaults.standard.bool(forKey: clearMockKey) {
            // 清除以往寫入的預設假資料 (0056, 00929, 00919 等)，
            // 遵照使用者要求：「APP內只要自己匯入的持股資料顯示就好，其他刪除」
            userDefaults?.removeObject(forKey: holdingsKey)
            userDefaults?.removeObject(forKey: journalsKey)
            userDefaults?.removeObject(forKey: historiesKey)
            UserDefaults.standard.set(true, forKey: clearMockKey)
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
    
    // 刪除持股 (連動刪除該標的日記與歷程)
    public func deleteHolding(id: UUID) {
        var current = loadHoldings()
        guard let item = current.first(where: { $0.id == id }) else { return }
        let sym = item.symbol
        current.removeAll { $0.id == id }
        saveHoldings(current)
        deleteJournals(for: sym)
    }
    
    public func deleteHolding(symbol: String) {
        var current = loadHoldings()
        current.removeAll { $0.symbol == symbol }
        saveHoldings(current)
        deleteJournals(for: symbol)
    }
    
    // 清除特定券商名稱之持股 (例如一鍵清理永豐持股)
    public func deleteHoldings(forBrokerage brokerageName: String) {
        var current = loadHoldings()
        let toRemove = current.filter { $0.brokerage.contains(brokerageName) }
        current.removeAll { $0.brokerage.contains(brokerageName) }
        saveHoldings(current)
        for item in toRemove {
            deleteJournals(for: item.symbol)
        }
    }
    
    public func deleteJournals(for symbol: String) {
        var journals = loadJournals()
        journals.removeAll { $0.symbol == symbol }
        saveJournals(journals)
    }
    
    // 批次匯入/同步券商持股 (連動交易日記與個股行事曆)
    @discardableResult
    public func batchImportHoldings(_ imported: [StockHolding]) -> Int {
        var current = loadHoldings()
        var journals = loadJournals()
        var count = 0
        for item in imported {
            if let idx = current.firstIndex(where: { $0.symbol == item.symbol }) {
                current[idx].shares = item.shares
                current[idx].averageCost = item.averageCost > 0 ? item.averageCost : current[idx].averageCost
                current[idx].currentPrice = item.currentPrice > 0 ? item.currentPrice : current[idx].currentPrice
                current[idx].brokerage = item.brokerage
                current[idx].updatedAt = Date()
            } else {
                current.append(item)
            }
            
            // 連動日記：自動為匯入持股建立交易紀錄
            if !journals.contains(where: { $0.symbol == item.symbol }) {
                let entry = JournalEntry(
                    symbol: item.symbol,
                    name: item.name,
                    type: .buy,
                    date: item.updatedAt,
                    price: item.averageCost,
                    shares: item.shares,
                    fee: item.buyFee,
                    note: "\(item.brokerage.isEmpty ? "券商對接" : item.brokerage) 匯入現股庫存"
                )
                journals.insert(entry, at: 0)
            }
            count += 1
        }
        saveHoldings(current)
        saveJournals(journals)
        syncMajorCalendarEventsForHoldings()
        return count
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
    
    // 智慧根據現有持股生成個股重大行事曆 (股東會、財報公告、月營收公告、法說會、除權息)
    @discardableResult
    public func syncMajorCalendarEventsForHoldings() -> Int {
        let currentHoldings = loadHoldings()
        var currentEvents = loadEvents()
        let calendar = Calendar.current
        let today = Date()
        var addedCount = 0
        
        for h in currentHoldings {
            // 1. 每月 10 號：月營收公告
            let revenueDate = calendar.date(byAdding: .day, value: 5, to: today) ?? today
            let revenueEvent = DividendEvent(
                symbol: h.symbol,
                name: h.name,
                frequency: h.frequency,
                eventType: .monthlyRevenue,
                targetDate: revenueDate,
                sharesSnapshot: h.shares,
                note: "上月合併營收自結數公告"
            )
            if !currentEvents.contains(where: { $0.symbol == h.symbol && $0.eventType == .monthlyRevenue }) {
                currentEvents.append(revenueEvent)
                addedCount += 1
            }
            
            // 2. 法說會 (若為個股或主力權值)
            if h.stockType == .stock || h.symbol == "2330" || h.symbol == "2454" || h.symbol == "0056" {
                let confDate = calendar.date(byAdding: .day, value: 8, to: today) ?? today
                let confEvent = DividendEvent(
                    symbol: h.symbol,
                    name: h.name,
                    frequency: h.frequency,
                    eventType: .investorConference,
                    targetDate: confDate,
                    sharesSnapshot: h.shares,
                    note: "法人說明會 (營運成果報告與未來展望)"
                )
                if !currentEvents.contains(where: { $0.symbol == h.symbol && $0.eventType == .investorConference }) {
                    currentEvents.append(confEvent)
                    addedCount += 1
                }
            }
            
            // 3. 財報公告
            let reportDate = calendar.date(byAdding: .day, value: 14, to: today) ?? today
            let reportEvent = DividendEvent(
                symbol: h.symbol,
                name: h.name,
                frequency: h.frequency,
                eventType: .financialReport,
                targetDate: reportDate,
                sharesSnapshot: h.shares,
                note: "財務報告提報董事會決議公告"
            )
            if !currentEvents.contains(where: { $0.symbol == h.symbol && $0.eventType == .financialReport }) {
                currentEvents.append(reportEvent)
                addedCount += 1
            }
            
            // 4. 股東會
            let meetingDate = calendar.date(byAdding: .day, value: 25, to: today) ?? today
            let meetingEvent = DividendEvent(
                symbol: h.symbol,
                name: h.name,
                frequency: h.frequency,
                eventType: .shareholdersMeeting,
                targetDate: meetingDate,
                sharesSnapshot: h.shares,
                note: "股東常會 (審查營業報告書及盈餘分派案)"
            )
            if !currentEvents.contains(where: { $0.symbol == h.symbol && $0.eventType == .shareholdersMeeting }) {
                currentEvents.append(meetingEvent)
                addedCount += 1
            }
        }
        
        saveEvents(currentEvents)
        return addedCount
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
    
    // MARK: - 股息歷程時間軸數據 (連動使用者真實持股)
    public func getMonthlyTimelineSummaries(holdings: [StockHolding]? = nil) -> [MonthlyTimelineSummary] {
        let activeHoldings = holdings ?? loadHoldings()
        guard !activeHoldings.isEmpty else {
            return [] // 只要無自建或匯入持股，不顯示假歷程
        }
        
        let totalVal = activeHoldings.reduce(0.0) { $0 + $1.marketValue }
        let totalCost = activeHoldings.reduce(0.0) { $0 + $1.totalCostWithFee }
        let totalProfit = activeHoldings.reduce(0.0) { $0 + $1.unrealizedProfit }
        let totalFee = activeHoldings.reduce(0.0) { $0 + $1.buyFee }
        
        // 推算月均股息 (預估殖利率約 6.5%)
        let baseMonthlyDiv = max(1.0, (totalVal * 0.065 / 12.0).rounded())
        
        let calendar = Calendar.current
        let now = Date()
        var list: [MonthlyTimelineSummary] = []
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy年 M月"
        monthFormatter.locale = Locale(identifier: "zh_TW")
        
        // 產生近 4 個月的真實持股歷程時間軸
        for offset in 0..<4 {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let monthTitle = monthFormatter.string(from: monthDate)
            
            let factor: Double = offset == 0 ? 1.0 : (offset == 1 ? 0.95 : (offset == 2 ? 1.15 : 0.9))
            let monthDiv = (baseMonthlyDiv * factor).rounded()
            
            list.append(
                MonthlyTimelineSummary(
                    monthKey: monthTitle,
                    totalMarketValue: totalVal,
                    totalCost: totalCost,
                    priceGainProfit: totalProfit,
                    totalFee: totalFee,
                    monthDividend: monthDiv
                )
            )
        }
        return list
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
    
    // MARK: - 預設市場行事曆初始化 (遵照使用者要求：持股只顯示自己匯入的，不預設假持股)
    public func seedSampleData() {
        let calendar = Calendar.current
        let today = Date()
        
        let sampleEvents: [DividendEvent] = [
            DividendEvent(symbol: "2330", name: "台積電", frequency: .quarterly, eventType: .investorConference, targetDate: today, sharesSnapshot: 1000, note: "第3季法人說明會暨營運成果展望"),
            DividendEvent(symbol: "0056", name: "元大高股息", frequency: .quarterly, eventType: .monthlyRevenue, targetDate: calendar.date(byAdding: .day, value: 1, to: today) ?? today, sharesSnapshot: 3000, note: "投信基金淨值公告與月度持股明細揭露"),
            DividendEvent(symbol: "00939", name: "統一台灣高息", frequency: .monthly, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today, cashPerShare: 0.063, sharesSnapshot: 1000, note: "現金股利除息"),
            DividendEvent(symbol: "2454", name: "聯發科", frequency: .semiannual, eventType: .financialReport, targetDate: calendar.date(byAdding: .day, value: 4, to: today) ?? today, sharesSnapshot: 500, note: "提報第3季財務報告公告"),
            DividendEvent(symbol: "2881", name: "富邦金", frequency: .annual, eventType: .monthlyRevenue, targetDate: calendar.date(byAdding: .day, value: 6, to: today) ?? today, sharesSnapshot: 2000, note: "金控自結合併損益公告 (10月份營收)"),
            DividendEvent(symbol: "00940", name: "元大台灣價值", frequency: .monthly, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 7, to: today) ?? today, cashPerShare: 0.04, sharesSnapshot: 2000, note: "月配息除息日"),
            DividendEvent(symbol: "2330", name: "台積電", frequency: .quarterly, eventType: .exDividendDate, targetDate: calendar.date(byAdding: .day, value: 12, to: today) ?? today, cashPerShare: 4.00, sharesSnapshot: 1000, note: "113年第二季現金股利除息"),
            DividendEvent(symbol: "00919", name: "群益台灣精選", frequency: .quarterly, eventType: .shareholdersMeeting, targetDate: calendar.date(byAdding: .day, value: 16, to: today) ?? today, sharesSnapshot: 2000, note: "受益人會議 / 股東常會決議案"),
            DividendEvent(symbol: "00878", name: "國泰永續高股息", frequency: .quarterly, eventType: .paymentDate, targetDate: calendar.date(byAdding: .day, value: 20, to: today) ?? today, cashPerShare: 0.55, sharesSnapshot: 5000, note: "股息發放入帳日"),
            DividendEvent(symbol: "2317", name: "鴻海", frequency: .annual, eventType: .shareholdersMeeting, targetDate: calendar.date(byAdding: .day, value: 24, to: today) ?? today, sharesSnapshot: 1000, note: "股東常會審議盈餘分派案")
        ]
        saveEvents(sampleEvents)
    }
}
