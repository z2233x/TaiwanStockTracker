import Foundation
import WidgetKit

public struct WidgetDataSummary: Codable {
    public let totalMarketValue: Double
    public let totalCost: Double
    public let unrealizedProfit: Double
    public let returnRate: Double
    public let dailyProfitAmount: Double
    public let dailyChangeRate: Double
    public let currentMonthEstimatedCash: Double    // 當月預估現金股息
    public let currentMonthStockShares: Int         // 當月預估配股總股數
    public let topHoldingName: String
    public let lastUpdated: Date
}

public final class StorageService {
    public static let shared = StorageService()
    public static let appGroupId = "group.com.twstock.tracker"
    
    private let userDefaults = UserDefaults(suiteName: appGroupId)
    private let holdingsKey = "saved_stock_holdings"
    private let dividendsKey = "saved_dividend_records"
    private let widgetSummaryKey = "widget_summary_data"
    
    private init() {}
    
    public func saveHoldings(_ holdings: [StockHolding]) {
        if let encoded = try? JSONEncoder().encode(holdings) {
            userDefaults?.set(encoded, forKey: holdingsKey)
        }
        updateWidgetSummary(holdings: holdings)
    }
    
    public func loadHoldings() -> [StockHolding] {
        guard let data = userDefaults?.data(forKey: holdingsKey),
              let holdings = try? JSONDecoder().decode([StockHolding].self, from: data) else {
            return []
        }
        return holdings
    }
    
    public func saveDividends(_ dividends: [DividendRecord]) {
        if let encoded = try? JSONEncoder().encode(dividends) {
            userDefaults?.set(encoded, forKey: dividendsKey)
        }
        updateWidgetSummary(dividends: dividends)
    }
    
    public func loadDividends() -> [DividendRecord] {
        guard let data = userDefaults?.data(forKey: dividendsKey),
              let dividends = try? JSONDecoder().decode([DividendRecord].self, from: data) else {
            return []
        }
        return dividends
    }
    
    public func updateWidgetSummary(holdings: [StockHolding]? = nil, dividends: [DividendRecord]? = nil) {
        let currentHoldings = holdings ?? loadHoldings()
        let currentDividends = dividends ?? loadDividends()
        
        let totalCost = currentHoldings.reduce(0.0) { $0 + $1.totalCostWithFee }
        let totalMarketValue = currentHoldings.reduce(0.0) { $0 + $1.marketValue }
        let unrealizedProfit = currentHoldings.reduce(0.0) { $0 + $1.unrealizedProfit }
        let returnRate = totalCost > 0 ? (unrealizedProfit / totalCost) * 100.0 : 0.0
        let dailyProfitAmount = currentHoldings.reduce(0.0) { $0 + $1.dailyProfitAmount }
        let dailyChangeRate = (totalMarketValue - dailyProfitAmount) > 0 ? (dailyProfitAmount / (totalMarketValue - dailyProfitAmount)) * 100.0 : 0.0
        
        // 當月配息與配股統計
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        let currentMonthKey = monthFormatter.string(from: Date())
        
        let thisMonthRecords = currentDividends.filter { $0.paymentMonthKey == currentMonthKey }
        let monthCash = thisMonthRecords.reduce(0.0) { $0 + $1.netCashAmount }
        let monthShares = thisMonthRecords.reduce(0) { $0 + $1.newSharesGained }
        
        let topHolding = currentHoldings.sorted { $0.marketValue > $1.marketValue }.first
        
        let summary = WidgetDataSummary(
            totalMarketValue: totalMarketValue,
            totalCost: totalCost,
            unrealizedProfit: unrealizedProfit,
            returnRate: returnRate,
            dailyProfitAmount: dailyProfitAmount,
            dailyChangeRate: dailyChangeRate,
            currentMonthEstimatedCash: monthCash,
            currentMonthStockShares: monthShares,
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
                totalMarketValue: 0, totalCost: 0, unrealizedProfit: 0, returnRate: 0,
                dailyProfitAmount: 0, dailyChangeRate: 0, currentMonthEstimatedCash: 0,
                currentMonthStockShares: 0, topHoldingName: "無", lastUpdated: Date()
            )
        }
        return summary
    }
}
