import Foundation

public final class StockQuoteService {
    public static let shared = StockQuoteService()
    private init() {}
    
    public struct QuoteResult {
        public let symbol: String
        public let currentPrice: Double
        public let previousClose: Double
        public let source: String
        public let fetchedAt: Date
    }

    /// 官方公布之除權息日程與每股配息金額
    public struct AnnouncedDividendItem: Codable, Equatable {
        public let symbol: String
        public let exDateString: String   // yyyy-MM-dd
        public let exDate: Date
        public let cashPerShare: Double
        public let source: String
    }

    /// 內建已驗證之 2025-2026 台股／ETF 官方公布除權息日與每股配息基準表（離線即時可用，連線時自動與證交所 TWT48U_ALL 及 Yahoo Finance 合併更新）
    public static let knownOfficialDividends: [String: [(date: String, cash: Double)]] = [
        "006208": [("2025-11-18", 3.448), ("2026-07-16", 4.75), ("2026-11-17", 3.88)],
        "00406A": [("2026-09-02", 0.138), ("2026-10-05", 0.138), ("2026-11-03", 0.138), ("2026-12-02", 0.138)],
        "00406":  [("2026-09-02", 0.138), ("2026-10-05", 0.138), ("2026-11-03", 0.138), ("2026-12-02", 0.138)],
        "00878":  [("2026-02-24", 0.50), ("2026-05-19", 0.66), ("2026-08-18", 1.01), ("2026-11-17", 1.25)],
        "00929":  [("2026-09-17", 0.38), ("2026-10-21", 0.38), ("2026-11-18", 0.38)],
        "00940":  [("2026-09-08", 0.055), ("2026-10-07", 0.055), ("2026-11-10", 0.06)],
        "00939":  [("2026-09-02", 0.063), ("2026-10-02", 0.063), ("2026-11-02", 0.063)],
        "0056":   [("2026-01-17", 0.70), ("2026-04-23", 1.00), ("2026-07-21", 1.35), ("2026-10-22", 1.72)],
        "00919":  [("2026-03-17", 0.78), ("2026-06-16", 1.00), ("2026-09-16", 1.10)],
        "0050":   [("2026-01-22", 1.00), ("2026-07-21", 0.60)],
        "00713":  [("2026-03-20", 0.78), ("2026-06-22", 1.00), ("2026-09-21", 1.25)],
        "00915":  [("2026-03-18", 0.72), ("2026-06-16", 0.45), ("2026-09-16", 0.60)],
        "2330":   [("2026-03-17", 6.00), ("2026-06-11", 6.00), ("2026-09-16", 7.00)]
    ]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return f
    }()

    /// 查詢指定標的於特定年月之官方除權息資訊
    public func officialDividend(for symbol: String, year: Int, month: Int) -> AnnouncedDividendItem? {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(format: "%04d-%02d", year, month)
        guard let list = Self.knownOfficialDividends[clean],
              let matched = list.first(where: { $0.date.hasPrefix(prefix) }),
              let d = Self.dateFormatter.date(from: matched.date) else {
            return nil
        }
        return AnnouncedDividendItem(
            symbol: clean,
            exDateString: matched.date,
            exDate: d,
            cashPerShare: matched.cash,
            source: "官方除權息公告"
        )
    }

    /// 取得該標的全部已知官方除權息日程
    public func knownDividends(for symbol: String) -> [AnnouncedDividendItem] {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let list = Self.knownOfficialDividends[clean] else { return [] }
        return list.compactMap { item in
            guard let d = Self.dateFormatter.date(from: item.date) else { return nil }
            return AnnouncedDividendItem(
                symbol: clean,
                exDateString: item.date,
                exDate: d,
                cashPerShare: item.cash,
                source: "官方除權息公告"
            )
        }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// 取得單檔最新台股股價（優先直連證交所 MIS 即時行情，備援 Yahoo Finance `.TW` / `.TWO`）
    public func fetchQuote(symbol: String) async throws -> QuoteResult {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let twseQuote = try? await queryTWSEMIS(symbol: clean) {
            return twseQuote
        }
        do {
            return try await queryYahoo(host: "query1.finance.yahoo.com", ticker: "\(clean).TW", symbol: clean)
        } catch {
            do {
                return try await queryYahoo(host: "query1.finance.yahoo.com", ticker: "\(clean).TWO", symbol: clean)
            } catch {
                return try await queryYahoo(host: "query2.finance.yahoo.com", ticker: "\(clean).TW", symbol: clean)
            }
        }
    }

    /// 批次併發更新多檔台股最新股價
    public func fetchQuotes(symbols: [String]) async -> [String: QuoteResult] {
        let unique = Array(Set(symbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }

        var results: [String: QuoteResult] = [:]
        if let batchTWSE = try? await queryTWSEMISBatch(symbols: unique) {
            for (k, v) in batchTWSE {
                results[k] = v
            }
        }

        let missing = unique.filter { results[$0] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: (String, QuoteResult?).self) { group in
                for sym in missing {
                    group.addTask {
                        let q = try? await self.fetchQuote(symbol: sym)
                        return (sym, q)
                    }
                }
                for await (sym, q) in group {
                    if let q = q {
                        results[sym] = q
                    }
                }
            }
        }
        return results
    }

    /// 自動搜尋各檔股票自己公布的除權息日與配息金額（整合證交所 TWT48U_ALL 除權息預告表 + Yahoo Finance `events=div` + 內建官方表）
    public func fetchDividendAnnouncements(symbols: [String]) async -> [String: [AnnouncedDividendItem]] {
        let unique = Array(Set(symbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return [:] }

        var combined: [String: [String: AnnouncedDividendItem]] = [:]
        for sym in unique {
            var byDate: [String: AnnouncedDividendItem] = [:]
            for item in knownDividends(for: sym) {
                byDate[item.exDateString] = item
            }
            combined[sym] = byDate
        }

        // 1. 查詢證交所 TWT48U_ALL 官方除權息預告表
        if let twseItems = try? await queryTWSETWT48U(filterSymbols: Set(unique)) {
            for item in twseItems {
                combined[item.symbol, default: [:]][item.exDateString] = item
            }
        }

        // 2. 併發查詢 Yahoo Finance `events=div` 取得各檔近一年實際除息日與配息金額
        await withTaskGroup(of: (String, [AnnouncedDividendItem]).self) { group in
            for sym in unique {
                group.addTask {
                    if let list = try? await self.queryYahooDividends(ticker: "\(sym).TW", symbol: sym), !list.isEmpty {
                        return (sym, list)
                    }
                    if let list = try? await self.queryYahooDividends(ticker: "\(sym).TWO", symbol: sym), !list.isEmpty {
                        return (sym, list)
                    }
                    return (sym, [])
                }
            }
            for await (sym, list) in group {
                for item in list {
                    combined[sym, default: [:]][item.exDateString] = item
                }
            }
        }

        var finalMap: [String: [AnnouncedDividendItem]] = [:]
        for (sym, dict) in combined {
            finalMap[sym] = dict.values.sorted { $0.exDateString < $1.exDateString }
        }
        return finalMap
    }

    private func queryTWSETWT48U(filterSymbols: Set<String>) async throws -> [AnnouncedDividendItem] {
        guard let url = URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var results: [AnnouncedDividendItem] = []
        for row in arr {
            let code = ((row["Code"] as? String) ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard filterSymbols.contains(code) else { continue }
            let rocDate = ((row["Date"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cashStr = ((row["CashDividend"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cash = Double(cashStr), cash > 0, rocDate.count == 7,
                  let rocYear = Int(rocDate.prefix(3)) else { continue }
            let westernYear = rocYear + 1911
            let mm = rocDate.dropFirst(3).prefix(2)
            let dd = rocDate.suffix(2)
            let dateStr = "\(westernYear)-\(mm)-\(dd)"
            if let d = Self.dateFormatter.date(from: dateStr) {
                results.append(AnnouncedDividendItem(
                    symbol: code,
                    exDateString: dateStr,
                    exDate: d,
                    cashPerShare: (cash * 1000.0).rounded() / 1000.0,
                    source: "證交所除權息預告"
                ))
            }
        }
        return results
    }

    private func queryYahooDividends(ticker: String, symbol: String) async throws -> [AnnouncedDividendItem] {
        let ts = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=1y&events=div&_=\(ts)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let first = (chart["result"] as? [[String: Any]])?.first,
              let events = first["events"] as? [String: Any],
              let divs = events["dividends"] as? [String: [String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var list: [AnnouncedDividendItem] = []
        for (_, obj) in divs {
            guard let amount = obj["amount"] as? Double, amount > 0 else { continue }
            let tsVal: TimeInterval
            if let dDouble = obj["date"] as? Double {
                tsVal = dDouble
            } else if let dInt = obj["date"] as? Int {
                tsVal = TimeInterval(dInt)
            } else {
                continue
            }
            let d = Date(timeIntervalSince1970: tsVal)
            let dStr = Self.dateFormatter.string(from: d)
            if let cleanDate = Self.dateFormatter.date(from: dStr) {
                list.append(AnnouncedDividendItem(
                    symbol: symbol,
                    exDateString: dStr,
                    exDate: cleanDate,
                    cashPerShare: (amount * 1000.0).rounded() / 1000.0,
                    source: "Yahoo除權息公告"
                ))
            }
        }
        return list.sorted { $0.exDateString < $1.exDateString }
    }

    private func queryTWSEMIS(symbol: String) async throws -> QuoteResult {
        let batch = try await queryTWSEMISBatch(symbols: [symbol])
        guard let found = batch[symbol] else {
            throw URLError(.cannotParseResponse)
        }
        return found
    }

    private func queryTWSEMISBatch(symbols: [String]) async throws -> [String: QuoteResult] {
        let exChList = symbols.flatMap { ["tse_\($0).tw", "otc_\($0).tw"] }.joined(separator: "|")
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let encoded = exChList.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(encoded)&json=1&delay=0&_=\(ts)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("https://mis.twse.com.tw/stock/fibest.jsp", forHTTPHeaderField: "Referer")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msgArray = json["msgArray"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var map: [String: QuoteResult] = [:]
        let now = Date()
        for item in msgArray {
            guard let rawCode = item["c"] as? String else { continue }
            let code = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let z = Double((item["z"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let pz = Double((item["pz"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let y = Double((item["y"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let tv = Int((item["tv"] as? String ?? "0")) ?? 0

            let price: Double
            if z > 0 {
                price = z
            } else if pz > 0 && (tv > 0 || y == 0 || abs(pz - y) < y * 0.15) {
                price = pz
            } else if y > 0 {
                price = y
            } else {
                continue
            }

            let prev = y > 0 ? y : price
            if map[code] == nil || z > 0 {
                map[code] = QuoteResult(
                    symbol: code,
                    currentPrice: (price * 100.0).rounded() / 100.0,
                    previousClose: (prev * 100.0).rounded() / 100.0,
                    source: "TWSE即時",
                    fetchedAt: now
                )
            }
        }
        return map
    }

    private func queryYahoo(host: String, ticker: String, symbol: String) async throws -> QuoteResult {
        let ts = Int(Date().timeIntervalSince1970)
        guard let url = URL(string: "https://\(host)/v8/finance/chart/\(ticker)?interval=1d&range=1d&_=\(ts)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let currentPrice = meta["regularMarketPrice"] as? Double,
              currentPrice > 0 else {
            throw URLError(.cannotParseResponse)
        }
        
        let prevClose = (meta["chartPreviousClose"] as? Double) ?? (meta["previousClose"] as? Double) ?? currentPrice
        return QuoteResult(
            symbol: symbol,
            currentPrice: (currentPrice * 100.0).rounded() / 100.0,
            previousClose: (prevClose * 100.0).rounded() / 100.0,
            source: "Yahoo Finance",
            fetchedAt: Date()
        )
    }
}
