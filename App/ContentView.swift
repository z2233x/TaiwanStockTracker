import SwiftUI

struct ContentView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var dividends: [DividendRecord] = StorageService.shared.loadDividends()
    
    @State private var isShowingAddHolding = false
    @State private var isShowingAddDividend = false
    @State private var isRefreshingQuotes = false
    
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var totalCost: Double { holdings.reduce(0) { $0 + $1.totalCostWithFee } }
    var totalProfit: Double { holdings.reduce(0) { $0 + $1.unrealizedProfit } }
    var returnRate: Double { totalCost > 0 ? (totalProfit / totalCost) * 100.0 : 0.0 }
    
    var body: some View {
        TabView {
            // MARK: - 分頁 1: 持股績效儀表板
            NavigationStack {
                List {
                    // 資產總覽卡片
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("台股總資產市值")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("$\(Int(totalMarketValue).formatted())")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            
                            HStack(spacing: 12) {
                                Label {
                                    Text("\(totalProfit >= 0 ? "+" : "")\(Int(totalProfit).formatted()) 元")
                                } icon: {
                                    Image(systemName: totalProfit >= 0 ? "arrow.up.right" : "arrow.down.right")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(profitColor(totalProfit))
                                
                                Text("(\(String(format: "%.2f", returnRate))%)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(profitColor(totalProfit))
                            }
                            
                            Divider().padding(.vertical, 4)
                            
                            HStack {
                                Text("投入總成本：$\(Int(totalCost).formatted())")
                                Spacer()
                                Text("持股檔數：\(holdings.count) 檔")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    
                    // 持股明細清單
                    Section("持股明細") {
                        if holdings.isEmpty {
                            Text("尚未建立持股，點擊右上角「+」開始記錄")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(holdings) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.name)
                                                .font(.headline)
                                            Text(item.symbol)
                                                .font(.caption)
                                                .padding(.horizontal, 4)
                                                .background(Color.secondary.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                        Text("\(item.shares) 股 | 均價 $\(String(format: "%.2f", item.averageCost))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("$\(String(format: "%.2f", item.currentPrice))")
                                            .font(.headline)
                                        
                                        let profit = item.unrealizedProfit
                                        Text("\(profit >= 0 ? "+" : "")\(Int(profit).formatted()) (\(String(format: "%.1f", item.returnRate))%)")
                                            .font(.caption.bold())
                                            .foregroundColor(profitColor(profit))
                                    }
                                }
                            }
                            .onDelete(perform: deleteHolding)
                        }
                    }
                }
                .navigationTitle("台股績效")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: refreshPrices) {
                            if isRefreshingQuotes {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingAddHolding = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isShowingAddHolding) {
                    AddHoldingView { newHolding in
                        holdings.append(newHolding)
                        StorageService.shared.saveHoldings(holdings)
                    }
                }
            }
            .tabItem {
                Label("績效損益", systemImage: "chart.line.uptrend.xyaxis")
            }
            
            // MARK: - 分頁 2: 每月配股配息
            NavigationStack {
                List {
                    let currentMonthKey = {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: Date())
                    }()
                    let thisMonth = dividends.filter { $0.paymentMonthKey == currentMonthKey }
                    let monthCash = thisMonth.reduce(0.0) { $0 + $1.netCashAmount }
                    let monthShares = thisMonth.reduce(0) { $0 + $1.newSharesGained }
                    
                    Section("本月發放預估") {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("預估現金股息")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("$\(Int(monthCash).formatted())")
                                    .font(.title3.bold()).foregroundColor(.orange)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("預估配股股數")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("+\(monthShares) 股")
                                    .font(.title3.bold()).foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Section("配股配息紀錄清單") {
                        if dividends.isEmpty {
                            Text("無配股配息紀錄，點擊右上角「+」新增")
                                .font(.subheadline).foregroundColor(.secondary)
                        } else {
                            ForEach(dividends) { div in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(div.holdingName)
                                            .font(.headline)
                                        Text(div.holdingSymbol)
                                            .font(.caption).foregroundColor(.secondary)
                                        Spacer()
                                        Text("發放日: \(div.paymentMonthKey)")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    HStack {
                                        Text("實發現金: $\(Int(div.netCashAmount).formatted())")
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                        Spacer()
                                        if div.newSharesGained > 0 {
                                            Text("配股: +\(div.newSharesGained) 股")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    if div.healthInsuranceFee > 0 {
                                        Text("已扣二代健保補充保費: -$\(Int(div.healthInsuranceFee))")
                                            .font(.caption2).foregroundColor(.gray)
                                    }
                                }
                            }
                            .onDelete(perform: deleteDividend)
                        }
                    }
                }
                .navigationTitle("每月配股配息")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingAddDividend = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $isShowingAddDividend) {
                    AddDividendView(holdings: holdings) { newRecord in
                        dividends.append(newRecord)
                        StorageService.shared.saveDividends(dividends)
                    }
                }
            }
            .tabItem {
                Label("每月配股", systemImage: "calendar.badge.clock")
            }
        }
    }
    
    private func profitColor(_ val: Double) -> Color {
        if val > 0.0001 { return .red }
        if val < -0.0001 { return .green }
        return .secondary
    }
    
    private func deleteHolding(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        StorageService.shared.saveHoldings(holdings)
    }
    
    private func deleteDividend(at offsets: IndexSet) {
        dividends.remove(atOffsets: offsets)
        StorageService.shared.saveDividends(dividends)
    }
    
    private func refreshPrices() {
        guard !isRefreshingQuotes else { return }
        isRefreshingQuotes = true
        Task {
            for i in 0..<holdings.count {
                if let quote = try? await StockQuoteService.shared.fetchQuote(symbol: holdings[i].symbol) {
                    holdings[i].currentPrice = quote.currentPrice
                    holdings[i].previousClose = quote.previousClose
                }
            }
            StorageService.shared.saveHoldings(holdings)
            isRefreshingQuotes = false
        }
    }
}

