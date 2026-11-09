import Foundation

public final class StockQuoteService {
    public static let shared = StockQuoteService()
    private init() {}
    
    public struct QuoteResult {
        public let symbol: String
        public let currentPrice: Double
        public let previousClose: Double
    }
    
    public func fetchQuote(symbol: String) async throws -> QuoteResult {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await queryYahoo(ticker: "\(clean).TW", symbol: clean)
        } catch {
            return try await queryYahoo(ticker: "\(clean).TWO", symbol: clean)
        }
    }
    
    private func queryYahoo(ticker: String, symbol: String) async throws -> QuoteResult {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(ticker)?interval=1d&range=1d") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let currentPrice = meta["regularMarketPrice"] as? Double else {
            throw URLError(.cannotParseResponse)
        }
        
        let prevClose = (meta["chartPreviousClose"] as? Double) ?? (meta["previousClose"] as? Double) ?? currentPrice
        return QuoteResult(symbol: symbol, currentPrice: currentPrice, previousClose: prevClose)
    }
}
