import Foundation
import WidgetKit

public struct NextMonthDividendForecast {
    public let monthKey: String
    public let estimatedDividend: Double
    public let totalEligibleShares: Int
    public let pendingAddedShares: Int
    public let isMidMonthAnnounced: Bool
    public let activeSymbols: [String]
}

public struct MonthlyTimelineSummary: Identifiable, Codable {
    public var id: String { monthKey }
    public let monthKey: String          // e.g. "2026年 11月"
    public let totalMarketValue: Double  // 總價值
    public let totalCost: Double         // 總成本
    public let priceGainProfit: Double   // 價差獲利
    public let totalFee: Double          // 手續費
    public let monthDividend: Double     // 當月已參與除息可領股息
    public let cumulativeDividend: Double // 截至該月累計配息加總
    public let activeHoldingCount: Int    // 該月份已買入持有標的數
    public let activeSymbols: [String]    // 該月份有配息生效之標的
    public let pendingNextDividend: Double // 本月除息後加碼、須待下月配息公布才領取之預估金額
    public let pendingSharesCount: Int     // 本月除息後才買進／加碼之股數
    public let pendingSymbols: [String]    // 須待下月公布領取之標的
    
    public init(
        monthKey: String,
        totalMarketValue: Double,
        totalCost: Double,
        priceGainProfit: Double,
        totalFee: Double,
        monthDividend: Double,
        cumulativeDividend: Double = 0.0,
        activeHoldingCount: Int = 0,
        activeSymbols: [String] = [],
        pendingNextDividend: Double = 0.0,
        pendingSharesCount: Int = 0,
        pendingSymbols: [String] = []
    ) {
        self.monthKey = monthKey
        self.totalMarketValue = totalMarketValue
        self.totalCost = totalCost
        self.priceGainProfit = priceGainProfit
        self.totalFee = totalFee
        self.monthDividend = monthDividend
        self.cumulativeDividend = cumulativeDividend
        self.activeHoldingCount = activeHoldingCount
        self.activeSymbols = activeSymbols
        self.pendingNextDividend = pendingNextDividend
        self.pendingSharesCount = pendingSharesCount
        self.pendingSymbols = pendingSymbols
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
    private let targetMonthlyIncomeKey = "saved_target_monthly_income_v1"
    
    public func saveTargetMonthlyIncome(_ amount: Double) {
        userDefaults?.set(amount, forKey: targetMonthlyIncomeKey)
    }
    
    public func loadTargetMonthlyIncome() -> Double {
        let val = userDefaults?.double(forKey: targetMonthlyIncomeKey) ?? 0.0
        return val > 0 ? val : 30000.0
    }
    
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
    
    // 新增或加碼存股 (精準寫入買入日期與加碼日期批次)
    public func addOrUpdateHolding(
        _ newHolding: StockHolding,
        isDCA: Bool = false,
        buyDate: Date? = nil,
        autoAddJournal: Bool = true
    ) {
        let effectiveDate = buyDate ?? newHolding.purchaseDate
        var current = loadHoldings()
        if let idx = current.firstIndex(where: { $0.symbol == newHolding.symbol }) {
            if isDCA {
                // 定期定額 / 單筆加碼存股：保留加碼日期批次並加權重新計算均價與總股數
                current[idx].addDCA(
                    newShares: newHolding.shares,
                    buyPrice: newHolding.averageCost,
                    buyDate: effectiveDate,
                    note: "加碼存股"
                )
            } else {
                // 直接更新或覆蓋
                var updated = newHolding
                if buyDate != nil {
                    updated.purchaseDate = effectiveDate
                    if updated.lots.count <= 1 {
                        updated.lots = updated.shares > 0
                            ? [HoldingLot(buyDate: effectiveDate, shares: updated.shares, price: updated.averageCost, note: "初始買入")]
                            : []
                    }
                }
                current[idx] = updated
            }
        } else {
            var created = newHolding
            if buyDate != nil {
                created.purchaseDate = effectiveDate
                created.lots = created.shares > 0
                    ? [HoldingLot(buyDate: effectiveDate, shares: created.shares, price: created.averageCost, note: "初始買入")]
                    : []
            }
            current.append(created)
        }
        saveHoldings(current)
        
        // 若勾選自動建立日記：使用實際買入／加碼日期
        if autoAddJournal && newHolding.shares > 0 {
            var journals = loadJournals()
            let journal = JournalEntry(
                symbol: newHolding.symbol,
                name: newHolding.name,
                type: .buy,
                date: effectiveDate,
                price: newHolding.averageCost,
                shares: newHolding.shares,
                fee: newHolding.buyFee,
                note: isDCA ? "加碼存股" : "建立初始持股"
            )
            journals.insert(journal, at: 0)
            journals.sort { $0.date > $1.date }
            saveJournals(journals)
        }
        syncAnnouncedDividends()
    }
    
    // 修改持股資料（同步批次買入與加碼日記）
    public func updateHolding(_ updated: StockHolding, syncLotsToJournal: Bool = true) {
        var current = loadHoldings()
        var target = updated
        if !target.lots.isEmpty {
            target.syncFromLots()
        }
        if let idx = current.firstIndex(where: { $0.id == target.id || $0.symbol == target.symbol }) {
            current[idx] = target
            saveHoldings(current)
            if syncLotsToJournal && !target.lots.isEmpty {
                var journals = loadJournals().filter { !($0.symbol == target.symbol && $0.type == .buy) }
                for lot in target.lots {
                    let fee = max(20.0, (Double(lot.shares) * lot.price * 0.001425 * target.brokerFeeDiscount).rounded())
                    journals.append(JournalEntry(
                        symbol: target.symbol,
                        name: target.name,
                        type: .buy,
                        date: lot.buyDate,
                        price: lot.price,
                        shares: lot.shares,
                        fee: fee,
                        note: lot.note
                    ))
                }
                journals.sort { $0.date > $1.date }
                saveJournals(journals)
            }
            syncAnnouncedDividends()
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
        syncAnnouncedDividends()
        return count
    }
    
    // MARK: - 即時報價與除權息公告同步 (證交所 MIS + TWT48U_ALL + Yahoo Finance 併發備援)
    private let lastQuoteUpdatedKey = "last_quote_updated_ts_v1"

    public var lastQuoteUpdatedAt: Date? {
        let ts = userDefaults?.double(forKey: lastQuoteUpdatedKey) ?? 0
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    public func refreshAllStockQuotes() async -> (successCount: Int, failedCount: Int) {
        var current = loadHoldings()
        guard !current.isEmpty else { return (0, 0) }
        
        let symbols = current.map { $0.symbol }
        async let quotesTask = StockQuoteService.shared.fetchQuotes(symbols: symbols)
        async let divsTask = StockQuoteService.shared.fetchDividendAnnouncements(symbols: symbols)
        let quoteMap = await quotesTask
        let divMap = await divsTask
        
        var success = 0
        var failed = 0
        for i in 0..<current.count {
            let sym = current[i].symbol
            if let quote = quoteMap[sym], quote.currentPrice > 0 {
                current[i].currentPrice = quote.currentPrice
                if quote.previousClose > 0 {
                    current[i].previousClose = quote.previousClose
                }
                current[i].updatedAt = quote.fetchedAt
                success += 1
            } else {
                failed += 1
            }
        }
        
        if success > 0 {
            userDefaults?.set(Date().timeIntervalSince1970, forKey: lastQuoteUpdatedKey)
            saveHoldings(current)
        }
        syncAnnouncedDividends(fetchedMap: divMap)
        return (success, failed)
    }

    /// 自動找尋各持股已公布的除權息日，同步至日曆，並在到達當月除權息日時自動入帳增加股息（例如 006208 於 11/17 除權息，11 月自動增加配息金額）
    @discardableResult
    public func syncAnnouncedDividends(
        fetchedMap: [String: [StockQuoteService.AnnouncedDividendItem]]? = nil,
        asOf today: Date = Date()
    ) -> Int {
        var holdings = loadHoldings()
        guard !holdings.isEmpty else { return 0 }
        var events = loadEvents()
        var histories = loadHoldingHistories()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)

        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"

        var eventsChanged = false
        var historiesChanged = false
        var holdingsChanged = false
        var creditedCount = 0

        for i in 0..<holdings.count {
            var h = holdings[i]
            let sym = h.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            var byDate: [String: StockQuoteService.AnnouncedDividendItem] = [:]
            for item in StockQuoteService.shared.knownDividends(for: sym) {
                byDate[item.exDateString] = item
            }
            if let fetched = fetchedMap?[sym] {
                for item in fetched {
                    byDate[item.exDateString] = item
                }
            }
            let items = byDate.values.sorted { $0.exDate < $1.exDate }
            guard !items.isEmpty else { continue }

            for item in items {
                let y = cal.component(.year, from: item.exDate)
                let m = cal.component(.month, from: item.exDate)

                // 1. 同步至台股日曆 (.exDividendDate)
                if let evIdx = events.firstIndex(where: {
                    $0.symbol.uppercased() == sym &&
                    $0.eventType == .exDividendDate &&
                    cal.component(.year, from: $0.targetDate) == y &&
                    cal.component(.month, from: $0.targetDate) == m
                }) {
                    if abs(events[evIdx].cashPerShare - item.cashPerShare) > 0.0001 ||
                       fmt.string(from: events[evIdx].targetDate) != item.exDateString {
                        events[evIdx] = DividendEvent(
                            id: events[evIdx].id,
                            symbol: h.symbol,
                            name: h.name,
                            frequency: h.frequency,
                            eventType: .exDividendDate,
                            targetDate: item.exDate,
                            cashPerShare: item.cashPerShare,
                            sharesSnapshot: h.shares,
                            note: "公告除權息日 \(item.exDateString) (每股配 $\(String(format: "%.3f", item.cashPerShare)))"
                        )
                        eventsChanged = true
                    }
                } else {
                    events.append(DividendEvent(
                        symbol: h.symbol,
                        name: h.name,
                        frequency: h.frequency,
                        eventType: .exDividendDate,
                        targetDate: item.exDate,
                        cashPerShare: item.cashPerShare,
                        sharesSnapshot: h.shares,
                        note: "公告除權息日 \(item.exDateString) (每股配 $\(String(format: "%.3f", item.cashPerShare)))"
                    ))
                    eventsChanged = true
                }

                // 2. 若已到達該股除權息日 (today >= exDate)，檢查除息前有效股數並自動計入當月股息紀錄
                let exStart = cal.startOfDay(for: item.exDate)
                if todayStart >= exStart {
                    let eligible = h.eligibleSharesForMonth(year: y, month: m, events: events)
                    guard eligible > 0 else { continue }

                    if let histIdx = histories.firstIndex(where: {
                        $0.symbol.uppercased() == sym &&
                        cal.component(.year, from: $0.exDividendDate) == y &&
                        cal.component(.month, from: $0.exDividendDate) == m
                    }) {
                        if histories[histIdx].sharesSnapshot != eligible ||
                           abs(histories[histIdx].dividendPerShare - item.cashPerShare) > 0.0001 {
                            histories[histIdx] = HoldingDividendHistory(
                                id: histories[histIdx].id,
                                symbol: h.symbol,
                                exDividendDate: item.exDate,
                                dividendPerShare: item.cashPerShare,
                                sharesSnapshot: eligible,
                                priceAtExDate: h.currentPrice
                            )
                            historiesChanged = true
                            creditedCount += 1
                        }
                    } else {
                        histories.append(HoldingDividendHistory(
                            symbol: h.symbol,
                            exDividendDate: item.exDate,
                            dividendPerShare: item.cashPerShare,
                            sharesSnapshot: eligible,
                            priceAtExDate: h.currentPrice
                        ))
                        historiesChanged = true
                        creditedCount += 1
                    }
                }
            }

            // 3. 重新彙整該持股已除息入帳之累計股息與次數
            let symHistories = histories.filter { $0.symbol.uppercased() == sym }
            if !symHistories.isEmpty {
                let sumDiv = symHistories.reduce(0.0) { $0 + $1.totalAmount }.rounded()
                let cnt = symHistories.count
                if abs(h.totalDividendsReceived - sumDiv) > 0.5 || h.dividendCount != cnt {
                    h.totalDividendsReceived = sumDiv
                    h.dividendCount = cnt
                    holdings[i] = h
                    holdingsChanged = true
                }
            }
        }

        if eventsChanged { saveEvents(events) }
        if historiesChanged {
            histories.sort { $0.exDividendDate > $1.exDividendDate }
            saveHoldingHistories(histories)
        }
        if holdingsChanged { saveHoldings(holdings) }
        return creditedCount
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
    
    private let deletedTimelineMonthKeysKey = "deleted_timeline_month_keys_v1"
    
    public func saveDeletedTimelineMonthKey(_ key: String) {
        var keys = loadDeletedTimelineMonthKeys()
        keys.insert(key)
        userDefaults?.set(Array(keys), forKey: deletedTimelineMonthKeysKey)
    }
    
    public func loadDeletedTimelineMonthKeys() -> Set<String> {
        let arr = userDefaults?.stringArray(forKey: deletedTimelineMonthKeysKey) ?? []
        return Set(arr)
    }
    
    public func resetDeletedTimelineMonths() {
        userDefaults?.removeObject(forKey: deletedTimelineMonthKeysKey)
    }
    
    // MARK: - 股息歷程時間軸數據 (依每筆買入／加碼日期與除息截算日分批起算配息)
    public func getMonthlyTimelineSummaries(holdings: [StockHolding]? = nil) -> [MonthlyTimelineSummary] {
        let activeHoldings = holdings ?? loadHoldings()
        guard !activeHoldings.isEmpty else {
            return [] // 只要無自建或匯入持股，不顯示假歷程
        }
        
        let journals = loadJournals()
        let events = loadEvents()
        let calendar = Calendar.current
        let now = Date()
        
        // 1. 找出每檔持股的最早買進日期（優先取批次 lots / holding.purchaseDate / 買進日記）
        var holdingPurchaseDates: [String: Date] = [:]
        for h in activeHoldings {
            let earliestLot = h.lots.map { $0.buyDate }.min()
            let earliestJournal = journals.filter { $0.symbol == h.symbol && $0.type == .buy }.map { $0.date }.min()
            let candidates = [earliestLot, h.purchaseDate, earliestJournal].compactMap { $0 }
            holdingPurchaseDates[h.symbol] = candidates.min() ?? h.updatedAt
        }
        
        // 2. 找出全體持股中最先買入的日期
        let earliestDate = holdingPurchaseDates.values.min() ?? now
        
        // 3. 計算從最早買入月份到當前月份相差多少個月 (最多回溯 12 個月，至少當前月 1 個月)
        let nowComponents = calendar.dateComponents([.year, .month], from: now)
        let earliestComponents = calendar.dateComponents([.year, .month], from: earliestDate)
        
        let yearDiff = (nowComponents.year ?? 2026) - (earliestComponents.year ?? 2026)
        let monthDiff = (nowComponents.month ?? 11) - (earliestComponents.month ?? 11)
        let totalMonths = max(1, min(12, yearDiff * 12 + monthDiff + 1))
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy年 M月"
        monthFormatter.locale = Locale(identifier: "zh_TW")
        
        var rawSummaries: [MonthlyTimelineSummary] = []
        var fallbackLatestSummary: MonthlyTimelineSummary? = nil
        var runningCumulativeDividend: Double = 0.0
        
        // 4. 從歷史最早月份依序往當前月份推算 (依當月實際可領除息股數計算)
        for offset in (0..<totalMonths).reversed() {
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let monthTitle = monthFormatter.string(from: monthDate)
            let y = calendar.component(.year, from: monthDate)
            let m = calendar.component(.month, from: monthDate)
            
            var monthDividendSum: Double = 0.0
            var pendingDividendSum: Double = 0.0
            var pendingSharesTotal = 0
            var monthVal: Double = 0.0
            var monthCost: Double = 0.0
            var monthFee: Double = 0.0
            var ownedHoldingsCount = 0
            var divActiveSymbols: [String] = []
            var pendingSymbols: [String] = []
            
            for h in activeHoldings {
                let owned = h.ownedShares(asOfEndOfYear: y, month: m)
                guard owned > 0 else { continue }
                ownedHoldingsCount += 1
                
                let principal = h.costPrincipal(asOfEndOfYear: y, month: m)
                let fee = max(20.0, (principal * 0.001425 * h.brokerFeeDiscount).rounded())
                monthCost += (principal + fee)
                monthFee += fee
                monthVal += Double(owned) * h.currentPrice
                
                // 【核心邏輯】：僅計算「buyDate < 該股該月自己公布的除權息日」的有效參與除息股數！
                let eligible = h.eligibleSharesForMonth(year: y, month: m, events: events)
                let pending = max(0, owned - eligible)
                
                if eligible > 0 {
                    let actual = DividendSourceService.shared.calculateActualMonthDividend(
                        for: h,
                        year: y,
                        month: m,
                        eligibleShares: eligible,
                        events: events,
                        asOf: now
                    )
                    // 當月已達除權息日（如 006208 於 11/17 除息），直接將實際除息金額加入該月股息！
                    let amt = actual.realizedInMonth > 0
                        ? actual.realizedInMonth
                        : (h.frequency == .monthly ? actual.upcomingInMonth : 0.0)
                    if amt > 0 {
                        monthDividendSum += amt
                        divActiveSymbols.append(h.symbol)
                    }
                }
                if pending > 0 {
                    let pendingAmt: Double
                    if let announced = StockHolding.announcedDividendInMonth(for: h.symbol, year: y, month: m, events: events),
                       announced.cashPerShare > 0 {
                        pendingAmt = Double(pending) * announced.cashPerShare
                    } else {
                        pendingAmt = DividendSourceService.shared.calculateMonthlyDividendAmount(for: h, shares: pending)
                    }
                    pendingDividendSum += pendingAmt
                    pendingSharesTotal += pending
                    pendingSymbols.append(h.symbol)
                }
            }
            
            guard ownedHoldingsCount > 0 else { continue }
            monthDividendSum = (monthDividendSum * 10.0).rounded() / 10.0
            let monthProfit = monthVal - monthCost
            
            let summary = MonthlyTimelineSummary(
                monthKey: monthTitle,
                totalMarketValue: monthVal.rounded(),
                totalCost: monthCost.rounded(),
                priceGainProfit: monthProfit.rounded(),
                totalFee: monthFee.rounded(),
                monthDividend: monthDividendSum.rounded(),
                cumulativeDividend: (runningCumulativeDividend + monthDividendSum).rounded(),
                activeHoldingCount: ownedHoldingsCount,
                activeSymbols: divActiveSymbols,
                pendingNextDividend: pendingDividendSum.rounded(),
                pendingSharesCount: pendingSharesTotal,
                pendingSymbols: pendingSymbols
            )
            fallbackLatestSummary = summary
            
            // 尚未開始任何首期配息前的純買入月份（例如 10/20 買 00406A，首期配息在 11 月），不列入 $0 歷史配息列以免稀釋平均月配息
            if monthDividendSum <= 0 && runningCumulativeDividend == 0 {
                continue
            }
            
            runningCumulativeDividend += monthDividendSum
            rawSummaries.append(summary)
        }
        
        if rawSummaries.isEmpty, let latest = fallbackLatestSummary {
            rawSummaries.append(latest)
        }
        
        // 5. 依月份新到舊排序 (近月排前面)
        var result = Array(rawSummaries.reversed())
        
        // 6. 排除使用者滑動刪除之月份
        let deletedKeys = loadDeletedTimelineMonthKeys()
        result.removeAll { deletedKeys.contains($0.monthKey) }
        
        return result
    }

    /// 推算下個月（例如 11 月中旬後已公布之 12 月預估配息，納入本月新買／加碼股數）
    public func getNextMonthDividendForecast(holdings: [StockHolding]? = nil) -> NextMonthDividendForecast? {
        let activeHoldings = holdings ?? loadHoldings()
        guard !activeHoldings.isEmpty else { return nil }
        let events = loadEvents()
        let cal = Calendar.current
        let now = Date()
        guard let nextMonthDate = cal.date(byAdding: .month, value: 1, to: now) else { return nil }

        let nextY = cal.component(.year, from: nextMonthDate)
        let nextM = cal.component(.month, from: nextMonthDate)
        let curY = cal.component(.year, from: now)
        let curM = cal.component(.month, from: now)
        let dayOfMonth = cal.component(.day, from: now)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年 M月"
        fmt.locale = Locale(identifier: "zh_TW")

        var totalDiv = 0.0
        var totalElig = 0
        var totalPendingAdded = 0
        var symbols: [String] = []

        for h in activeHoldings {
            let nextElig = h.eligibleSharesForMonth(year: nextY, month: nextM, events: events)
            let curElig = h.eligibleSharesForMonth(year: curY, month: curM, events: events)
            if nextElig > 0 {
                let actualNext = DividendSourceService.shared.calculateActualMonthDividend(
                    for: h,
                    year: nextY,
                    month: nextM,
                    eligibleShares: nextElig,
                    events: events,
                    asOf: nextMonthDate
                )
                let nextAmt = actualNext.realizedInMonth > 0
                    ? actualNext.realizedInMonth
                    : (actualNext.upcomingInMonth > 0
                        ? actualNext.upcomingInMonth
                        : (h.frequency == .monthly ? DividendSourceService.shared.calculateMonthlyDividendAmount(for: h, shares: nextElig) : 0.0))
                if nextAmt > 0 {
                    totalDiv += nextAmt
                    totalElig += nextElig
                    totalPendingAdded += max(0, nextElig - curElig)
                    symbols.append(h.symbol)
                }
            }
        }

        return NextMonthDividendForecast(
            monthKey: fmt.string(from: nextMonthDate),
            estimatedDividend: totalDiv.rounded(),
            totalEligibleShares: totalElig,
            pendingAddedShares: totalPendingAdded,
            isMidMonthAnnounced: dayOfMonth >= 15,
            activeSymbols: symbols
        )
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
