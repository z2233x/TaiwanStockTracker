import Foundation

public struct BrokerageAccount: Identifiable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let iconName: String
    public let colorHex: String
    public var isConnected: Bool
    public var lastSyncTime: Date?
    
    public static let defaultBrokerages: [BrokerageAccount] = [
        BrokerageAccount(name: "元大證券", iconName: "y.circle.fill", colorHex: "#007AFF", isConnected: true, lastSyncTime: Date()),
        BrokerageAccount(name: "國泰綜合證券", iconName: "tree.circle.fill", colorHex: "#34C759", isConnected: true, lastSyncTime: Date()),
        BrokerageAccount(name: "富邦證券", iconName: "f.circle.fill", colorHex: "#007AFF", isConnected: false),
        BrokerageAccount(name: "永豐金證券 (大戶投)", iconName: "s.circle.fill", colorHex: "#FF9500", isConnected: true, lastSyncTime: Date()),
        BrokerageAccount(name: "玉山證券", iconName: "mountain.2.circle.fill", colorHex: "#34C759", isConnected: false),
        BrokerageAccount(name: "台新證券 (Richart)", iconName: "r.circle.fill", colorHex: "#FF3B30", isConnected: false),
        BrokerageAccount(name: "群益金鼎證券", iconName: "q.circle.fill", colorHex: "#AF52DE", isConnected: false),
        BrokerageAccount(name: "凱基證券", iconName: "k.circle.fill", colorHex: "#5856D6", isConnected: false)
    ]
}

public final class BrokerageService {
    public static let shared = BrokerageService()
    private init() {}
    
    // 解析常見券商匯出文字或 CSV (自動過濾逗號、空格、欄位)
    // 支援格式範例:
    // 2330 台積電 1000 1050
    // 0056,元大高股息,3000,37.84
    // 00878 2000 22.8
    public func parseBrokerageText(_ text: String, brokerageName: String = "元大證券") -> [StockHolding] {
        var parsedList: [StockHolding] = []
        let lines = text.components(separatedBy: .newlines)
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty && !line.hasPrefix("#") && !line.contains("股票代號") else { continue }
            
            // 分割符號：支援逗號、Tab、空格
            let parts = line.replacingOccurrences(of: "\t", with: " ")
                            .replacingOccurrences(of: ",", with: " ")
                            .components(separatedBy: " ")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            guard parts.count >= 2 else { continue }
            
            let symbolCandidate = parts[0].uppercased().trimmingCharacters(in: .whitespaces)
            guard symbolCandidate.count >= 4 else { continue }
            
            // 從資料庫比對標準名稱與資料
            let meta = TaiwanStockDatabase.shared.find(symbol: symbolCandidate)
            var name = meta?.name ?? symbolCandidate
            var shares = 1000
            var price = meta?.referencePrice ?? 0.0
            
            if parts.count >= 4 {
                // 格式: 2330 台積電 1000 1050
                name = parts[1]
                shares = Int(parts[2].replacingOccurrences(of: ",", with: "")) ?? 1000
                price = Double(parts[3].replacingOccurrences(of: ",", with: "")) ?? price
            } else if parts.count == 3 {
                // 格式: 2330 1000 1050
                shares = Int(parts[1].replacingOccurrences(of: ",", with: "")) ?? 1000
                price = Double(parts[2].replacingOccurrences(of: ",", with: "")) ?? price
            } else if parts.count == 2 {
                // 格式: 2330 1000
                shares = Int(parts[1].replacingOccurrences(of: ",", with: "")) ?? 1000
            }
            
            let holding = StockHolding(
                symbol: symbolCandidate,
                name: name,
                frequency: meta?.frequency ?? .quarterly,
                shares: shares,
                averageCost: price > 0 ? price : 10.0,
                currentPrice: price > 0 ? price : 10.0,
                stockType: meta?.stockType ?? .stock,
                brokerage: brokerageName
            )
            parsedList.append(holding)
        }
        
        return parsedList
    }
}
