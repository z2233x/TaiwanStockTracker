import Foundation

public struct DividendRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var holdingSymbol: String
    public var holdingName: String
    public var exDividendDate: Date       // 除權息日
    public var paymentDate: Date          // 發放日
    public var cashDividendPerShare: Double // 每股現金股利 (元)
    public var stockDividendPerShare: Double // 每股股票股利/配股 (元，每股面額10元)
    public var sharesSnapshot: Int        // 除權息當下持有股數
    
    public init(
        id: UUID = UUID(),
        holdingSymbol: String,
        holdingName: String,
        exDividendDate: Date,
        paymentDate: Date,
        cashDividendPerShare: Double,
        stockDividendPerShare: Double = 0.0,
        sharesSnapshot: Int
    ) {
        self.id = id
        self.holdingSymbol = holdingSymbol
        self.holdingName = holdingName
        self.exDividendDate = exDividendDate
        self.paymentDate = paymentDate
        self.cashDividendPerShare = cashDividendPerShare
        self.stockDividendPerShare = stockDividendPerShare
        self.sharesSnapshot = sharesSnapshot
    }
    
    // 現金股利總額 (稅前)
    public var grossCashAmount: Double {
        Double(sharesSnapshot) * cashDividendPerShare
    }
    
    // 配股增加之新股數 (每千股配股數 = 股數 * (股票股利 / 10))
    public var newSharesGained: Int {
        Int((Double(sharesSnapshot) * (stockDividendPerShare / 10.0)).rounded(.down))
    }
    
    // 股票股利面額價值 (每股 10 元)
    public var stockDividendFaceValue: Double {
        Double(newSharesGained) * 10.0
    }
    
    // 台灣二代健保補充保費 (單筆股利總額現金+配股面額達 20,000 元以上，課徵 2.11%)
    public var healthInsuranceFee: Double {
        let totalDividendIncome = grossCashAmount + stockDividendFaceValue
        return totalDividendIncome >= 20000.0 ? (grossCashAmount * 0.0211).rounded() : 0.0
    }
    
    // 實發現金股利 (扣除健保費與銀行匯費 10 元)
    public var netCashAmount: Double {
        guard grossCashAmount > 0 else { return 0.0 }
        return max(0.0, grossCashAmount - healthInsuranceFee - 10.0)
    }
    
    // 發放月份標記 ("yyyy-MM")
    public var paymentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: paymentDate)
    }
}
