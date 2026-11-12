import Foundation
import UIKit
import Vision

public final class StockOCRService {
    public static let shared = StockOCRService()
    private init() {}
    
    /// 透過 Apple 原生 Vision 引擎辨識券商庫存截圖或拍照相片
    public func recognizeStocks(from image: UIImage, completion: @escaping (Result<[StockHolding], Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(domain: "StockOCRService", code: 400, userInfo: [NSLocalizedDescriptionKey: "無法讀取圖片資料"])))
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] (req, err) in
            guard let self = self else { return }
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
                completion(.success([]))
                return
            }
            
            let detectedItems = self.parseObservations(observations)
            completion(.success(detectedItems))
        }
        
        // 設定精確模式與支援繁中/英數
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        request.usesLanguageCorrection = false // 關閉自動拼寫校正，保護股票代號數字不被篡改
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 自動適應圖片旋轉方向
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 座標與空間排版解析 (以 Table Row 帶狀空間精準隔離)
    private func parseObservations(_ observations: [VNRecognizedTextObservation]) -> [StockHolding] {
        struct TextElement {
            let text: String
            let box: CGRect // 歸一化座標 (0,0 在左下角，Y 越大越靠上)
        }
        
        var elements: [TextElement] = []
        for obs in observations {
            if let topCandidate = obs.topCandidates(1).first {
                let cleaned = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    elements.append(TextElement(text: cleaned, box: obs.boundingBox))
                }
            }
        }
        
        // 1. 過濾雜訊區塊 (說明備註、頁碼、欄位表頭提示)
        let filteredElements = elements.filter { elem in
            let t = elem.text
            // 排除表尾備註及免責文字 (如 ※2020/2/14 起現股[付出成本]自動計入該股票之除息金額)
            if t.hasPrefix("※") || t.contains("自動計入") || t.contains("起現股") || t.contains("不區分幣別") || t.contains("自行篩選") {
                return false
            }
            // 排除頁次與總損益摘要
            if (t.contains("總損益") && t.contains("筆數")) || t.contains("頁次") {
                return false
            }
            // 排除完整欄位表頭行
            if (t.contains("股票名稱") && t.contains("庫存")) || (t.contains("即時庫存") && t.contains("現值")) {
                return false
            }
            return true
        }
        
        // 2. 尋找股票錨點 (4~6 碼代號，含 ETF 00 系列與個股/興櫃)
        struct StockAnchor {
            let symbol: String
            let midY: CGFloat
            let minX: CGFloat
            let rawText: String
        }
        
        // 正則：支援 ETF (如 00406A, 006208, 0056, 00878) 或 4 碼個股/興櫃 (如 2330, 7781)
        // 排除含有斜線或橫線之日期 (如 2020/2/14, 2024-11)
        let symbolPattern = "(?<![A-Za-z0-9/.-])(00\\d{2,4}[A-Za-z]?|[1-9]\\d{3}[A-Za-z]?)(?![A-Za-z0-9/.-])"
        let regex = try? NSRegularExpression(pattern: symbolPattern)
        
        var anchors: [StockAnchor] = []
        var seenSymbols = Set<String>()
        
        for elem in filteredElements {
            // 若文字塊本身包含年月日日期分隔，直接略過該塊的代碼提取
            if elem.text.contains("/") || elem.text.contains("年") || elem.text.contains("月") || elem.text.contains("日") {
                continue
            }
            
            let nsStr = elem.text as NSString
            let matches = regex?.matches(in: elem.text, range: NSRange(location: 0, length: nsStr.length)) ?? []
            for m in matches {
                let sym = nsStr.substring(with: m.range(at: 1)).uppercased()
                // 排除常見西元年誤判 (如 2020, 2024, 2025, 2026)，除非明確在股票資料庫且同行有股票名稱
                if (sym == "2020" || sym == "2024" || sym == "2025" || sym == "2026") && !elem.text.contains("美亞") {
                    continue
                }
                if !seenSymbols.contains(sym) {
                    seenSymbols.insert(sym)
                    anchors.append(StockAnchor(symbol: sym, midY: elem.box.midY, minX: elem.box.minX, rawText: elem.text))
                }
            }
        }
        
        // 若找不到股票錨點，退回純文字分行解析
        if anchors.isEmpty {
            let sortedByY = filteredElements.sorted { $0.box.midY > $1.box.midY }
            let lines = sortedByY.map { $0.text }
            return extractHoldingsFromLines(lines)
        }
        
        // 將股票錨點按 Y 軸由上至下 (midY 由大到小) 排序
        anchors.sort { $0.midY > $1.midY }
        
        var holdings: [StockHolding] = []
        
        // 3. 為每檔股票劃定專屬橫向資料帶 (Band)，杜絕跨行數字干擾
        for i in 0..<anchors.count {
            let cur = anchors[i]
            let topBound: CGFloat = (i == 0) ? (cur.midY + 0.06) : ((anchors[i - 1].midY + cur.midY) / 2.0)
            let bottomBound: CGFloat = (i == anchors.count - 1) ? (cur.midY - 0.06) : ((cur.midY + anchors[i + 1].midY) / 2.0)
            
            // 抓取落在該持股帶狀區間的所有文字塊
            let bandElements = filteredElements.filter { elem in
                return elem.box.midY <= topBound && elem.box.midY >= bottomBound
            }.sorted { $0.box.minX < $1.box.minX }
            
            let bandFullText = bandElements.map { $0.text }.joined(separator: " ")
            
            // 4. 解析股票名稱 (優先查資料庫，若無則從該區間提取連續中文字)
            let meta = TaiwanStockDatabase.shared.find(symbol: cur.symbol)
            var finalName = meta?.name
            if finalName == nil || finalName?.isEmpty == true {
                // 從帶狀文字提取中文名稱 (排除券商常見功能字)
                let cleanedChinese = bandFullText
                    .replacingOccurrences(of: "沖銷", with: " ")
                    .replacingOccurrences(of: "明細", with: " ")
                    .replacingOccurrences(of: "現股", with: " ")
                    .replacingOccurrences(of: "興櫃", with: " ")
                    .replacingOccurrences(of: "台幣", with: " ")
                    .replacingOccurrences(of: "外幣", with: " ")
                    .replacingOccurrences(of: "融資", with: " ")
                    .replacingOccurrences(of: "融券", with: " ")
                
                let chRegex = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fa5]{2,10}")
                let chMatches = chRegex?.matches(in: cleanedChinese, range: NSRange(cleanedChinese.startIndex..., in: cleanedChinese)) ?? []
                for cm in chMatches {
                    if let range = Range(cm.range, in: cleanedChinese) {
                        let word = String(cleanedChinese[range])
                        if word != "台幣" && word != "現股" && word != "沖銷" && word != "明細" {
                            finalName = word
                            break
                        }
                    }
                }
            }
            if finalName == nil || finalName?.isEmpty == true {
                finalName = cur.symbol
            }
            
            // 5. 提取該區間內的所有數字並使用數學公式交叉比對
            let (shares, price) = extractBestSharesAndPrice(from: bandFullText, targetSymbol: cur.symbol, metaPrice: meta?.referencePrice ?? 0.0)
            
            // 6. 配息頻率判定 (00406A / 00406 強制月配)
            var freq: FrequencyType = meta?.frequency ?? .annual
            if cur.symbol == "00406A" || cur.symbol == "00406" ||
               (finalName?.contains("中信台灣收益") == true) ||
               (finalName?.contains("掩護性買權") == true) {
                freq = .monthly
            } else if cur.symbol == "006208" || cur.symbol == "0050" {
                freq = .semiannual
            } else if ["0056", "00878", "00919", "00713", "2330"].contains(cur.symbol) {
                freq = .quarterly
            } else if ["00929", "00940", "00939"].contains(cur.symbol) {
                freq = .monthly
            }
            
            let stockType: StockType = (cur.symbol.hasPrefix("00") ? .etf : (meta?.stockType ?? .stock))
            
            let holding = StockHolding(
                symbol: cur.symbol,
                name: finalName ?? cur.symbol,
                frequency: freq,
                shares: shares,
                averageCost: price > 0 ? price : (meta?.referencePrice ?? 10.0),
                currentPrice: meta?.referencePrice ?? (price > 0 ? price : 10.0),
                stockType: stockType,
                brokerage: "照片智慧辨識"
            )
            holdings.append(holding)
        }
        
        return holdings
    }
    
    // MARK: - 智慧提取代號、股數與成本 (文字行 Fallback 模式)
    public func extractHoldingsFromLines(_ lines: [String]) -> [StockHolding] {
        var holdings: [StockHolding] = []
        var detectedSymbols = Set<String>()
        
        // 排除備註與表尾行
        let cleanLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("※") || t.contains("自動計入") || t.contains("起現股") || t.contains("不區分幣別") { return false }
            if (t.contains("總損益") && t.contains("筆數")) || t.contains("頁次") { return false }
            return true
        }
        
        let allStocks = TaiwanStockDatabase.shared.allStocks
        let symbolPattern = "(?<![A-Za-z0-9/.-])(00\\d{2,4}[A-Za-z]?|[1-9]\\d{3}[A-Za-z]?)(?![A-Za-z0-9/.-])"
        let regex = try? NSRegularExpression(pattern: symbolPattern)
        
        for (lineIdx, rawLine) in cleanLines.enumerated() {
            if rawLine.contains("/") && !rawLine.contains("00") { continue }
            
            var foundSymbol: String? = nil
            var foundName: String? = nil
            
            let nsStr = rawLine as NSString
            let matches = regex?.matches(in: rawLine, range: NSRange(location: 0, length: nsStr.length)) ?? []
            for m in matches {
                let sym = nsStr.substring(with: m.range(at: 1)).uppercased()
                if (sym == "2020" || sym == "2024" || sym == "2025" || sym == "2026") && !rawLine.contains("美亞") {
                    continue
                }
                foundSymbol = sym
                if let meta = allStocks.first(where: { $0.symbol == sym }) {
                    foundName = meta.name
                }
                break
            }
            
            if foundSymbol == nil {
                for stock in allStocks {
                    if rawLine.contains(stock.name) {
                        foundSymbol = stock.symbol
                        foundName = stock.name
                        break
                    }
                }
            }
            
            if let sym = foundSymbol, !detectedSymbols.contains(sym) {
                detectedSymbols.insert(sym)
                let meta = TaiwanStockDatabase.shared.find(symbol: sym)
                var finalName = foundName ?? (meta?.name ?? sym)
                
                // 搜索上下文 (該行與往後 1 行) 提取數值
                let searchScope = cleanLines[lineIdx..<min(lineIdx + 2, cleanLines.count)].joined(separator: " ")
                let (shares, price) = extractBestSharesAndPrice(from: searchScope, targetSymbol: sym, metaPrice: meta?.referencePrice ?? 0.0)
                
                var freq: FrequencyType = meta?.frequency ?? .annual
                if sym == "00406A" || sym == "00406" || finalName.contains("中信台灣收益") || finalName.contains("掩護性買權") {
                    freq = .monthly
                } else if sym == "006208" || sym == "0050" {
                    freq = .semiannual
                } else if ["0056", "00878", "00919"].contains(sym) {
                    freq = .quarterly
                }
                
                let holding = StockHolding(
                    symbol: sym,
                    name: finalName,
                    frequency: freq,
                    shares: shares,
                    averageCost: price > 0 ? price : (meta?.referencePrice ?? 10.0),
                    currentPrice: meta?.referencePrice ?? (price > 0 ? price : 10.0),
                    stockType: sym.hasPrefix("00") ? .etf : (meta?.stockType ?? .stock),
                    brokerage: "照片智慧辨識"
                )
                holdings.append(holding)
            }
        }
        
        return holdings
    }
    
    // MARK: - 數值解析：結合千分位黏合、雙胞胎庫存整數與 S * P ≈ C 數學交叉驗證
    private func extractBestSharesAndPrice(from text: String, targetSymbol: String, metaPrice: Double) -> (shares: Int, price: Double) {
        // 1. 全形符號與百分比預處理
        var processedText = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "%", with: " ")
        
        // 2. 正則黏合千分位逗號 (例如 140,433 或 140, 433 或 1,000 或 1,059,320)
        // 重複兩次以覆蓋百萬級千分位
        let commaRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*,\\s*(\\d{3})(?!\\d)")
        for _ in 0..<2 {
            let nsText = processedText as NSString
            processedText = commaRegex?.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: NSRange(location: 0, length: nsText.length),
                withTemplate: "$1$2"
            ) ?? processedText
        }
        
        // 3. 提取所有有效數值 (整數或帶小數點浮點數)
        let numRegex = try? NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?")
        let nsProcessed = processedText as NSString
        let matches = numRegex?.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsProcessed.length)) ?? []
        
        // 收集標的本身包含的純數字 (例如 7781，或 00406A 裡的 406)，避免將股票代號誤當成股數或成本
        let symNumRegex = try? NSRegularExpression(pattern: "\\d+")
        let nsSym = targetSymbol as NSString
        let symMatches = symNumRegex?.matches(in: targetSymbol, range: NSRange(location: 0, length: nsSym.length)) ?? []
        var excludedDigits = Set<String>()
        for sm in symMatches {
            let s = nsSym.substring(with: sm.range)
            if s.count >= 3 {
                excludedDigits.insert(s)
            }
        }
        
        var numbers: [Double] = []
        for m in matches {
            let rawStr = nsProcessed.substring(with: m.range)
            if excludedDigits.contains(rawStr) { continue }
            if let val = Double(rawStr), val > 0 && val < 100000000 {
                numbers.append(val)
            }
        }
        
        // 4. 整數候選群 (股數候選)
        let integerCandidates = numbers.filter { floor($0) == $0 && $0 >= 1 }
        
        // 5. 特徵 1: 券商表格雙胞胎整數判定 (即時庫存與昨日餘額常緊鄰且數值完全相等)
        var twinShares: Int? = nil
        if integerCandidates.count >= 2 {
            for idx in 0..<min(4, integerCandidates.count - 1) {
                if integerCandidates[idx] == integerCandidates[idx + 1] {
                    twinShares = Int(integerCandidates[idx])
                    break
                }
            }
        }
        
        // 建立優先檢驗的股數清單
        var candidateSharesToCheck: [Int] = []
        if let twin = twinShares {
            candidateSharesToCheck.append(twin)
        }
        for it in integerCandidates.prefix(4) {
            let intVal = Int(it)
            if !candidateSharesToCheck.contains(intVal) {
                candidateSharesToCheck.append(intVal)
            }
        }
        
        // 6. 特徵 2: 數學關係高精度驗證 S * P ≈ C (股數 * 成本均價 ≈ 付出成本)
        struct MathMatch {
            let shares: Int
            let price: Double
            let cost: Double
            let diff: Double
            let priceIndex: Int
        }
        
        var mathMatches: [MathMatch] = []
        for s in candidateSharesToCheck {
            guard s > 0 else { continue }
            for (pIdx, p) in numbers.enumerated() {
                guard p != Double(s), p >= 0.1, p <= 3500 else { continue }
                let expectedC = Double(s) * p
                for c in numbers where c > Double(s) && c > p && c >= 50 {
                    let diff = abs(expectedC - c) / c
                    if diff < 0.025 { // 誤差 2.5% 內 (包容券商手續費/稅差或四捨五入)
                        mathMatches.append(MathMatch(shares: s, price: p, cost: c, diff: diff, priceIndex: pIdx))
                    }
                }
            }
        }
        
        if !mathMatches.isEmpty {
            // 排序策略：
            // a. 優先取 diff 最小者 (S * 成本均價 ≈ 付出成本 的誤差通常 < 0.001)
            // b. 若 diff 相當，優先取 priceIndex 較小者 (表頭中成本均價排在現價左側)
            let best = mathMatches.sorted { (m1, m2) -> Bool in
                let d1 = (m1.diff * 1000).rounded()
                let d2 = (m2.diff * 1000).rounded()
                if d1 != d2 {
                    return d1 < d2
                }
                return m1.priceIndex < m2.priceIndex
            }.first!
            
            return (best.shares, best.price)
        }
        
        // 7. Fallback 啟發模式
        let bestShares: Int
        if let twin = twinShares {
            bestShares = twin
        } else if let roundLot = integerCandidates.first(where: { Int($0) % 1000 == 0 && $0 >= 1000 }) {
            bestShares = Int(roundLot)
        } else if let firstInt = integerCandidates.first {
            bestShares = Int(firstInt)
        } else {
            bestShares = 1000
        }
        
        let floatCandidates = numbers.filter { floor($0) != $0 && $0 > 0.5 && $0 <= 3500 }
        let bestPrice: Double
        if let floatP = floatCandidates.first {
            bestPrice = floatP
        } else if metaPrice > 0 {
            bestPrice = metaPrice
        } else {
            bestPrice = 10.0
        }
        
        return (bestShares, bestPrice)
    }
}

// MARK: - 輔助圖片旋轉方向轉換
private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
