import SwiftUI

// MARK: - 主應用程式五分頁 (對應截圖底部導航列)
struct ContentView: View {
    @State private var selectedTab: Int = 2 // 預設停在「投資總覽」
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 分頁 1: 股息日曆 + 倒數日 (對應截圖 5)
            DividendCalendarTabView()
                .tabItem {
                    Label("股息日曆", systemImage: "calendar.badge.clock")
                }
                .tag(0)
            
            // 分頁 2: 持有 ETF + 股息明細 (對應截圖 4)
            HoldingsListView()
                .tabItem {
                    Label("我的追蹤", systemImage: "heart.text.square")
                }
                .tag(1)
            
            // 分頁 3: 投資總覽 + 圓餅佔比 (對應截圖 1)
            DashboardView()
                .tabItem {
                    Label("投資總覽", systemImage: "chart.pie.fill")
                }
                .tag(2)
            
            // 分頁 4: 日記管理 (對應截圖 2)
            JournalManagementView()
                .tabItem {
                    Label("日記管理", systemImage: "book.pages")
                }
                .tag(3)
            
            // 分頁 5: 股息歷程時間軸 (對應截圖 3)
            DividendTimelineView()
                .tabItem {
                    Label("股息歷程", systemImage: "clock.arrow.circlepath")
                }
                .tag(4)
        }
        .tint(Color(hex: "#007AFF"))
    }
}

// MARK: ==========================================
// MARK: 模組 1: 投資總覽 (對應截圖 1)
// MARK: ==========================================

struct DashboardView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var isPrivacyMasked: Bool = StorageService.shared.isPrivacyMasked
    @State private var isShowingAdd = false
    @State private var isRefreshing = false
    
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var totalCost: Double { holdings.reduce(0) { $0 + $1.totalCostWithFee } }
    var priceGainProfit: Double { holdings.reduce(0) { $0 + $1.unrealizedProfit } }
    var totalDividends: Double { holdings.reduce(0) { $0 + $1.totalDividendsReceived } }
    var totalDividendCount: Int { holdings.reduce(0) { $0 + $1.dividendCount } }
    var frequencyDict: [FrequencyType: Int] { StorageService.shared.getFrequencyDistribution(holdings: holdings) }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. 藍色漸層資產主卡片 (支援眼睛切換遮蔽)
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("總價值")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.85))
                                Spacer()
                                Button {
                                    isPrivacyMasked.toggle()
                                    StorageService.shared.isPrivacyMasked = isPrivacyMasked
                                } label: {
                                    Image(systemName: isPrivacyMasked ? "eye.slash.fill" : "eye.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text(isPrivacyMasked ? "******" : "$\(Int(totalMarketValue).formatted())")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("總成本")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(isPrivacyMasked ? "*****" : "$\(Int(totalCost).formatted())")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("價差獲利")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                    Text(isPrivacyMasked ? "****" : "\(priceGainProfit >= 0 ? "+" : "")$\(Int(priceGainProfit).formatted())")
                                        .font(.subheadline.bold())
                                        .foregroundColor(priceGainProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                                }
                            }
                            
                            // 白色子卡片 (總股息 & 領息次數)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("總股息")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(isPrivacyMasked ? "*****" : "$\(Int(totalDividends).formatted())")
                                        .font(.headline.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.white)
                                .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("領息次數")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(isPrivacyMasked ? "***" : "\(totalDividendCount) 次")
                                        .font(.headline.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(18)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#2F80ED"), Color(hex: "#56CCF2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: Color(hex: "#2F80ED").opacity(0.3), radius: 10, y: 5)
                    }
                    .padding(.horizontal)
                    
                    // 2. 領息頻率卡片 (月配 6 | 雙月配 4 | 季配 2 | 半年配 0 | 年配 4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("領息頻率")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            ForEach(FrequencyType.allCases, id: \.self) { freq in
                                VStack(spacing: 4) {
                                    Text(freq.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(frequencyDict[freq] ?? 0)")
                                        .font(.title3.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // 3. ETF 投資佔比圓餅環形圖 (Donut Chart)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ETF投資佔比")
                            .font(.headline)
                        
                        if holdings.isEmpty {
                            Text("尚無持股數據")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            // 環形圖中心
                            ZStack {
                                DonutChartView(holdings: holdings)
                                    .frame(width: 170, height: 170)
                                
                                VStack(spacing: 2) {
                                    Text("ETF")
                                        .font(.caption.bold())
                                        .foregroundColor(.secondary)
                                    Text("投資佔比")
                                        .font(.subheadline.bold())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            
                            // 標的比例明細列表
                            VStack(spacing: 10) {
                                ForEach(Array(holdings.sorted { $0.marketValue > $1.marketValue }.enumerated()), id: \.element.id) { index, item in
                                    let ratio = totalMarketValue > 0 ? (item.marketValue / totalMarketValue) * 100.0 : 0.0
                                    HStack {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(chartColor(at: index))
                                            .frame(width: 4, height: 26)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.symbol)
                                                .font(.subheadline.bold())
                                            Text(item.name)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text("$\(Int(item.marketValue).formatted())")
                                            .font(.subheadline.bold())
                                        
                                        Text("\(String(format: "%.0f", ratio))%")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.secondary)
                                            .frame(width: 44, alignment: .trailing)
                                    }
                                    .padding(.vertical, 2)
                                    
                                    if index < holdings.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top, 10)
            }
            .navigationTitle("投資總覽")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        refreshQuotes()
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddHoldingSheet { newHolding in
                    holdings.append(newHolding)
                    StorageService.shared.saveHoldings(holdings)
                }
            }
        }
    }
    
    private func refreshQuotes() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            for i in 0..<holdings.count {
                if let quote = try? await StockQuoteService.shared.fetchQuote(symbol: holdings[i].symbol) {
                    holdings[i].currentPrice = quote.currentPrice
                    holdings[i].previousClose = quote.previousClose
                }
            }
            StorageService.shared.saveHoldings(holdings)
            isRefreshing = false
        }
    }
}

