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
    
    // MARK: - 座標與空間排版解析
    private func parseObservations(_ observations: [VNRecognizedTextObservation]) -> [StockHolding] {
        struct TextElement {
            let text: String
            let box: CGRect // 歸一化座標 (0,0 在左下角)
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
        
        // 將文字區塊按 Y 軸座標由上至下（Y 遞減）、X 軸由左至右分行
        let rowThreshold: CGFloat = 0.025
        var rows: [[TextElement]] = []
        
        // 先按 Y 由大到小排序 (Vision Y 原點在底部)
        let sortedByY = elements.sorted { $0.box.midY > $1.box.midY }
        
        for elem in sortedByY {
            if let lastRow = rows.last, let firstInRow = lastRow.first, abs(firstInRow.box.midY - elem.box.midY) < rowThreshold {
                rows[rows.count - 1].append(elem)
            } else {
                rows.append([elem])
            }
        }
        
        // 每行按 X 座標由左到右排序
        for i in 0..<rows.count {
            rows[i].sort { $0.box.minX < $1.box.minX }
        }
        
        // 組合每行字串
        var fullTextLines: [String] = []
        for r in rows {
            let lineStr = r.map { $0.text }.joined(separator: " ")
            fullTextLines.append(lineStr)
        }
        
        return extractHoldingsFromLines(fullTextLines)
    }
    
    // MARK: - 智慧提取代號、股數與成本
    public func extractHoldingsFromLines(_ lines: [String]) -> [StockHolding] {
        var holdings: [StockHolding] = []
        var detectedSymbols = Set<String>()
        
        let allStocks = TaiwanStockDatabase.shared.allStocks
        
        for (lineIdx, rawLine) in lines.enumerated() {
            let line = rawLine.replacingOccurrences(of: ",", with: "")
            
            // 1. 尋找台股代號 (4~5 位數字) 或 股票中文名稱
            var foundSymbol: String? = nil
            var foundName: String? = nil
            
            // 正則尋找 4~5 位台股代號 (如 2330, 0056, 00878)
            let regex = try? NSRegularExpression(pattern: "(?<!\\d)(\\d{4,5}[A-Za-z]?)(?!\\d)")
            if let matches = regex?.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                for m in matches {
                    if let range = Range(m.range(at: 1), in: line) {
                        let sym = String(line[range]).uppercased()
                        if let meta = allStocks.first(where: { $0.symbol == sym }) {
                            foundSymbol = meta.symbol
                            foundName = meta.name
                            break
                        }
                    }
                }
            }
            
            // 若代號未對應，比對中文名稱
            if foundSymbol == nil {
                for stock in allStocks {
                    if line.contains(stock.name) {
                        foundSymbol = stock.symbol
                        foundName = stock.name
                        break
                    }
                }
            }
            
            // 若在該行找到股票
            if let sym = foundSymbol, !detectedSymbols.contains(sym) {
                detectedSymbols.insert(sym)
                let meta = TaiwanStockDatabase.shared.find(symbol: sym)
                let finalName = foundName ?? (meta?.name ?? sym)
                
                // 搜索上下文 (該行與往後 2 行) 提取數值：股數與價格
                let searchScope = lines[lineIdx..<min(lineIdx + 3, lines.count)].joined(separator: " ")
                let (shares, price) = extractSharesAndPrice(from: searchScope, referencePrice: meta?.referencePrice ?? 0.0)
                
                let holding = StockHolding(
                    symbol: sym,
                    name: finalName,
                    frequency: meta?.frequency ?? .quarterly,
                    shares: shares,
                    averageCost: price > 0 ? price : (meta?.referencePrice ?? 10.0),
                    currentPrice: meta?.referencePrice ?? (price > 0 ? price : 10.0),
                    stockType: meta?.stockType ?? .stock,
                    brokerage: "照片智慧辨識"
                )
                holdings.append(holding)
            }
        }
        
        return holdings
    }
    
    // MARK: - 數值解析與推斷
    private func extractSharesAndPrice(from text: String, referencePrice: Double) -> (shares: Int, price: Double) {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let tokens = cleaned.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        
        var numbers: [Double] = []
        for t in tokens {
            // 過濾掉非數字詞與明顯不是金額或股數的代號
            if let num = Double(t), num > 0 && num < 10000000 {
                // 排除 4 碼可能為股票代號本身
                if num >= 1000 && num <= 9999 && floor(num) == num {
                    // 若剛好是代號則略過一次
                    continue
                }
                numbers.append(num)
            }
        }
        
        var shares = 1000
        var price = referencePrice > 0 ? referencePrice : 0.0
        
        // 智慧推斷：通常股數為整數 (如 500, 1000, 2000, 3000, 10000)，價格通常有小數點或接近參考價
        if numbers.count >= 2 {
            // 找出最可能是股數的整數 (大於等於 100，或 1000 的倍數)
            if let shareCandidate = numbers.first(where: { floor($0) == $0 && $0 >= 100 }) {
                shares = Int(shareCandidate)
                // 剩下數字中最接近參考價或帶小數點的作為成本
                let remaining = numbers.filter { $0 != shareCandidate }
                if let priceCandidate = remaining.first(where: { abs($0 - referencePrice) < referencePrice * 0.5 }) ?? remaining.first {
                    price = priceCandidate
                }
            } else {
                shares = Int(numbers[0])
                price = numbers[1]
            }
        } else if numbers.count == 1 {
            if numbers[0] >= 100 && floor(numbers[0]) == numbers[0] {
                shares = Int(numbers[0])
            } else {
                price = numbers[0]
            }
        }
        
        return (shares, price)
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
