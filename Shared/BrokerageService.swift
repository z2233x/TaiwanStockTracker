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
    
    // 透過本機/私有雲 Python Shioaji Bridge 查詢即時真實庫存
    public func fetchPositionsFromShioajiBridge(
        bridgeURL: String,
        apiKey: String,
        secretKey: String,
        certPath: String,
        completion: @escaping (Result<[StockHolding], Error>) -> Void
    ) {
        var cleanURL = bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.hasPrefix("http://") && !cleanURL.hasPrefix("https://") {
            cleanURL = "http://" + cleanURL
        }
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        guard let url = URL(string: "\(cleanURL)/api/sync_positions") else {
            completion(.failure(NSError(domain: "ShioajiBridge", code: 400, userInfo: [NSLocalizedDescriptionKey: "中繼伺服器網址格式不正確"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let body: [String: Any] = [
            "api_key": apiKey,
            "secret_key": secretKey,
            "ca_cert_path": certPath
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "ShioajiBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "未收到中繼伺服器回應"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let detail = json["detail"] as? String {
                        completion(.failure(NSError(domain: "ShioajiBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: detail])))
                        return
                    }
                    guard let positions = json["positions"] as? [[String: Any]] else {
                        completion(.failure(NSError(domain: "ShioajiBridge", code: 500, userInfo: [NSLocalizedDescriptionKey: "回傳格式無效"])))
                        return
                    }
                    
                    var holdings: [StockHolding] = []
                    for p in positions {
                        guard let sym = p["symbol"] as? String, !sym.isEmpty else { continue }
                        let shares = (p["shares"] as? Int) ?? 1000
                        let cost = (p["average_cost"] as? Double) ?? 0.0
                        let meta = TaiwanStockDatabase.shared.find(symbol: sym)
                        let holding = StockHolding(
                            symbol: sym,
                            name: meta?.name ?? (p["name"] as? String ?? sym),
                            frequency: meta?.frequency ?? .quarterly,
                            shares: shares,
                            averageCost: cost > 0 ? cost : (meta?.referencePrice ?? 10.0),
                            currentPrice: meta?.referencePrice ?? (cost > 0 ? cost : 10.0),
                            stockType: meta?.stockType ?? .stock,
                            brokerage: "永豐金證券 (Shioaji API)"
                        )
                        holdings.append(holding)
                    }
                    completion(.success(holdings))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