// MARK: - 新增持股表單
struct AddHoldingView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (StockHolding) -> Void
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var sharesString = "1000"
    @State private var costString = ""
    @State private var stockType: StockType = .stock
    @State private var discountString = "0.6"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("股票基本資料") {
                    TextField("代號 (例: 2330, 00878)", text: $symbol)
                        .keyboardType(.asciiCapable)
                    TextField("股票名稱 (例: 台積電)", text: $name)
                    Picker("類型", selection: $stockType) {
                        ForEach(StockType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
                Section("持股與買入成本") {
                    TextField("持有股數 (1張 = 1,000股)", text: $sharesString)
                        .keyboardType(.numberPad)
                    TextField("買入均價 (元)", text: $costString)
                        .keyboardType(.decimalPad)
                    TextField("券商手續費折讓 (例: 0.6 代表6折)", text: $discountString)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新增持股")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let shares = Int(sharesString) ?? 0
                        let cost = Double(costString) ?? 0.0
                        let discount = Double(discountString) ?? 0.6
                        let holding = StockHolding(
                            symbol: symbol,
                            name: name.isEmpty ? symbol : name,
                            shares: shares,
                            averageCost: cost,
                            currentPrice: cost,
                            previousClose: cost,
                            stockType: stockType,
                            brokerFeeDiscount: discount
                        )
                        onSave(holding)
                        dismiss()
                    }
                    .disabled(symbol.isEmpty || costString.isEmpty)
                }
            }
        }
    }
}

// MARK: - 新增配股配息表單
struct AddDividendView: View {
    @Environment(\.dismiss) var dismiss
    let holdings: [StockHolding]
    var onSave: (DividendRecord) -> Void
    
    @State private var selectedIndex = 0
    @State private var exDate = Date()
    @State private var payDate = Date()
    @State private var cashPerShare = ""
    @State private var stockPerShare = ""
    
    var body: some View {
        NavigationStack {
            Form {
                if !holdings.isEmpty {
                    Section("選擇標的") {
                        Picker("持股", selection: $selectedIndex) {
                            ForEach(0..<holdings.count, id: \.self) { i in
                                Text("\(holdings[i].name) (\(holdings[i].symbol))").tag(i)
                            }
                        }
                    }
                }
                Section("配發資訊 (元/股)") {
                    TextField("每股現金股利 (元)", text: $cashPerShare)
                        .keyboardType(.decimalPad)
                    TextField("每股配股股票股利 (元，面額10元)", text: $stockPerShare)
                        .keyboardType(.decimalPad)
                }
                Section("日期設定") {
                    DatePicker("除權息日", selection: $exDate, displayedComponents: .date)
                    DatePicker("預計發放日", selection: $payDate, displayedComponents: .date)
                }
            }
            .navigationTitle("記錄配股配息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        guard !holdings.isEmpty else { return }
                        let holding = holdings[selectedIndex]
                        let record = DividendRecord(
                            holdingSymbol: holding.symbol,
                            holdingName: holding.name,
                            exDividendDate: exDate,
                            paymentDate: payDate,
                            cashDividendPerShare: Double(cashPerShare) ?? 0.0,
                            stockDividendPerShare: Double(stockPerShare) ?? 0.0,
                            sharesSnapshot: holding.shares
                        )
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }
}
