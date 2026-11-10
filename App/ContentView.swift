import SwiftUI
import UserNotifications

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
    @State private var refreshMessage = ""
    @State private var lastRefreshedTime = ""
    
    // 存股被動收入目標計算機 State
    @State private var targetMonthlyIncome: Double = 30000 // 目標月領 3 萬元
    @State private var expectedYield: Double = 0.075       // 預期平均殖利率 7.5%
    @State private var monthlyDCAAmount: Double = 20000     // 每月定期定額 2 萬元
    
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var totalCost: Double { holdings.reduce(0) { $0 + $1.totalCostWithFee } }
    var priceGainProfit: Double { holdings.reduce(0) { $0 + $1.unrealizedProfit } }
    var totalDividends: Double { holdings.reduce(0) { $0 + $1.totalDividendsReceived } }
    var totalDividendCount: Int { holdings.reduce(0) { $0 + $1.dividendCount } }
    var frequencyDict: [FrequencyType: Int] { StorageService.shared.getFrequencyDistribution(holdings: holdings) }
    
    // 當前推算年化股息與月均股息
    var estimatedAnnualDividend: Double { totalMarketValue * expectedYield }
    var currentMonthlyDividend: Double { estimatedAnnualDividend / 12.0 }
    var goalProgress: Double {
        targetMonthlyIncome > 0 ? min(1.0, currentMonthlyDividend / targetMonthlyIncome) : 0
    }
    var neededPrincipal: Double {
        expectedYield > 0 ? (targetMonthlyIncome * 12.0) / expectedYield : 0
    }
    var principalGap: Double { max(0, neededPrincipal - totalMarketValue) }
    var yearsToGoal: Double {
        let monthly = monthlyDCAAmount > 0 ? monthlyDCAAmount : 10000
        return (principalGap / (monthly * 12.0))
    }
    
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
                            
                            if !lastRefreshedTime.isEmpty {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("報價更新時間: \(lastRefreshedTime)")
                                }
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
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
                    
                    // 2. 存股被動收入目標計算機 (進階功能)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("存股被動收入目標", systemImage: "target")
                                .font(.headline.bold())
                            Spacer()
                            Text("達成率 \(String(format: "%.1f", goalProgress * 100))%")
                                .font(.subheadline.bold())
                                .foregroundColor(Color(hex: "#007AFF"))
                        }
                        
                        // 進度條
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "#007AFF"), Color(hex: "#5AC8FA")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(10, geo.size.width * CGFloat(goalProgress)), height: 10)
                            }
                        }
                        .frame(height: 10)
                        
                        // 目標快選按鈕
                        HStack(spacing: 8) {
                            GoalChipButton(title: "月領1萬", target: 10000, current: $targetMonthlyIncome)
                            GoalChipButton(title: "月領3萬", target: 30000, current: $targetMonthlyIncome)
                            GoalChipButton(title: "月領5萬", target: 50000, current: $targetMonthlyIncome)
                            GoalChipButton(title: "月領10萬", target: 100000, current: $targetMonthlyIncome)
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        // 試算數據網格
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目前推算月股息").font(.caption).foregroundColor(.secondary)
                                Text("$\(Int(currentMonthlyDividend).formatted())")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color(hex: "#007AFF"))
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 2) {
                                Text("距目標本金還差").font(.caption).foregroundColor(.secondary)
                                Text("$\(Int(principalGap).formatted())")
                                    .font(.subheadline.bold())
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("定期定額預估").font(.caption).foregroundColor(.secondary)
                                Text(principalGap <= 0 ? "已達成目標！" : "約 \(String(format: "%.1f", yearsToGoal)) 年")
                                    .font(.subheadline.bold())
                                    .foregroundColor(principalGap <= 0 ? .green : .orange)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    
                    // 3. 領息頻率卡片 (月配 / 雙月配 / 季配 / 半年配 / 年配)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("領息頻率")
                            .font(.headline.bold())
                        
                        HStack(spacing: 8) {
                            FrequencyBadgeCard(title: "月配", count: frequencyDict[.monthly] ?? 0, colorHex: FrequencyType.monthly.badgeColorHex)
                            FrequencyBadgeCard(title: "雙月配", count: frequencyDict[.bimonthly] ?? 0, colorHex: FrequencyType.bimonthly.badgeColorHex)
                            FrequencyBadgeCard(title: "季配", count: frequencyDict[.quarterly] ?? 0, colorHex: FrequencyType.quarterly.badgeColorHex)
                            FrequencyBadgeCard(title: "半年配", count: frequencyDict[.semiannual] ?? 0, colorHex: FrequencyType.semiannual.badgeColorHex)
                            FrequencyBadgeCard(title: "年配", count: frequencyDict[.annual] ?? 0, colorHex: FrequencyType.annual.badgeColorHex)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    
                    // 4. ETF 投資佔比 (環形圓餅圖 Donut Chart)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ETF 投資佔比")
                            .font(.headline.bold())
                        
                        // Donut Chart 圖形
                        ZStack {
                            DonutChartView(holdings: holdings)
                                .frame(width: 200, height: 200)
                            
                            VStack(spacing: 4) {
                                Text("ETF")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("投資佔比")
                                    .font(.subheadline.bold())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        
                        // 各標的佔比清單
                        VStack(spacing: 12) {
                            ForEach(Array(holdings.enumerated()), id: \.element.id) { index, item in
                                let percentage = totalMarketValue > 0 ? (item.marketValue / totalMarketValue) * 100.0 : 0
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(donutColor(index: index))
                                        .frame(width: 4, height: 20)
                                    
                                    Text("\(item.symbol) \(item.name)")
                                        .font(.subheadline.bold())
                                    
                                    Spacer()
                                    
                                    Text(isPrivacyMasked ? "*****" : "$\(Int(item.marketValue).formatted())")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text(String(format: "%.1f%%", percentage))
                                        .font(.subheadline.bold())
                                        .frame(width: 55, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                }
                .padding()
            }
            .refreshable {
                await refreshQuotes()
            }
            .navigationTitle("投資總覽")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refreshQuotes() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text(isRefreshing ? "更新中..." : "更新報價")
                                .font(.caption)
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color(hex: "#007AFF"))
                    }
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddHoldingSheet { newHolding, isDCA in
                    StorageService.shared.addOrUpdateHolding(newHolding, isDCA: isDCA, autoAddJournal: true)
                    holdings = StorageService.shared.loadHoldings()
                }
            }
            .onAppear {
                holdings = StorageService.shared.loadHoldings()
            }
        }
    }
    
    private func refreshQuotes() async {
        isRefreshing = true
        let res = await StorageService.shared.refreshAllStockQuotes()
        holdings = StorageService.shared.loadHoldings()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastRefreshedTime = formatter.string(from: Date())
        isRefreshing = false
    }
    
    private func donutColor(index: Int) -> Color {
        let palette = [
            Color(hex: "#007AFF"), Color(hex: "#5856D6"), Color(hex: "#FF9500"),
            Color(hex: "#34C759"), Color(hex: "#AF52DE"), Color(hex: "#5AC8FA"),
            Color(hex: "#FF2D55"), Color(hex: "#FFCC00")
        ]
        return palette[index % palette.count]
    }
}

