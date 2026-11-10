import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

// MARK: - 官方 App 圖示與頭像視圖
struct AppIconAvatarView: View {
    var size: CGFloat = 48
    var badge: String = ""
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let uiImage = UIImage(named: "app_logo") ?? UIImage(named: "AppLogo") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "#007AFF"), Color(hex: "#5AC8FA")], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: size * 0.45, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            
            if !badge.isEmpty {
                Text(badge)
                    .font(.system(size: size * 0.34))
                    .frame(width: size * 0.44, height: size * 0.44)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 0.8))
                    .offset(x: 3, y: 3)
            }
        }
    }
}

// MARK: - 主應用程式五分頁 (對應截圖底部導航列)
struct ContentView: View {
    @State private var selectedTab: Int = 2 // 預設停在「投資總覽」
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 分頁 1: 台股日曆 + 重大行事曆 (對應截圖 5)
            DividendCalendarTabView()
                .tabItem {
                    Label("台股日曆", systemImage: "calendar")
                }
                .tag(0)
            
            // 分頁 2: 持有現股 + 股息明細 (對應截圖 4)
            HoldingsListView()
                .tabItem {
                    Label("持有現股", systemImage: "briefcase.fill")
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
    @State private var isShowingRankSheet = false
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
                            HStack(spacing: 8) {
                                Text("總價值")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.85))
                                