// MARK: - 甜甜圈環形圓餅圖實作 (相容 iOS 16 & 17)
struct DonutChartView: View {
    let holdings: [StockHolding]
    
    var body: some View {
        let total = holdings.reduce(0.0) { $0 + $1.marketValue }
        GeometryReader { geo in
            ZStack {
                ForEach(Array(holdings.enumerated()), id: \.element.id) { index, item in
                    let startAngle = calculateAngle(index: index, total: total)
                    let endAngle = calculateAngle(index: index + 1, total: total)
                    
                    DonutSlice(startAngle: startAngle, endAngle: endAngle)
                        .stroke(chartColor(at: index), lineWidth: 28)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
    
    private func calculateAngle(index: Int, total: Double) -> Angle {
        guard total > 0 else { return .degrees(0) }
        let subtotal = holdings.prefix(index).reduce(0.0) { $0 + $1.marketValue }
        return .degrees((subtotal / total) * 360.0 - 90.0)
    }
}

struct DonutSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 14
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

func chartColor(at index: Int) -> Color {
    let colors = [
        Color(hex: "#2F80ED"), Color(hex: "#56CCF2"), Color(hex: "#FFB03A"),
        Color(hex: "#EB5757"), Color(hex: "#6FCF97"), Color(hex: "#BB6BD9"),
        Color(hex: "#F2994A"), Color(hex: "#9B51E0")
    ]
    return colors[index % colors.count]
}

// MARK: ==========================================
// MARK: 模組 2: 日記管理 (對應截圖 2)
// MARK: ==========================================

struct JournalManagementView: View {
    @State private var journals: [JournalEntry] = StorageService.shared.loadJournals()
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var selectedFilter: String = "ALL"
    @State private var isShowingAdd = false
    
    var filteredJournals: [JournalEntry] {
        if selectedFilter == "ALL" {
            return journals
        } else {
            return journals.filter { $0.symbol == selectedFilter }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 用戶資訊頂部卡 (助手 ID 與複製按鈕)
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 38))
                        .foregroundColor(Color(hex: "#007AFF"))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("股息助手")
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text("ID: 10535785149")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        // 設定
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                
                Divider()
                
                // 標的下拉篩選器 (如: 0056-元大高股息)
                HStack {
                    Menu {
                        Button("全部標的") { selectedFilter = "ALL" }
                        ForEach(holdings) { h in
                            Button("\(h.symbol)-\(h.name)") { selectedFilter = h.symbol }
                        }
                    } label: {
                        HStack {
                            Text(filterTitle)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
                // 買賣流水日記列表
                List {
                    if filteredJournals.isEmpty {
                        Text("目前無此標的之投資日記紀錄")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredJournals) { entry in
                            HStack(alignment: .center, spacing: 12) {
                                // 橘色買 / 綠色賣 標籤
                                Text(entry.type.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color(hex: entry.type.badgeColorHex))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.dateString)
                                        .font(.subheadline.bold())
                                    Text("買入日期")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("$\(String(format: "%.2f", entry.price))")
                                        .font(.subheadline.bold())
                                    Text("買入金額")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("$\(Int(entry.totalAmount))")
                                        .font(.subheadline.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                    Text(entry.lotsText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: deleteJournal)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("日記管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddJournalSheet(holdings: holdings) { newEntry in
                    journals.insert(newEntry, at: 0)
                    StorageService.shared.saveJournals(journals)
                }
            }
        }
    }
    
    private var filterTitle: String {
        if selectedFilter == "ALL" { return "全部標的" }
        if let h = holdings.first(where: { $0.symbol == selectedFilter }) {
            return "\(h.symbol)-\(h.name)"
        }
        return selectedFilter
    }
    
    private func deleteJournal(at offsets: IndexSet) {
        journals.remove(atOffsets: offsets)
        StorageService.shared.saveJournals(journals)
    }
}

// MARK: ==========================================
// MARK: 模組 3: 股息歷程時間軸 (對應截圖 3)
// MARK: ==========================================

struct DividendTimelineView: View {
    @State private var monthlyList: [MonthlyTimelineSummary] = StorageService.shared.getMonthlyTimelineSummaries()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(monthlyList.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            // 左側垂直時間軸節點與線條
                            VStack(spacing: 0) {
                                Text(item.monthKey.replacingOccurrences(of: "2025年 ", with: "").replacingOccurrences(of: "2024年 ", with: ""))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text(item.monthKey.contains("2025") ? "2025" : "2024")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 6)
                                
                                Circle()
                                    .fill(Color(hex: "#007AFF"))
                                    .frame(width: 10, height: 10)
                                
                                if index < monthlyList.count - 1 {
                                    Rectangle()
                                        .fill(Color(hex: "#007AFF").opacity(0.3))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 48)
                            
                            // 右側詳細月度數據卡片
                            VStack(spacing: 8) {
                                HStack {
                                    Text("總價值")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("$\(Int(item.totalMarketValue).formatted())")
                                        .font(.headline.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("總成本")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("$\(Int(item.totalCost).formatted())")
                                        .font(.subheadline)
                                }
                                
                                HStack {
                                    Text("價差獲利")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(item.priceGainProfit >= 0 ? "+" : "")$\(Int(item.priceGainProfit).formatted())")
                                        .font(.subheadline.bold())
                                        .foregroundColor(item.priceGainProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                                }
                                
                                HStack {
                                    Text("手續費")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("$\(Int(item.totalFee))")
                                        .font(.caption)
                                }
                                
                                HStack {
                                    Text("當月股息")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("$\(Int(item.monthDividend).formatted())")
                                        .font(.subheadline.bold())
                                        .foregroundColor(Color(hex: "#FF9500"))
                                }
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("股息歷程")
        }
    }
}

// MARK: ==========================================
// MARK: 模組 4: 持有 ETF + 股息明細 (對應截圖 4)
// MARK: ==========================================

struct HoldingsListView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var expandedSymbols: Set<String> = []
    @State private var selectedHoldingForDetail: StockHolding? = nil
    @State private var isShowingAdd = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(holdings) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            // 標的代號 + 頻率Badge + 名稱
                            HStack(spacing: 6) {
                                Text(item.symbol)
                                    .font(.headline.bold())
                                
                                Text(item.frequency.rawValue)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: item.frequency.badgeColorHex).opacity(0.15))
                                    .foregroundColor(Color(hex: item.frequency.badgeColorHex))
                                    .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            // 展開收合箭頭
                            Button {
                                if expandedSymbols.contains(item.symbol) {
                                    expandedSymbols.remove(item.symbol)
                                } else {
                                    expandedSymbols.insert(item.symbol)
                                }
                            } label: {
                                Image(systemName: expandedSymbols.contains(item.symbol) ? "chevron.up" : "chevron.down")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("總成本")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("$\(Int(item.totalCostWithFee).formatted())")
                                    .font(.subheadline.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("總股數")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("\(item.shares.formatted())股")
                                    .font(.subheadline.bold())
                            }
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("總損益")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("\(item.unrealizedProfit >= 0 ? "+" : "")$\(Int(item.unrealizedProfit).formatted())")
                                    .font(.subheadline.bold())
                                    .foregroundColor(item.unrealizedProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("已領息")
                                    .font(.caption).foregroundColor(.secondary)
                                Text("(領息\(item.dividendCount)次)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 展開內容：現值、均價、現價、股息明細按鈕
                        if expandedSymbols.contains(item.symbol) {
                            VStack(spacing: 8) {
                                Divider()
                                HStack {
                                    Text("現值: $\(Int(item.marketValue).formatted())")
                                    Spacer()
                                    Text("均價: $\(String(format: "%.2f", item.averageCost))")
                                    Spacer()
                                    Text("現價: $\(String(format: "%.2f", item.currentPrice))")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                Button {
                                    selectedHoldingForDetail = item
                                } label: {
                                    HStack {
                                        Image(systemName: "chart.bar.doc.horizontal")
                                        Text("查看 \(item.name) 股息紀錄")
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(hex: "#007AFF"))
                                    .cornerRadius(8)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteHolding)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("持有ETF")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedHoldingForDetail) { h in
                HoldingDividendDetailView(holding: h)
            }
            .sheet(isPresented: $isShowingAdd) {
                AddHoldingSheet { newHolding in
                    holdings.append(newHolding)
                    StorageService.shared.saveHoldings(holdings)
                }
            }
        }
    }
    
    private func deleteHolding(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        StorageService.shared.saveHoldings(holdings)
    }
}

// MARK: - 單檔 ETF 歷史除息明細頁面 (對應截圖 4 右側卡片)
struct HoldingDividendDetailView: View {
    @Environment(\.dismiss) var dismiss
    let holding: StockHolding
    @State private var histories: [HoldingDividendHistory] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 標的頭部
                HStack(spacing: 8) {
                    Text(holding.symbol)
                        .font(.title2.bold())
                    Text(holding.name)
                        .font(.title3)
                    Text(holding.frequency.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: holding.frequency.badgeColorHex).opacity(0.15))
                        .foregroundColor(Color(hex: holding.frequency.badgeColorHex))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                // 總股息 & 領息次數卡片
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("總股息").font(.caption).foregroundColor(.secondary)
                        Text("$\(Int(holding.totalDividendsReceived).formatted())")
                            .font(.title2.bold())
                            .foregroundColor(Color(hex: "#007AFF"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("領息次數").font(.caption).foregroundColor(.secondary)
                        Text("\(histories.count) 次")
                            .font(.title2.bold())
                            .foregroundColor(Color(hex: "#007AFF"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // 表頭
                HStack {
                    Text("股利發放日").font(.caption.bold()).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                    Text("配息金額").font(.caption.bold()).foregroundColor(.secondary).frame(width: 70, alignment: .trailing)
                    Text("除息股數").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
                    Text("股息").font(.caption.bold()).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                
                // 歷史除息流水
                List(histories) { h in
                    HStack {
                        Text(h.paymentDateString)
                            .font(.subheadline)
                            .frame(width: 90, alignment: .leading)
                        Text("$\(String(format: "%.2f", h.dividendPerShare))")
                            .font(.subheadline)
                            .frame(width: 70, alignment: .trailing)
                        Text("\(h.sharesSnapshot.formatted())")
                            .font(.subheadline)
                            .frame(width: 80, alignment: .trailing)
                        Text("$\(Int(h.totalReceived).formatted())")
                            .font(.subheadline.bold())
                            .foregroundColor(Color(hex: "#007AFF"))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("股息紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .onAppear {
                histories = StorageService.shared.loadHoldingHistories(symbol: holding.symbol)
            }
        }
    }
}

// MARK: ==========================================
// MARK: 模組 5: ETF 日曆 + 倒數日 (對應截圖 5)
// MARK: ==========================================

struct DividendCalendarTabView: View {
    @State private var selectedMode: Int = 1 // 0: 股息日曆, 1: 倒數日
    @State private var events: [DividendEvent] = StorageService.shared.loadEvents()
    @State private var isShowingAdd = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 模式切換 Switch
                Picker("顯示模式", selection: $selectedMode) {
                    Text("股息日曆").tag(0)
                    Text("倒數日").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if selectedMode == 0 {
                    // 模式 A: 股息日曆 (帶圓點之月曆 + 當月配息清單)
                    DividendCalendarMonthView(events: events)
                } else {
                    // 模式 B: 倒數日 (按剩餘天數精準排序之清單)
                    DividendCountdownListView(events: events)
                }
            }
            .navigationTitle("ETF日曆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddDividendEventSheet { newEvent in
                    events.append(newEvent)
                    StorageService.shared.saveEvents(events)
                }
            }
        }
    }
}

// 倒數日清單視圖
struct DividendCountdownListView: View {
    let events: [DividendEvent]
    
    var sortedEvents: [DividendEvent] {
        events.sorted { $0.daysRemaining < $1.daysRemaining }
    }
    
    var body: some View {
        List {
            ForEach(sortedEvents) { event in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(event.symbol).font(.headline)
                            Text(event.name).font(.subheadline)
                        }
                        Text("\(event.eventType.rawValue): \(event.dateString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 倒數天數 Badge (如: 今天, 剩 2 天, 剩 6 天)
                    Text(event.countdownBadgeText)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(hex: event.countdownBadgeColorHex))
                        .cornerRadius(16)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
    }
}

// 股息日曆月曆視圖
struct DividendCalendarMonthView: View {
    let events: [DividendEvent]
    @State private var currentMonth: Date = Date()
    
    var body: some View {
        VStack(spacing: 12) {
            // 月曆圖例標記
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#007AFF")).frame(width: 8, height: 8)
                    Text("除息日").font(.caption).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#5AC8FA")).frame(width: 8, height: 8)
                    Text("最後購買日").font(.caption).foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "#34C759")).frame(width: 8, height: 8)
                    Text("發放日").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            // 當期配發清單 (對應截圖 5 下方)
            List {
                Section("當月配息日程") {
                    ForEach(events) { ev in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(ev.symbol).font(.headline)
                                    Text(ev.frequency.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color(hex: ev.frequency.badgeColorHex).opacity(0.15))
                                        .foregroundColor(Color(hex: ev.frequency.badgeColorHex))
                                        .cornerRadius(4)
                                }
                                Text(ev.name).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(String(format: "%.2f", ev.cashPerShare))")
                                    .font(.headline.bold())
                                    .foregroundColor(Color(hex: "#007AFF"))
                                Text(ev.dateString)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: ==========================================
// MARK: 輸入對話框 (Sheet Forms)
// MARK: ==========================================

struct AddHoldingSheet: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (StockHolding) -> Void
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var frequency: FrequencyType = .quarterly
    @State private var shares = "1000"
    @State private var cost = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("標的資料") {
                    TextField("代號 (例: 0056, 00878)", text: $symbol).keyboardType(.asciiCapable)
                    TextField("名稱 (例: 元大高股息)", text: $name)
                    Picker("配息頻率", selection: $frequency) {
                        ForEach(FrequencyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("持股與成本") {
                    TextField("持有股數", text: $shares).keyboardType(.numberPad)
                    TextField("買入均價", text: $cost).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新增持股")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let h = StockHolding(
                            symbol: symbol,
                            name: name.isEmpty ? symbol : name,
                            frequency: frequency,
                            shares: Int(shares) ?? 0,
                            averageCost: Double(cost) ?? 0,
                            currentPrice: Double(cost) ?? 0
                        )
                        onSave(h)
                        dismiss()
                    }
                    .disabled(symbol.isEmpty || cost.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct AddJournalSheet: View {
    @Environment(\.dismiss) var dismiss
    let holdings: [StockHolding]
    var onSave: (JournalEntry) -> Void
    
    @State private var selectedSymbol = ""
    @State private var type: TransactionType = .buy
    @State private var price = ""
    @State private var shares = "1000"
    @State private var date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("交易標的") {
                    if !holdings.isEmpty {
                        Picker("選擇持股", selection: $selectedSymbol) {
                            ForEach(holdings) { Text("\($0.symbol) \($0.name)").tag($0.symbol) }
                        }
                    } else {
                        TextField("股票代號", text: $selectedSymbol)
                    }
                    Picker("類型", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("價格與股數") {
                    TextField("單價 (元)", text: $price).keyboardType(.decimalPad)
                    TextField("股數 (1,000股 = 1張)", text: $shares).keyboardType(.numberPad)
                    DatePicker("交易日期", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("新增日記")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let holdingName = holdings.first(where: { $0.symbol == selectedSymbol })?.name ?? selectedSymbol
                        let entry = JournalEntry(
                            symbol: selectedSymbol,
                            name: holdingName,
                            type: type,
                            date: date,
                            price: Double(price) ?? 0,
                            shares: Int(shares) ?? 0
                        )
                        onSave(entry)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear {
                if let first = holdings.first { selectedSymbol = first.symbol }
            }
        }
    }
}

struct AddDividendEventSheet: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (DividendEvent) -> Void
    
    @State private var symbol = "0056"
    @State private var name = "元大高股息"
    @State private var eventType: DividendEventType = .exDividendDate
    @State private var targetDate = Date()
    @State private var cash = "0.79"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("事件標的") {
                    TextField("代號", text: $symbol)
                    TextField("名稱", text: $name)
                    Picker("事件類型", selection: $eventType) {
                        Text("最後購買日").tag(DividendEventType.lastBuyDate)
                        Text("除息日").tag(DividendEventType.exDividendDate)
                        Text("股利發放日").tag(DividendEventType.paymentDate)
                    }
                    DatePicker("日期", selection: $targetDate, displayedComponents: .date)
                    TextField("每股配息金額 (元)", text: $cash).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("新增日程")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let ev = DividendEvent(
                            symbol: symbol,
                            name: name,
                            eventType: eventType,
                            targetDate: targetDate,
                            cashPerShare: Double(cash) ?? 0
                        )
                        onSave(ev)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - Color Hex 擴充
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
