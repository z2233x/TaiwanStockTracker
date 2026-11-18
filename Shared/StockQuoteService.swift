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
        // 先批次向證交所 MIS 一次查多檔（單一請求最快且為即時報價）
        if let batchTWSE = try? await queryTWSEMISBatch(symbols: unique) {
            for (k, v) in batchTWSE {
                results[k] = v
            }
        }

        // 剩餘未取得者併發查詢個別即時端點 / Yahoo Finance
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
            // z = 當盤成交價; pz = 試撮/收盤參考價; o = 開盤; y = 昨收
            let z = Double((item["z"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let pz = Double((item["pz"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let y = Double((item["y"] as? String ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
            let tv = Int((item["tv"] as? String ?? "0")) ?? 0

            // 若有有效成交量與成交價採 z，盤後/零股未撮合優先採 pz（若 > 0），最後才退回 y
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
            // 若 tse 與 otc 同時回傳，優先保留成交量較高或價格較新者
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
