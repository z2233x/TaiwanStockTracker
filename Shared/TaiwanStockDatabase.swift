import Foundation

public struct StockMetaItem: Identifiable, Codable, Equatable, Hashable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let market: String              // 上市 / 上櫃
    public let stockType: StockType        // 一般個股 / ETF指數型
    public let frequency: FrequencyType    // 月配 / 季配 / 半年配 / 年配
    public let referencePrice: Double
    
    public init(
        symbol: String,
        name: String,
        market: String = "上市",
        stockType: StockType = .stock,
        frequency: FrequencyType = .annual,
        referencePrice: Double = 0.0
    ) {
        self.symbol = symbol
        self.name = name
        self.market = market
        self.stockType = stockType
        self.frequency = frequency
        self.referencePrice = referencePrice
    }
}

public final class TaiwanStockDatabase {
    public static let shared = TaiwanStockDatabase()
    
    public private(set) var allStocks: [StockMetaItem] = []
    private var symbolMap: [String: StockMetaItem] = [:]
    
    private init() {
        loadDatabase()
    }
    
    private func loadDatabase() {
        // 1. 嘗試從 App Bundle 載入全台股 2,400+ 標的 JSON
        if let url = Bundle.main.url(forResource: "TaiwanStocks", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([StockMetaItem].self, from: data),
           !list.isEmpty {
            self.allStocks = list
            self.symbolMap = Dictionary(list.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
            return
        }
        
        // 2. 本機專案路徑備份載入
        let localPath = "C:/Users/Edision/TaiwanStockTracker/Shared/TaiwanStocks.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
           let list = try? JSONDecoder().decode([StockMetaItem].self, from: data),
           !list.isEmpty {
            self.allStocks = list
            self.symbolMap = Dictionary(list.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
            return
        }
        
        // 3. Fallback: 核心熱門標的
        self.allStocks = PopularStockPreset.allPresets.map {
            StockMetaItem(
                symbol: $0.symbol,
                name: $0.name,
                market: "上市",
                stockType: $0.stockType,
                frequency: $0.frequency,
                referencePrice: $0.defaultPrice
            )
        }
        self.symbolMap = Dictionary(self.allStocks.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    // 即時模糊搜尋：代號完全相符 > 代號前綴 > 名稱前綴 > 代號/名稱包含
    public func search(keyword: String, limit: Int = 30) -> [StockMetaItem] {
        let clean = keyword.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else {
            return Array(allStocks.prefix(limit))
        }
        
        var results: [StockMetaItem] = []
        var seen = Set<String>()
        
        // 1. 完全符合代號
        if let exact = symbolMap[clean] {
            results.append(exact)
            seen.insert(exact.symbol)
        }
        
        // 2. 代號前綴相符 (如打 "23" 出現 2330, 2317, 2382...)
        for item in allStocks where item.symbol.hasPrefix(clean) && !seen.contains(item.symbol) {
            results.append(item)
            seen.insert(item.symbol)
            if results.count >= limit { return results }
        }
        
        // 3. 名稱前綴相符 (如打 "台積" 出現 台積電)
        for item in allStocks where item.name.hasPrefix(clean) && !seen.contains(item.symbol) {
            results.append(item)
            seen.insert(item.symbol)
            if results.count >= limit { return results }
        }
        
        // 4. 代號或名稱包含
        for item in allStocks where (item.symbol.contains(clean) || item.name.contains(clean)) && !seen.contains(item.symbol) {
            results.append(item)
            seen.insert(item.symbol)
            if results.count >= limit { return results }
        }
        
        return results
    }
    
    public func find(symbol: String) -> StockMetaItem? {
        let clean = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return symbolMap[clean]
    }
}