struct GoalChipButton: View {
    let title: String
    let target: Double
    @Binding var current: Double
    
    var isSelected: Bool { Int(current) == Int(target) }
    
    var body: some View {
        Button {
            current = target
        } label: {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color(hex: "#007AFF") : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
    }
}

struct FrequencyBadgeCard: View {
    let title: String
    let count: Int
    let colorHex: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(Color(hex: colorHex))
            Text("\(count)")
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: colorHex).opacity(0.12))
        .cornerRadius(10)
    }
}

// 繪製 Donut Chart 圓餅圖
struct DonutChartView: View {
    let holdings: [StockHolding]
    
    var totalValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    
    var slices: [(startAngle: Angle, endAngle: Angle, color: Color)] {
        guard totalValue > 0 else { return [] }
        var list: [(startAngle: Angle, endAngle: Angle, color: Color)] = []
        var currentDegree: Double = -90.0
        
        let palette = [
            Color(hex: "#007AFF"), Color(hex: "#5856D6"), Color(hex: "#FF9500"),
            Color(hex: "#34C759"), Color(hex: "#AF52DE"), Color(hex: "#5AC8FA"),
            Color(hex: "#FF2D55"), Color(hex: "#FFCC00")
        ]
        
        for (i, h) in holdings.enumerated() {
            let sliceDeg = (h.marketValue / totalValue) * 360.0
            let start = Angle(degrees: currentDegree)
            let end = Angle(degrees: currentDegree + sliceDeg)
            list.append((startAngle: start, endAngle: end, color: palette[i % palette.count]))
            currentDegree += sliceDeg
        }
        return list
    }
    