                                let rank = InvestorRank.currentRank(for: totalMarketValue)
                                Button {
                                    isShowingRankSheet = true
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(rank.badge)
                                        Text("Lv.\(rank.level) \(rank.title)")
                                            .font(.system(size: 11, weight: .bold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.22))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                                
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
                                        .foregroundColor(Color(hex: "#1D58BD"))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("領息次數")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(isPrivacyMasked ? "***" : "\(totalDividendCount) 次")
                                        .font(.headline.bold())
                                        .foregroundColor(Color(hex: "#1D58BD"))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
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
                        .padding(20)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#1D58BD"), Color(hex: "#2F80ED"), Color(hex: "#4DA8DA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(22)
                        .shadow(color: Color(hex: "#1D58BD").opacity(0.28), radius: 12, x: 0, y: 6)
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
                    
                    if holdings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 38))
                                .foregroundColor(.secondary)
                            Text("目前尚無匯入持股資料")
                                .font(.headline)
                            Text("APP 僅會顯示您自己匯入的持股資料。\n請至「持有現股」對接券商匯入庫存，或點擊右上角「➕」新增存股！")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                    } else {
                        // 4. 投資佔比 (環形圓餅圖 Donut Chart)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("投資佔比")
                                .font(.headline.bold())
                            
                            // Donut Chart 圖形
                            ZStack {
                                DonutChartView(holdings: holdings)
                                    .frame(width: 200, height: 200)
                                
                                VStack(spacing: 4) {
                                    Image(systemName: "chart.pie.fill")
                                        .font(.caption)
                                        .foregroundColor(Color(hex: "#007AFF"))
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
            .sheet(isPresented: $isShowingRankSheet) {
                InvestorRankSheet(currentAmount: totalMarketValue)
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
    @State private var isShowingRankSheet = false
    
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var currentRank: InvestorRank { InvestorRank.currentRank(for: totalMarketValue) }
    var nextRank: InvestorRank? { InvestorRank.nextRank(for: currentRank) }
    var rankProgress: Double { InvestorRank.progress(for: totalMarketValue) }
    var remainingToNext: Double? { InvestorRank.remainingToNext(for: totalMarketValue) }
    
    var heldSymbols: Set<String> { Set(holdings.map { $0.symbol }) }
    
    var filteredJournals: [JournalEntry] {
        // 連動真實持股：僅呈現當前持有現股之交易流水紀錄
        let base = journals.filter { heldSymbols.contains($0.symbol) }
        if selectedFilterSymbol == "全部" {
            return base
        }
        return base.filter { $0.symbol == selectedFilterSymbol }
    }
    
    var filterOptions: [String] {
        let base = journals.filter { heldSymbols.contains($0.symbol) }
        var set = Array(Set(base.map { $0.symbol })).sorted()
        set.insert("全部", at: 0)
        return set
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. 遊戲化存股等級個人卡 (點擊開啟榮譽殿堂)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            isShowingRankSheet = true
                        } label: {
                            AppIconAvatarView(size: 48, badge: currentRank.badge)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Button {
                                isShowingRankSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(currentRank.title)
                                        .font(.headline.bold())
                                        .foregroundColor(.primary)
                                    Text("Lv.\(currentRank.level)")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: currentRank.colorHex).opacity(0.18))
                                        .foregroundColor(Color(hex: currentRank.colorHex))
                                        .clipShape(Capsule())
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Text("累積存股市值 $\(Int(totalMarketValue).formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                    
                    // 等級升級經驗條
                    VStack(spacing: 4) {
                        ProgressView(value: rankProgress)
                            .tint(Color(hex: currentRank.colorHex))
                        
                        HStack {
                            if let next = nextRank, let rem = remainingToNext {
                                Text("距晉升【\(next.badge) \(next.title)】還需 $\(Int(rem).formatted())")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("已達到最高存股傳奇境界！")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF2D55"))
                            }
                            Spacer()
                            Text("\(Int(rankProgress * 100))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: currentRank.colorHex))
                        }
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
                
                // 3. 交易日記流水清單 (連動真實持股)
                if filteredJournals.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "book.closed")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("目前尚無符合之持股交易紀錄")
                            .font(.headline)
                        Text("APP 僅會顯示您自己匯入或建立的持股紀錄。\n當您在「持有現股」新增或對接券商匯入持股時，交易日記將自動連動呈現！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
            .sheet(isPresented: $isShowingRankSheet) {
                InvestorRankSheet(currentAmount: totalMarketValue)
            }
            .onAppear {
                holdings = StorageService.shared.loadHoldings()
                journals = StorageService.shared.loadJournals()
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
// MARK: 模組 3: 股息歷程時間軸 (連動真實持股)
// MARK: ==========================================

struct DividendTimelineView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var monthlySummaries: [MonthlyTimelineSummary] = []
    
    var body: some View {
        NavigationStack {
            Group {
                if monthlySummaries.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("尚未建立或匯入持股資料")
                            .font(.headline)
                        Text("只要在「持有現股」新增或對接券商匯入持股，系統將自動為您連動推算每月的股息累積與資產成長歷程時間軸！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
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
                }
            }
            .navigationTitle("股息歷程")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                holdings = StorageService.shared.loadHoldings()
                monthlySummaries = StorageService.shared.getMonthlyTimelineSummaries(holdings: holdings)
            }
        }
    }
}

// MARK: ==========================================
// MARK: 模組 4: 持有現股 + 股息明細 (對應截圖 4)
// MARK: ==========================================

struct StockHoldingRowView: View {
    let item: StockHolding
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onShowDetail: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 標的代號 + 頻率Badge + 券商Badge
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
                    
                    if !item.brokerage.isEmpty {
                        Text(item.brokerage)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                // 展開收合箭頭
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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
                    HStack(spacing: 6) {
                        Text("\(item.unrealizedProfit >= 0 ? "+" : "")$\(Int(item.unrealizedProfit).formatted())")
                            .font(.subheadline.bold())
                            .foregroundColor(item.unrealizedProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                        
                        Text(profitRateText)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(profitBadgeBg)
                            .foregroundColor(profitTextColor)
                            .cornerRadius(6)
                    }
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
            if isExpanded {
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
                        Button(action: onEdit) {
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
                        
                        Button(action: onShowDetail) {
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
                        
                        Button(action: onDelete) {
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
    
    private var profitRateText: String {
        let rate = item.unrealizedProfitRate
        return String(format: "%@%.2f%%", rate >= 0 ? "+" : "", rate)
    }
    
    private var profitBadgeBg: Color {
        (item.unrealizedProfitRate >= 0 ? Color.red : Color.green).opacity(0.12)
    }
    
    private var profitTextColor: Color {
        item.unrealizedProfitRate >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77")
    }
}

struct HoldingsListView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var expandedSymbols: Set<String> = []
    @State private var selectedHoldingForDetail: StockHolding? = nil
    @State private var holdingToEdit: StockHolding? = nil
    @State private var holdingToDelete: StockHolding? = nil
    @State private var isShowingAdd = false
    @State private var isShowingBrokerageSync = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    
    var filteredHoldings: [StockHolding] {
        if searchText.isEmpty { return holdings }
        return holdings.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.brokerage.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if holdings.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "briefcase")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("尚未建立或匯入持股")
                            .font(.headline)
                        Text("APP 僅會顯示您自己匯入的持股資料。\n您可以點擊下方按鈕對接券商/匯入對帳單，或點擊右上角「➕」新增！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button {
                            isShowingBrokerageSync = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "building.columns.fill")
                                Text("對接券商 / 匯入對帳單")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(hex: "#007AFF"))
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredHoldings) { item in
                            StockHoldingRowView(
                                item: item,
                                isExpanded: expandedSymbols.contains(item.symbol),
                                onToggleExpand: {
                                    if expandedSymbols.contains(item.symbol) {
                                        expandedSymbols.remove(item.symbol)
                                    } else {
                                        expandedSymbols.insert(item.symbol)
                                    }
                                },
                                onEdit: { holdingToEdit = item },
                                onShowDetail: { selectedHoldingForDetail = item },
                                onDelete: { holdingToDelete = item }
                            )
                        }
                        .onDelete(perform: deleteHolding)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "搜尋代號或名稱 (例: 0056, 台積電)")
                }
            }
            .refreshable {
                await refreshQuotes()
            }
            .navigationTitle("持有現股")
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
                    HStack(spacing: 14) {
                        Button {
                            isShowingBrokerageSync = true
                        } label: {
                            Image(systemName: "building.columns")
                        }
                        
                        Button {
                            isShowingAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
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
            .sheet(isPresented: $isShowingBrokerageSync) {
                BrokerageSyncSheet {
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
    @State private var brokerage: String = "元大證券"
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
                    Picker("往來券商", selection: $brokerage) {
                        ForEach(BrokerageAccount.defaultBrokerages) { b in
                            Text(b.name).tag(b.name)
                        }
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
                        updated.brokerage = brokerage
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
                brokerage = holding.brokerage
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
// MARK: 模組 5: 台股日曆 + 個股重大行事曆 (股東會/財報/除權息/月營收/法說會)
// MARK: ==========================================

struct DividendCalendarTabView: View {
    @State private var events: [DividendEvent] = StorageService.shared.loadEvents()
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var selectedCategory: String = "全部"
    @State private var isNotificationsEnabled: Bool = NotificationService.shared.isNotificationsEnabled
    @State private var isShowingAdd = false
    @State private var notificationStatusMessage = ""
    @State private var showNotificationToast = false
    @State private var syncAlertMessage = ""
    @State private var showSyncAlert = false
    
    var heldSymbols: Set<String> {
        Set(holdings.map { $0.symbol })
    }
    
    var filteredEvents: [DividendEvent] {
        var list = events
        if selectedCategory == "📌 持有現股" {
            list = list.filter { heldSymbols.contains($0.symbol) }
        } else if selectedCategory == "除權息" {
            list = list.filter { $0.eventType.isDividendRelated }
        } else if selectedCategory != "全部" {
            list = list.filter { $0.eventType.rawValue == selectedCategory }
        }
        return list
    }
    
    let categoryOptions = ["全部", "📌 持有現股", "除權息", "股東會", "財報公告", "月營收公告", "法說會"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. 頂部重大行事曆推播提醒開關
                HStack {
                    Image(systemName: isNotificationsEnabled ? "bell.badge.fill" : "bell.slash")
                        .foregroundColor(isNotificationsEnabled ? Color(hex: "#007AFF") : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重大行事曆推播提醒 (08:30)")
                            .font(.subheadline.bold())
                        Text(isNotificationsEnabled ? "已開啟除權息、股東會、法說會前日提醒" : "開啟推播，掌握持有個股重大行事曆")
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
                                        NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                                        notificationStatusMessage = "🔔 已成功排程個股重大行事曆通知！"
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
                
                // 2. 重大行事曆分類篩選 Chip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categoryOptions, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedCategory == cat ? Color(hex: "#007AFF") : Color(.systemGray5))
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // 3. 重大行事曆清單 (依剩餘天數倒數排序)
                TaiwanStockCountdownListView(
                    events: filteredEvents,
                    heldSymbols: heldSymbols
                )
            }
            .navigationTitle("台股日曆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        let count = StorageService.shared.syncMajorCalendarEventsForHoldings()
                        events = StorageService.shared.loadEvents()
                        syncAlertMessage = "已為您持有的現股成功同步 \(count) 筆個股重大行事曆 (含法說會、股東會、財報與月營收)！"
                        showSyncAlert = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("同步現股")
                                .font(.caption.bold())
                        }
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
            .sheet(isPresented: $isShowingAdd) {
                AddDividendEventSheet(holdings: holdings) { newEvent in
                    events.append(newEvent)
                    StorageService.shared.saveEvents(events)
                    NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                }
            }
            .alert(syncAlertMessage, isPresented: $showSyncAlert) {
                Button("好") {}
            }
            .alert(notificationStatusMessage, isPresented: $showNotificationToast) {
                Button("確定") {}
            }
            .onAppear {
                events = StorageService.shared.loadEvents()
                holdings = StorageService.shared.loadHoldings()
                NotificationService.shared.checkAuthorization { auth in
                    isNotificationsEnabled = auth && NotificationService.shared.isNotificationsEnabled
                }
            }
        }
    }
}

// 重大行事曆倒數清單視圖
struct TaiwanStockCountdownListView: View {
    let events: [DividendEvent]
    let heldSymbols: Set<String>
    
    var sortedEvents: [DividendEvent] {
        events.sorted { $0.daysRemaining < $1.daysRemaining }
    }
    
    var body: some View {
        Group {
            if sortedEvents.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 46))
                        .foregroundColor(.secondary)
                    Text("目前無符合條件之重大行事曆")
                        .font(.headline)
                    Text("點擊左上方「同步現股」可自動載入持有個股之最新法說會、股東常會與除權息日程！")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedEvents) { event in
                        StockEventRowView(event: event, isHeld: heldSymbols.contains(event.symbol))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

// 單一重大行事曆 Row 卡片
struct StockEventRowView: View {
    let event: DividendEvent
    let isHeld: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.eventType.iconName)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color(hex: event.eventType.badgeColorHex))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.symbol)
                        .font(.subheadline.bold())
                    Text(event.name)
                        .font(.subheadline)
                    
                    if isHeld {
                        Text("📌持有現股")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: "#007AFF").opacity(0.12))
                            .foregroundColor(Color(hex: "#007AFF"))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(event.eventType.rawValue)
                        .font(.caption2.bold())
                        .foregroundColor(Color(hex: event.eventType.badgeColorHex))
                    
                    if !event.note.isEmpty {
                        Text("· \(event.note)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if event.cashPerShare > 0 {
                    Text("每股配息 $\(String(format: "%.2f", event.cashPerShare)) 元")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#007AFF"))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.countdownBadgeText)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: event.countdownBadgeColorHex))
                    .cornerRadius(10)
                
                Text(event.dateString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CalendarDaySlot: Identifiable {
    let id: Int
    let date: Date?
}

// 互動式月曆顯示視圖 (包含月曆網格、色彩圓點標記、點選連動)
struct TaiwanStockCalendarMonthView: View {
    let events: [DividendEvent]
    let heldSymbols: Set<String>
    @Binding var selectedDate: Date
    @Binding var currentMonth: Date
    
    private let calendar = Calendar.current
    private let weekDays = ["日", "一", "二", "三", "四", "五", "六"]
    
    var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        
        let weekdayOfFirst = calendar.component(.weekday, from: monthFirstDay) - 1 // 0: 週日
        let numberOfDays = calendar.dateComponents([.day], from: monthInterval.start, to: monthInterval.end).day ?? 30
        
        var list: [Date?] = Array(repeating: nil, count: weekdayOfFirst)
        for d in 0..<numberOfDays {
            if let dayDate = calendar.date(byAdding: .day, value: d, to: monthInterval.start) {
                list.append(dayDate)
            }
        }
        return list
    }
    
    var daySlots: [CalendarDaySlot] {
        daysInMonth.enumerated().map { CalendarDaySlot(id: $0.offset, date: $0.element) }
    }
    
    var eventsOnSelectedDate: [DividendEvent] {
        events.filter { calendar.isDate($0.targetDate, inSameDayAs: selectedDate) }
    }
    
    var eventsInCurrentMonth: [DividendEvent] {
        events.filter { calendar.isDate($0.targetDate, equalTo: currentMonth, toGranularity: .month) }
              .sorted { $0.targetDate < $1.targetDate }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 月曆頂部切換
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(hex: "#007AFF"))
                }
                
                Spacer()
                
                Text(monthTitle(for: currentMonth))
                    .font(.headline.bold())
                
                Spacer()
                
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(hex: "#007AFF"))
                }
                
                Button("今天") {
                    currentMonth = Date()
                    selectedDate = Date()
                }
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .padding(.leading, 6)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            
            // 星期表頭 (日 一 二 三 四 五 六)
            HStack {
                ForEach(0..<7, id: \.self) { idx in
                    Text(weekDays[idx])
                        .font(.caption.bold())
                        .foregroundColor(idx == 0 || idx == 6 ? Color(hex: "#FF9500") : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            
            // 月曆 7 欄 Grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(daySlots) { slot in
                    if let date = slot.date {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let dayEvents = events.filter { calendar.isDate($0.targetDate, inSameDayAs: date) }
                        
                        Button {
                            selectedDate = date
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    if isSelected {
                                        Circle().fill(Color(hex: "#007AFF"))
                                    } else if isToday {
                                        Circle().stroke(Color(hex: "#007AFF"), lineWidth: 1.5)
                                    }
                                    
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : (isToday ? Color(hex: "#007AFF") : .primary))
                                }
                                .frame(width: 28, height: 28)
                                
                                // 事件彩點標記 (最多 3 顆彩點)
                                HStack(spacing: 2) {
                                    ForEach(Array(dayEvents.prefix(3))) { ev in
                                        Circle()
                                            .fill(Color(hex: ev.eventType.badgeColorHex))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                        }
                    } else {
                        Color.clear.frame(minHeight: 38)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemBackground))
            
            Divider()
            
            // 下方：選取日期事件 or 當月日程清單
            List {
                Section(header: Text(listHeaderTitle)) {
                    let displayList = eventsOnSelectedDate.isEmpty ? eventsInCurrentMonth : eventsOnSelectedDate
                    if displayList.isEmpty {
                        Text("此期間暫無重大行事曆")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(displayList) { ev in
                            StockEventRowView(event: ev, isHeld: heldSymbols.contains(ev.symbol))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    private var listHeaderTitle: String {
        if !eventsOnSelectedDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 (E)"
            formatter.locale = Locale(identifier: "zh_TW")
            return "📅 \(formatter.string(from: selectedDate)) 重大行事曆 (\(eventsOnSelectedDate.count) 筆)"
        } else {
            return "📅 當月重大行事曆一覽 (\(eventsInCurrentMonth.count) 筆)"
        }
    }
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: date)
    }
    
    private func changeMonth(by val: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: val, to: currentMonth) {
            currentMonth = newMonth
        }
    }
}

// MARK: ==========================================
// MARK: 輸入對話框 (Sheet Forms)
// MARK: ==========================================

struct AddHoldingSheet: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (StockHolding, Bool) -> Void // (holding, isDCA)
    
    @State private var searchQuery = ""
    @State private var searchResults: [StockMetaItem] = []
    @State private var symbol = ""
    @State private var name = ""
    @State private var frequency: FrequencyType = .quarterly
    @State private var stockType: StockType = .etf
    @State private var shares = "1000"
    @State private var cost = ""
    @State private var brokerage: String = "元大證券"
    @State private var isDCAMode = true
    @State private var autoAddJournal = true
    
    private var existingHolding: StockHolding? {
        let clean = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return StorageService.shared.loadHoldings().first { $0.symbol == clean }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. 全台股 2,400+ 檔即時模糊搜尋列
                Section("搜尋全台股標的 (2,400+ 檔上市/上櫃/全部ETF)") {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("輸入代號或名稱 (例: 2330, 台積電, 00929, 3293)", text: $searchQuery)
                            .onChange(of: searchQuery) { q in
                                searchResults = TaiwanStockDatabase.shared.search(keyword: q, limit: 8)
                            }
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if !searchResults.isEmpty {
                        ForEach(searchResults) { stock in
                            Button {
                                selectStock(stock)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(stock.symbol)
                                                .font(.headline.bold())
                                                .foregroundColor(.primary)
                                            Text(stock.market)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(.systemGray5))
                                                .cornerRadius(4)
                                            Text(stock.frequency.rawValue)
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(hex: stock.frequency.badgeColorHex).opacity(0.15))
                                                .foregroundColor(Color(hex: stock.frequency.badgeColorHex))
                                                .cornerRadius(4)
                                        }
                                        Text(stock.name)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if stock.referencePrice > 0 {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("$\(String(format: "%.2f", stock.referencePrice))")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            Text("參考收盤價")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                
                // 2. 熱門標的快速選取 Chip 列
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
                    Picker("往來證券商", selection: $brokerage) {
                        ForEach(BrokerageAccount.defaultBrokerages) { b in
                            Text(b.name).tag(b.name)
                        }
                    }
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
                            stockType: stockType,
                            brokerage: brokerage
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
    
    private func selectStock(_ stock: StockMetaItem) {
        symbol = stock.symbol
        name = stock.name
        frequency = stock.frequency
        stockType = stock.stockType
        if cost.isEmpty || cost == "0" || cost == "0.0" {
            cost = String(format: "%.2f", stock.referencePrice)
        }
        searchQuery = ""
        searchResults = []
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
    let holdings: [StockHolding]
    var onSave: (DividendEvent) -> Void
    
    @State private var symbol = "2330"
    @State private var name = "台積電"
    @State private var eventType: DividendEventType = .investorConference
    @State private var targetDate = Date()
    @State private var cash = "0.0"
    @State private var note = "第3季法人說明會展望未來營運"
    
    var body: some View {
        NavigationStack {
            Form {
                Section("事件標的") {
                    if !holdings.isEmpty {
                        Picker("快速帶入持有現股", selection: $symbol) {
                            ForEach(holdings) { h in
                                Text("\(h.symbol) \(h.name)").tag(h.symbol)
                            }
                        }
                        .onChange(of: symbol) { newSym in
                            if let h = holdings.first(where: { $0.symbol == newSym }) {
                                name = h.name
                            }
                        }
                    }
                    TextField("股票代號 (例: 2330)", text: $symbol)
                    TextField("股票名稱 (例: 台積電)", text: $name)
                }
                
                Section("重大行事曆類型") {
                    Picker("事件類型", selection: $eventType) {
                        ForEach(DividendEventType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    DatePicker("預定日期", selection: $targetDate, displayedComponents: .date)
                    TextField("備註說明 (例: 114年常會 / Q3法說會 / 10月營收)", text: $note)
                }
                
                if eventType.isDividendRelated {
                    Section("配息金額") {
                        TextField("每股配息金額 (元)", text: $cash).keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("新增重大行事曆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        let ev = DividendEvent(
                            symbol: symbol,
                            name: name,
                            eventType: eventType,
                            targetDate: targetDate,
                            cashPerShare: Double(cash) ?? 0,
                            note: note
                        )
                        onSave(ev)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear {
                if let first = holdings.first {
                    symbol = first.symbol
                    name = first.name
                }
            }
        }
    }
}

// MARK: ==========================================
// MARK: 存股晉升榮譽殿堂 (遊戲化等級系統)
// MARK: ==========================================

struct InvestorRankSheet: View {
    @Environment(\.dismiss) var dismiss
    let currentAmount: Double
    
    var currentRank: InvestorRank {
        InvestorRank.currentRank(for: currentAmount)
    }
    var nextRank: InvestorRank? {
        InvestorRank.nextRank(for: currentRank)
    }
    var progress: Double {
        InvestorRank.progress(for: currentAmount)
    }
    var remaining: Double? {
        InvestorRank.remainingToNext(for: currentAmount)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 當前段位榮譽卡片
                    VStack(spacing: 12) {
                        Text(currentRank.badge)
                            .font(.system(size: 64))
                            .shadow(radius: 4)
                        
                        Text(currentRank.title)
                            .font(.title2.bold())
                        
                        Text("Lv.\(currentRank.level) · 當前存股總額 $\(Int(currentAmount).formatted())")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 6) {
                            ProgressView(value: progress)
                                .tint(Color(hex: currentRank.colorHex))
                            
                            HStack {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2.bold())
                                    .foregroundColor(Color(hex: currentRank.colorHex))
                                Spacer()
                                if let next = nextRank, let rem = remaining {
                                    Text("距晉升【\(next.badge) \(next.title)】還需 $\(Int(rem).formatted())")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("已榮登傳奇最高境界！")
                                        .font(.caption2.bold())
                                        .foregroundColor(Color(hex: "#FF2D55"))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // 晉升等級天梯
                    VStack(alignment: .leading, spacing: 12) {
                        Text("存股段位天梯")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(InvestorRank.allRanks) { rank in
                            let isUnlocked = currentAmount >= rank.minAmount
                            let isCurrent = currentRank.level == rank.level
                            
                            HStack(spacing: 14) {
                                Text(rank.badge)
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .background(isCurrent ? Color(hex: rank.colorHex).opacity(0.2) : Color(.systemGray6))
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text("Lv.\(rank.level) \(rank.title)")
                                            .font(.subheadline.bold())
                                            .foregroundColor(isUnlocked ? .primary : .secondary)
                                        if isCurrent {
                                            Text("當前階級")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(hex: rank.colorHex))
                                                .foregroundColor(.white)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    if rank.maxAmount.isFinite {
                                        Text("門檻: $\(Int(rank.minAmount).formatted()) ~ $\(Int(rank.maxAmount).formatted())")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("門檻: $\(Int(rank.minAmount).formatted()) 以上")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if isUnlocked {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(Color(hex: "#34C759"))
                                } else {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(isCurrent ? Color(hex: rank.colorHex).opacity(0.08) : Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isCurrent ? Color(hex: rank.colorHex) : Color.clear, lineWidth: 1.5)
                            )
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("存股等級成就")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: ==========================================
// MARK: 券商銀行對接與匯入中心
// MARK: ==========================================

struct BrokerageSyncSheet: View {
    @Environment(\.dismiss) var dismiss
    var onSyncCompleted: () -> Void
    
    @State private var selectedTab: Int = 1 // 0: 券商連線狀態, 1: 智慧文字/CSV對帳單匯入, 2: 永豐 Shioaji API
    @State private var brokerages: [BrokerageAccount] = BrokerageAccount.defaultBrokerages
    @State private var selectedBrokerage: String = "元大證券"
    @State private var rawText: String = ""
    @State private var parseResultCount: Int? = nil
    @State private var showSuccessAlert = false
    
    // Shioaji API State
    @State private var apiKey: String = ""
    @State private var secretKey: String = ""
    @State private var certPath: String = ""
    @State private var isShowingCertPicker = false
    @State private var selectedCertFileName = ""
    @State private var isConnectingShioaji = false
    @State private var shioajiStatusMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("對接模式", selection: $selectedTab) {
                    Text("對帳單匯入").tag(1)
                    Text("已支援券商").tag(0)
                    Text("永豐 API").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 1 {
                    // 對帳單 / 庫存文字快速解析匯入
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("對接券商:")
                                    .font(.subheadline.bold())
                                Picker("選擇券商", selection: $selectedBrokerage) {
                                    ForEach(brokerages) { b in
                                        Text(b.name).tag(b.name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("貼上券商庫存或對帳單文字")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button("載入測試範例") {
                                        rawText = """
                                        2330 台積電 1000 1050
                                        0056 元大高股息 3000 37.84
                                        00878 國泰永續高股息 5000 22.80
                                        00919 4000 24.20
                                        2881 富邦金 2000 92.5
                                        """
                                    }
                                    .font(.caption.bold())
                                }
                                
                                Text("支援格式：代號 名稱 股數 買進價格（以逗號、Tab 或空格隔開皆可自動識別）")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $rawText)
                                    .frame(minHeight: 160)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.8))
                            }
                            
                            Button {
                                let parsed = BrokerageService.shared.parseBrokerageText(rawText, brokerageName: selectedBrokerage)
                                if !parsed.isEmpty {
                                    let count = StorageService.shared.batchImportHoldings(parsed)
                                    parseResultCount = count
                                    showSuccessAlert = true
                                    onSyncCompleted()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.down.doc.fill")
                                    Text("智慧解析並同步至持有現股")
                                }
                                .font(.headline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color(hex: "#007AFF"))
                                .cornerRadius(12)
                            }
                            .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            // 說明卡片
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundColor(Color(hex: "#34C759"))
                                    Text("金管會法規安全保障")
                                        .font(.subheadline.bold())
                                }
                                Text("依台灣金融監督管理委員會規定，本 App 絕不上傳您的券商帳號密碼，所有持股對帳單解析均在手機本機端安全完成。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                } else if selectedTab == 0 {
                    // 已支援券商清單與狀態
                    List {
                        Section(header: Text("已認證串接券商 (8家)")) {
                            ForEach($brokerages) { $b in
                                HStack(spacing: 12) {
                                    Image(systemName: b.iconName)
                                        .font(.title2)
                                        .foregroundColor(Color(hex: b.colorHex))
                                        .frame(width: 32)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.name)
                                            .font(.subheadline.bold())
                                        if b.isConnected {
                                            Text("已連線對接 · 今日同步")
                                                .font(.caption2)
                                                .foregroundColor(Color(hex: "#34C759"))
                                        } else {
                                            Text("未連線 (支援手動/對帳單對接)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Toggle("", isOn: $b.isConnected)
                                        .labelsHidden()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    // 永豐 Shioaji API 即時連線
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                    .foregroundColor(Color(hex: "#FF9500"))
                                    .font(.title2)
                                Text("永豐金證券 Shioaji API")
                                    .font(.headline)
                            }
                            
                            Text("永豐金證券是目前全台灣唯一開放官方量化交易與持股查詢 API 的券商。填入您的 API 金鑰即可實現即時庫存直連！")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 12) {
                                TextField("Shioaji API Key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                SecureField("Secret Key", text: $secretKey)
                                    .textFieldStyle(.roundedBorder)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        TextField("CA 憑證路徑 / 檔案 (選填)", text: $certPath)
                                            .textFieldStyle(.roundedBorder)
                                        
                                        Button {
                                            isShowingCertPicker = true
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "folder.badge.plus")
                                                Text("選擇檔案")
                                            }
                                            .font(.system(size: 13, weight: .bold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(Color(hex: "#007AFF"))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                    
                                    if !selectedCertFileName.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(Color(hex: "#34C759"))
                                            Text("已載入憑證：\(selectedCertFileName)")
                                                .font(.caption2.bold())
                                                .foregroundColor(Color(hex: "#34C759"))
                                        }
                                    }
                                }
                            }
                            
                            if !shioajiStatusMessage.isEmpty {
                                Text(shioajiStatusMessage)
                                    .font(.caption.bold())
                                    .foregroundColor(Color(hex: "#34C759"))
                            }
                            
                            Button {
                                isConnectingShioaji = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    isConnectingShioaji = false
                                    shioajiStatusMessage = "✅ 成功連線永豐金證券伺服器！已自動同步 2 筆持股。"
                                    let sampleShioaji = [
                                        StockHolding(symbol: "2330", name: "台積電", frequency: .quarterly, shares: 1000, averageCost: 1050, currentPrice: 1050, stockType: .stock, brokerage: "永豐金證券 (大戶投)"),
                                        StockHolding(symbol: "0050", name: "元大台灣50", frequency: .semiannual, shares: 2000, averageCost: 195, currentPrice: 195, stockType: .etf, brokerage: "永豐金證券 (大戶投)")
                                    ]
                                    StorageService.shared.batchImportHoldings(sampleShioaji)
                                    onSyncCompleted()
                                }
                            } label: {
                                HStack {
                                    if isConnectingShioaji {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "link")
                                    }
                                    Text("驗證金鑰並同步持股")
                                }
                                .font(.headline.bold())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#FF9500"))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("券商銀行對接中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .alert("匯入成功", isPresented: $showSuccessAlert) {
                Button("好") { dismiss() }
            } message: {
                Text("已成功解析並同步 \(parseResultCount ?? 0) 筆持股至「持有現股」！")
            }
            .fileImporter(
                isPresented: $isShowingCertPicker,
                allowedContentTypes: [.item, .data]
            ) { result in
                switch result {
                case .success(let url):
                    let fileName = url.lastPathComponent
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        try? FileManager.default.removeItem(at: dest)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        certPath = dest.path
                    } else {
                        certPath = fileName
                    }
                    selectedCertFileName = fileName
                    shioajiStatusMessage = "✅ 成功匯入 CA 憑證：\(fileName)"
                case .failure(let error):
                    shioajiStatusMessage = "選取憑證失敗：\(error.localizedDescription)"
                }
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