    var body: some View {
        ZStack {
            ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                DonutSlice(startAngle: slice.startAngle, endAngle: slice.endAngle)
                    .stroke(slice.color, style: StrokeStyle(lineWidth: 24, lineCap: .butt))
            }
        }
    }
}

struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 12
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

// MARK: ==========================================
// MARK: 模組 2: 日記管理 (對應截圖 2)
// MARK: ==========================================

struct JournalManagementView: View {
    @State private var journals: [JournalEntry] = StorageService.shared.loadJournals()
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var selectedFilterSymbol: String = "全部"
    @State private var isShowingAdd = false
    @State private var isShowingBackup = false
    
    var filteredJournals: [JournalEntry] {
        if selectedFilterSymbol == "全部" {
            return journals
        }
        return journals.filter { $0.symbol == selectedFilterSymbol }
    }
    
    var filterOptions: [String] {
        var set = Array(Set(journals.map { $0.symbol })).sorted()
        set.insert("全部", at: 0)
        return set
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. 助手專屬頂部列 (對應截圖 2 個人資訊欄)
                HStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "#007AFF"), Color(hex: "#5AC8FA")], startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("存股助手")
                            .font(.headline.bold())
                        HStack(spacing: 4) {
                            Text("ID: 8886291")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        isShowingBackup = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                            Text("備份/還原")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                
                // 2. 標的下拉篩選選單
                HStack {
                    Text("篩選標的:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("選擇標的", selection: $selectedFilterSymbol) {
                        ForEach(filterOptions, id: \.self) { opt in
                            Text(opt == "全部" ? "全部標的" : opt).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    Text("共 \(filteredJournals.count) 筆日記")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                // 3. 交易日記流水清單 (對應截圖 2)
                List {
                    ForEach(filteredJournals) { item in
                        HStack(spacing: 12) {
                            // 橘色「買」/ 綠色「賣」圓形 Badge
                            Text(item.type.rawValue)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color(hex: item.type.badgeColorHex))
                                .clipShape(Circle())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.dateString)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(4)
                                    }
                                }
                                HStack(spacing: 6) {
                                    Text(item.symbol)
                                        .font(.subheadline.bold())
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(Int(item.totalAmount).formatted())")
                                    .font(.headline.bold())
                                Text("$\(String(format: "%.2f", item.price)) · \(item.lotsText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteJournal)
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
            .sheet(isPresented: $isShowingBackup) {
                DataBackupSheet {
                    journals = StorageService.shared.loadJournals()
                    holdings = StorageService.shared.loadHoldings()
                }
            }
        }
    }
    
    private func deleteJournal(at offsets: IndexSet) {
        journals.remove(atOffsets: offsets)
        StorageService.shared.saveJournals(journals)
    }
}

// 資料備份與還原 Sheet
struct DataBackupSheet: View {
    @Environment(\.dismiss) var dismiss
    var onDataRestored: () -> Void
    
    @State private var jsonString: String = ""
    @State private var importText: String = ""
    @State private var isCopied = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("匯出資料 (全體備份)") {
                    Text("可將您的所有存股持股、日記流水、除息事件轉為 JSON 文字，換機或更新 IPA 時無痛還原。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        if let json = StorageService.shared.exportAllDataAsJSON() {
                            UIPasteboard.general.string = json
                            isCopied = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(isCopied ? "已複製完整 JSON 至剪貼簿！" : "一鍵複製全部備份至剪貼簿")
                        }
                        .foregroundColor(isCopied ? .green : Color(hex: "#007AFF"))
                    }
                }
                
                Section("還原資料 (匯入備份)") {
                    Text("請在此貼上先前複製的備份 JSON 文字：")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $importText)
                        .frame(height: 120)
                        .font(.system(size: 11, design: .monospaced))
                    
                    Button("執行資料還原") {
                        if StorageService.shared.importDataFromJSON(importText) {
                            alertMessage = "資料還原成功！"
                            showAlert = true
                            onDataRestored()
                        } else {
                            alertMessage = "還原失敗：JSON 格式無效，請確認貼上完整的備份文字。"
                            showAlert = true
                        }
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("備份與還原")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .alert(alertMessage, isPresented: $showAlert) {
                Button("確定") {
                    if alertMessage.contains("成功") { dismiss() }
                }
            }
        }
    }
}

// MARK: ==========================================
// MARK: 模組 3: 股息歷程時間軸 (對應截圖 3)
// MARK: ==========================================

struct DividendTimelineView: View {
    let monthlySummaries: [MonthlyTimelineSummary] = StorageService.shared.getMonthlyTimelineSummaries()
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(monthlySummaries.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            // 左側垂直時間軸線條與節點
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color(hex: "#007AFF"))
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 4)
                                
                                if index < monthlySummaries.count - 1 {
                                    Rectangle()
                                        .fill(Color(hex: "#007AFF").opacity(0.3))
                                        .frame(width: 2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            
                            // 右側月份數據卡片 (對應截圖 3)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.monthKey)
                                    .font(.headline.bold())
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("總價值").font(.caption).foregroundColor(.secondary)
                                        Text("$\(Int(item.totalMarketValue).formatted())").font(.subheadline.bold())
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("總成本").font(.caption).foregroundColor(.secondary)
                                        Text("$\(Int(item.totalCost).formatted())").font(.subheadline.bold())
                                    }
                                }
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("價差獲利").font(.caption).foregroundColor(.secondary)
                                        Text("\(item.priceGainProfit >= 0 ? "+" : "")$\(Int(item.priceGainProfit).formatted())")
                                            .font(.subheadline.bold())
                                            .foregroundColor(item.priceGainProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("手續費").font(.caption).foregroundColor(.secondary)
                                        Text("$\(Int(item.totalFee).formatted())").font(.subheadline.bold())
                                    }
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("當月股息")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text("$\(Int(item.monthDividend).formatted())")
                                        .font(.title3.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("股息歷程")
            .navigationBarTitleDisplayMode(.inline)
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
    @State private var holdingToEdit: StockHolding? = nil
    @State private var holdingToDelete: StockHolding? = nil
    @State private var isShowingAdd = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    
    var filteredHoldings: [StockHolding] {
        if searchText.isEmpty { return holdings }
        return holdings.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredHoldings) { item in
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
                        
                        // 展開內容：現值、均價、現價、多功能操作區
                        if expandedSymbols.contains(item.symbol) {
                            VStack(spacing: 10) {
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
                                
                                // 操作按鈕組
                                HStack(spacing: 8) {
                                    // 編輯按鈕
                                    Button {
                                        holdingToEdit = item
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                            Text("編輯")
                                        }
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(8)
                                    }
                                    
                                    // 股息紀錄按鈕
                                    Button {
                                        selectedHoldingForDetail = item
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "chart.bar.doc.horizontal")
                                            Text("股息紀錄")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Color(hex: "#007AFF"))
                                        .cornerRadius(8)
                                    }
                                    
                                    // 刪除按鈕
                                    Button {
                                        holdingToDelete = item
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption.bold())
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.red.opacity(0.12))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteHolding)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "搜尋代號或名稱 (例: 0056, 台積電)")
            .refreshable {
                await refreshQuotes()
            }
            .navigationTitle("持有ETF")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refreshQuotes() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .confirmationDialog(
                "確定要刪除 \(holdingToDelete?.symbol ?? "") \(holdingToDelete?.name ?? "") 嗎？",
                isPresented: Binding(get: { holdingToDelete != nil }, set: { if !$0 { holdingToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("刪除存股", role: .destructive) {
                    if let target = holdingToDelete {
                        StorageService.shared.deleteHolding(id: target.id)
                        holdings = StorageService.shared.loadHoldings()
                    }
                    holdingToDelete = nil
                }
                Button("取消", role: .cancel) { holdingToDelete = nil }
            } message: {
                Text("此操作將從您的總資產與追蹤清單中移除此標的。")
            }
            .sheet(item: $selectedHoldingForDetail) { h in
                HoldingDividendDetailView(holding: h)
            }
            .sheet(item: $holdingToEdit) { h in
                EditHoldingSheet(holding: h) { updated in
                    StorageService.shared.updateHolding(updated)
                    holdings = StorageService.shared.loadHoldings()
                } onDelete: {
                    StorageService.shared.deleteHolding(id: h.id)
                    holdings = StorageService.shared.loadHoldings()
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddHoldingSheet { newHolding, isDCA in
                    StorageService.shared.addOrUpdateHolding(newHolding, isDCA: isDCA, autoAddJournal: true)
                    holdings = StorageService.shared.loadHoldings()
                }
            }
            .onAppear {
                holdings = StorageService.shared.loadHoldings()
            }
        }
    }
    
    private func deleteHolding(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        StorageService.shared.saveHoldings(holdings)
    }
    
    private func refreshQuotes() async {
        isRefreshing = true
        _ = await StorageService.shared.refreshAllStockQuotes()
        holdings = StorageService.shared.loadHoldings()
        isRefreshing = false
    }
}

// 編輯持股 Sheet
struct EditHoldingSheet: View {
    @Environment(\.dismiss) var dismiss
    let holding: StockHolding
    var onSave: (StockHolding) -> Void
    var onDelete: () -> Void
    
    @State private var name: String = ""
    @State private var frequency: FrequencyType = .quarterly
    @State private var shares: String = ""
    @State private var averageCost: String = ""
    @State private var currentPrice: String = ""
    @State private var totalDividends: String = ""
    @State private var dividendCount: String = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("標的資訊 (\(holding.symbol))") {
                    TextField("名稱", text: $name)
                    Picker("配息頻率", selection: $frequency) {
                        ForEach(FrequencyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                
                Section("持股與成本") {
                    HStack {
                        Text("持有股數")
                        Spacer()
                        TextField("股數", text: $shares).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("買入均價 (元)")
                        Spacer()
                        TextField("均價", text: $averageCost).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("目前現價 (元)")
                        Spacer()
                        TextField("現價", text: $currentPrice).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                
                Section("累計已領股息") {
                    HStack {
                        Text("累計股息 (元)")
                        Spacer()
                        TextField("總股息", text: $totalDividends).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("領息次數")
                        Spacer()
                        TextField("次數", text: $dividendCount).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("刪除此存股標的")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("編輯 \(holding.symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存修改") {
                        var updated = holding
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.frequency = frequency
                        updated.shares = Int(shares) ?? holding.shares
                        updated.averageCost = Double(averageCost) ?? holding.averageCost
                        updated.currentPrice = Double(currentPrice) ?? holding.currentPrice
                        updated.totalDividendsReceived = Double(totalDividends) ?? holding.totalDividendsReceived
                        updated.dividendCount = Int(dividendCount) ?? holding.dividendCount
                        updated.updatedAt = Date()
                        onSave(updated)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .confirmationDialog("確定要刪除 \(holding.symbol) 嗎？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("確定刪除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("刪除後將無法恢復，並將自總市值扣除。")
            }
            .onAppear {
                name = holding.name
                frequency = holding.frequency
                shares = "\(holding.shares)"
                averageCost = String(format: "%.2f", holding.averageCost)
                currentPrice = String(format: "%.2f", holding.currentPrice)
                totalDividends = "\(Int(holding.totalDividendsReceived))"
                dividendCount = "\(holding.dividendCount)"
            }
        }
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
    @State private var isNotificationsEnabled: Bool = NotificationService.shared.isNotificationsEnabled
    @State private var isShowingAdd = false
    @State private var notificationStatusMessage = ""
    @State private var showNotificationToast = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 頂部除息推播通知開關欄 (進階功能)
                HStack {
                    Image(systemName: isNotificationsEnabled ? "bell.badge.fill" : "bell.slash")
                        .foregroundColor(isNotificationsEnabled ? Color(hex: "#007AFF") : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("除息前一天推播提醒 (08:30)")
                            .font(.subheadline.bold())
                        Text(isNotificationsEnabled ? "已開啟除息前日提醒與當日提醒" : "點擊開啟本機推播通知，不再錯過除息")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $isNotificationsEnabled)
                        .labelsHidden()
                        .onChange(of: isNotificationsEnabled) { enabled in
                            if enabled {
                                NotificationService.shared.requestAuthorization { granted in
                                    if granted {
                                        let holdings = StorageService.shared.loadHoldings()
                                        NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                                        notificationStatusMessage = "🔔 已成功排程除息前通知！"
                                        showNotificationToast = true
                                    } else {
                                        isNotificationsEnabled = false
                                        notificationStatusMessage = "請至 iOS「設定」允許本 App 通知權限"
                                        showNotificationToast = true
                                    }
                                }
                            } else {
                                NotificationService.shared.isNotificationsEnabled = false
                                NotificationService.shared.syncDividendReminders(events: events, holdings: [])
                            }
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                
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
                    let holdings = StorageService.shared.loadHoldings()
                    NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                }
            }
            .alert(notificationStatusMessage, isPresented: $showNotificationToast) {
                Button("確定") {}
            }
            .onAppear {
                events = StorageService.shared.loadEvents()
                NotificationService.shared.checkAuthorization { auth in
                    isNotificationsEnabled = auth && NotificationService.shared.isNotificationsEnabled
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
    var onSave: (StockHolding, Bool) -> Void // (holding, isDCA)
    
    @State private var symbol = ""
    @State private var name = ""
    @State private var frequency: FrequencyType = .quarterly
    @State private var stockType: StockType = .etf
    @State private var shares = "1000"
    @State private var cost = ""
    @State private var isDCAMode = true
    @State private var autoAddJournal = true
    
    private var existingHolding: StockHolding? {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return StorageService.shared.loadHoldings().first { $0.symbol == clean }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 熱門標的快速選取 Chip 列
                Section("熱門台股 / 高股息 ETF 快速選取") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PopularStockPreset.allPresets) { preset in
                                Button {
                                    symbol = preset.symbol
                                    name = preset.name
                                    frequency = preset.frequency
                                    stockType = preset.stockType
                                    if cost.isEmpty {
                                        cost = String(format: "%.2f", preset.defaultPrice)
                                    }
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(preset.symbol)
                                            .font(.subheadline.bold())
                                        Text(preset.name)
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(symbol == preset.symbol ? Color(hex: "#007AFF") : Color(.systemGray5))
                                    .foregroundColor(symbol == preset.symbol ? .white : .primary)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("標的資料") {
                    TextField("代號 (例: 0056, 00878, 2330)", text: $symbol)
                        .keyboardType(.asciiCapable)
                    TextField("名稱 (例: 元大高股息)", text: $name)
                    Picker("配息頻率", selection: $frequency) {
                        ForEach(FrequencyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("標的類型", selection: $stockType) {
                        Text("ETF 指數型 (證交稅 0.1%)").tag(StockType.etf)
                        Text("一般個股 (證交稅 0.3%)").tag(StockType.stock)
                    }
                }
                
                // 智慧加碼提示
                if let existing = existingHolding {
                    Section("🔄 加碼存股試算 (您已持有 \(existing.symbol))") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("目前已持有: \(existing.shares.formatted()) 股 · 均價 $\(String(format: "%.2f", existing.averageCost))")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            Picker("存股操作模式", selection: $isDCAMode) {
                                Text("定期定額加碼 (加權均價)").tag(true)
                                Text("直接覆蓋原資料").tag(false)
                            }
                            .pickerStyle(.segmented)
                            
                            if isDCAMode, let addShares = Int(shares), addShares > 0, let addPrice = Double(cost), addPrice > 0 {
                                let totalS = existing.shares + addShares
                                let newCost = ((Double(existing.shares) * existing.averageCost) + (Double(addShares) * addPrice)) / Double(totalS)
                                HStack {
                                    Text("加碼後新總股數: \(totalS.formatted()) 股")
                                    Spacer()
                                    Text("新均價: $\(String(format: "%.2f", newCost))")
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                .font(.caption.bold())
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                
                Section(existingHolding != nil && isDCAMode ? "本次買進加碼規格" : "持股與成本") {
                    TextField("股數 (例: 1,000 股 = 1 張)", text: $shares).keyboardType(.numberPad)
                    TextField("成交單價 (元)", text: $cost).keyboardType(.decimalPad)
                    Toggle("自動寫入買賣日記流水帳", isOn: $autoAddJournal)
                }
            }
            .navigationTitle(existingHolding != nil ? "加碼存股" : "新增存股")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingHolding != nil && isDCAMode ? "確認加碼" : "儲存") {
                        let h = StockHolding(
                            symbol: symbol,
                            name: name.isEmpty ? symbol : name,
                            frequency: frequency,
                            shares: Int(shares) ?? 0,
                            averageCost: Double(cost) ?? 0,
                            currentPrice: Double(cost) ?? 0,
                            stockType: stockType
                        )
                        onSave(h, existingHolding != nil && isDCAMode)
                        dismiss()
                    }
                    .disabled(symbol.isEmpty || cost.isEmpty || (Int(shares) ?? 0) <= 0)
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
    @State private var note = ""
    
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
                    TextField("備註 (例: 定期定額加碼)", text: $note)
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
                            shares: Int(shares) ?? 0,
                            note: note
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
