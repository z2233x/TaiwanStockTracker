import SwiftUI
import SceneKit
import UserNotifications
import UniformTypeIdentifiers
import PhotosUI
import Vision

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
    @State private var selectedTab: Int = 1 // 預設停在「持有現股」
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 分頁 1: 台股日曆 + 重大行事曆 (對應截圖 5)
            DividendCalendarTabView()
                .tabItem {
                    Label("台股日曆", systemImage: "calendar")
                }
                .tag(0)
            
            // 分頁 2: 持有現股 (清爽專注管理)
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
            
            // 分頁 4: 股息歷程時間軸 (對應截圖 3)
            DividendTimelineView()
                .tabItem {
                    Label("股息歷程", systemImage: "clock.arrow.circlepath")
                }
                .tag(3)
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
    @State private var isShowingPetSheet = false
    @State private var petState: DividendPetState = PetService.shared.loadState()
    @State private var isRefreshing = false
    @State private var refreshMessage = ""
    @State private var lastRefreshedTime = ""
    
    // 存股被動收入目標計算機 State (支援手動輸入與持久化儲存)
    @State private var targetMonthlyIncome: Double = StorageService.shared.loadTargetMonthlyIncome()
    @State private var targetMonthlyIncomeInput: String = "\(Int(StorageService.shared.loadTargetMonthlyIncome()))"
    @State private var monthlyDCAAmount: Double = 20000     // 每月定期定額 2 萬元
    
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var totalCost: Double { holdings.reduce(0) { $0 + $1.totalCostWithFee } }
    var priceGainProfit: Double { holdings.reduce(0) { $0 + $1.unrealizedProfit } }
    var totalDividends: Double { holdings.reduce(0) { $0 + $1.totalDividendsReceived } }
    var totalDividendCount: Int { holdings.reduce(0) { $0 + $1.dividendCount } }
    var frequencyDict: [FrequencyType: Int] { StorageService.shared.getFrequencyDistribution(holdings: holdings) }
    
    // 智慧持股股息來源與掩護性買權分析 (逐檔對應推算)
    var dividendSourceSummary: PortfolioDividendSourceSummary {
        DividendSourceService.shared.analyzePortfolio(holdings: holdings)
    }
    
    // 當前推算年化股息與月均股息 (按持有現股逐檔智慧推算加總，不再單純乘以 7.5%)
    var currentMonthlyDividend: Double {
        dividendSourceSummary.totalMonthlyDividend
    }
    var estimatedAnnualDividend: Double {
        dividendSourceSummary.totalAnnualDividend
    }
    var effectivePortfolioYield: Double {
        totalMarketValue > 0 ? (estimatedAnnualDividend / totalMarketValue) : 0.075
    }
    var goalProgress: Double {
        targetMonthlyIncome > 0 ? min(1.0, currentMonthlyDividend / targetMonthlyIncome) : 0
    }
    var neededPrincipal: Double {
        effectivePortfolioYield > 0 ? (targetMonthlyIncome * 12.0) / effectivePortfolioYield : 0
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
                                    HStack(spacing: 4) {
                                        Text(rank.badge)
                                        Text("Lv.\(rank.level) \(rank.title)")
                                            .font(.system(size: 13, weight: .bold))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
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
                    
                    // 1.5 財富寵物伴侶卡 (招財貓 / 貪錢鳥 / 財氣犬)
                    PetCompanionBannerCard(
                        petState: petState,
                        isDownMarket: priceGainProfit < 0 && !holdings.isEmpty,
                        auras: PetService.shared.auras(for: holdings, summary: dividendSourceSummary),
                        onTapCard: { isShowingPetSheet = true },
                        onTapFeed: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                let res = PetService.shared.feedAllPending()
                                petState = res.state
                            }
                        }
                    )
                    
                    // 2. 存股被動收入目標計算機 (支援手動輸入與快選)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("存股被動收入目標", systemImage: "target")
                                .font(.headline.bold())
                            Spacer()
                            Text("達成率 \(String(format: "%.1f", goalProgress * 100))%")
                                .font(.subheadline.bold())
                                .foregroundColor(Color(hex: "#007AFF"))
                        }
                        
                        // 手動輸入框 (直接鍵入自訂月領金額)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自訂目標月領金額 (點擊直接手動輸入)：")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.headline.bold())
                                    .foregroundColor(Color(hex: "#007AFF"))
                                
                                TextField("例: 30000", text: $targetMonthlyIncomeInput)
                                    .keyboardType(.numberPad)
                                    .font(.headline.bold())
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(hex: "#007AFF").opacity(0.4), lineWidth: 1)
                                    )
                                    .onChange(of: targetMonthlyIncomeInput) { newVal in
                                        let filtered = newVal.filter { "0123456789".contains($0) }
                                        if let val = Double(filtered), val > 0 {
                                            targetMonthlyIncome = val
                                            StorageService.shared.saveTargetMonthlyIncome(val)
                                        }
                                    }
                                
                                Text("元 / 月")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                            }
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
                            GoalChipButton(title: "月領1萬", target: 10000, current: $targetMonthlyIncome) {
                                targetMonthlyIncomeInput = "10000"
                                StorageService.shared.saveTargetMonthlyIncome(10000)
                            }
                            GoalChipButton(title: "月領3萬", target: 30000, current: $targetMonthlyIncome) {
                                targetMonthlyIncomeInput = "30000"
                                StorageService.shared.saveTargetMonthlyIncome(30000)
                            }
                            GoalChipButton(title: "月領5萬", target: 50000, current: $targetMonthlyIncome) {
                                targetMonthlyIncomeInput = "50000"
                                StorageService.shared.saveTargetMonthlyIncome(50000)
                            }
                            GoalChipButton(title: "月領10萬", target: 100000, current: $targetMonthlyIncome) {
                                targetMonthlyIncomeInput = "100000"
                                StorageService.shared.saveTargetMonthlyIncome(100000)
                            }
                        }
                        
                        Divider()

                        
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
                    
                    // 2.5 股息來源結構與掩護性買權 (Covered Call) 分析模組
                    DividendSourceBreakdownCard(summary: dividendSourceSummary)
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
                    petState = PetService.shared.syncDividendPoints(
                        holdings: holdings,
                        histories: StorageService.shared.loadHoldingHistories()
                    )
                }
            }
            .sheet(isPresented: $isShowingRankSheet) {
                InvestorRankSheet(currentAmount: totalMarketValue)
            }
            .sheet(isPresented: $isShowingPetSheet) {
                PetCompanionSheet(
                    petState: $petState,
                    holdings: holdings,
                    summary: dividendSourceSummary,
                    isDownMarket: priceGainProfit < 0 && !holdings.isEmpty
                )
            }
            .onAppear {
                holdings = StorageService.shared.loadHoldings()
                petState = PetService.shared.syncDividendPoints(
                    holdings: holdings,
                    histories: StorageService.shared.loadHoldingHistories()
                )
                if let ts = StorageService.shared.lastQuoteUpdatedAt {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm:ss"
                    lastRefreshedTime = f.string(from: ts)
                }
            }
            .task {
                let last = StorageService.shared.lastQuoteUpdatedAt
                if !holdings.isEmpty && (last == nil || Date().timeIntervalSince(last!) > 30) {
                    await refreshQuotes()
                }
            }
        }
    }
    
    private func refreshQuotes() async {
        isRefreshing = true
        _ = await StorageService.shared.refreshAllStockQuotes()
        holdings = StorageService.shared.loadHoldings()
        petState = PetService.shared.syncDividendPoints(
            holdings: holdings,
            histories: StorageService.shared.loadHoldingHistories()
        )
        
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

// MARK: - 股息來源結構與掩護性買權 (Covered Call) 分析卡片
struct DividendSourceBreakdownCard: View {
    let summary: PortfolioDividendSourceSummary
    @State private var isShowingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 卡片表頭
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(Color(hex: "#AF52DE"))
                    Text("股息來源結構與節稅分析")
                        .font(.headline.bold())
                }
                Spacer()
                if summary.hasCoveredCallHoldings {
                    Text("含Covered Call")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "#AF52DE").opacity(0.15))
                        .foregroundColor(Color(hex: "#AF52DE"))
                        .cornerRadius(6)
                }
            }
            
            // 股息總覽金額（區分本月可領 vs 除息後新加碼待下月公布）
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.totalPendingShares > 0 ? "本月實際可領推算 (依買入日期篩選)" : "持股逐檔推算月被動現金流")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("$\(Int(summary.totalMonthlyDividend).formatted())")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(hex: "#007AFF"))
                        Text("/ 本月")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary.totalPendingShares > 0 ? "滿倉預估月息" : "推算年領股息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(summary.totalPendingShares > 0
                         ? "$\(Int(summary.totalFullPositionMonthlyDividend).formatted()) /月"
                         : "$\(Int(summary.totalAnnualDividend).formatted())")
                        .font(.subheadline.bold())
                }
            }

            if summary.totalPendingShares > 0 {
                let cal = Calendar.current
                let today = Date()
                let isMidMonth = cal.component(.day, from: today) >= 15
                let nextM = (cal.component(.month, from: today) % 12) + 1
                HStack(spacing: 6) {
                    Text(isMidMonth ? "📢" : "⏳")
                    Text(isMidMonth
                         ? "\(nextM) 月配息已公布：除息後新買／加碼 \(summary.totalPendingShares.formatted()) 股（+$\(Int(summary.totalPendingMonthlyDividend).formatted())/月）將於 \(nextM) 月除息領取。"
                         : "本月除息後新買／加碼 \(summary.totalPendingShares.formatted()) 股（+$\(Int(summary.totalPendingMonthlyDividend).formatted())/月），待本月中旬公布 \(nextM) 月配息後領取。")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: isMidMonth ? "#1D4ED8" : "#9A3412"))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isMidMonth ? Color.blue : Color.orange).opacity(0.11))
                .cornerRadius(8)
            }
            
            // 四色股息來源比例長條圖
            if summary.totalMonthlyDividend > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            if summary.total76Percent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "#AF52DE"))
                                    .frame(width: max(4, geo.size.width * CGFloat(summary.total76Percent / 100.0)))
                            }
                            if summary.total54CPercent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "#007AFF"))
                                    .frame(width: max(4, geo.size.width * CGFloat(summary.total54CPercent / 100.0)))
                            }
                            if summary.totalReservePercent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "#FF9500"))
                                    .frame(width: max(4, geo.size.width * CGFloat(summary.totalReservePercent / 100.0)))
                            }
                            if summary.totalSurplusPercent > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: "#34C759"))
                                    .frame(width: max(4, geo.size.width * CGFloat(summary.totalSurplusPercent / 100.0)))
                            }
                        }
                    }
                    .frame(height: 10)
                    
                    // 四大來源圖例與佔比
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        SourceLegendItem(
                            colorHex: "#AF52DE",
                            title: "76 選擇權權利金/財產交易",
                            amount: summary.total76Amount,
                            percentage: summary.total76Percent,
                            note: "免綜所稅・免二代健保"
                        )
                        SourceLegendItem(
                            colorHex: "#007AFF",
                            title: "54C 股利所得 (現股股息)",
                            amount: summary.total54CAmount,
                            percentage: summary.total54CPercent,
                            note: "計入綜所稅・單筆滿2萬扣2.11%"
                        )
                        SourceLegendItem(
                            colorHex: "#FF9500",
                            title: "收益平準金 (本金返還)",
                            amount: summary.totalReserveAmount,
                            percentage: summary.totalReservePercent,
                            note: "免納所得稅・免二代健保"
                        )
                        SourceLegendItem(
                            colorHex: "#34C759",
                            title: "資本公積",
                            amount: summary.totalSurplusAmount,
                            percentage: summary.totalSurplusPercent,
                            note: "免稅所得・免二代健保"
                        )
                    }
                }
            } else {
                Text("尚無持股資料，匯入或新增現股後將自動精算股息來源結構")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider().padding(.vertical, 2)
            
            // 💡 節稅效益與健保免扣重點說明
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.green)
                    Text("實質領息與節稅優勢")
                        .font(.caption.bold())
                    Spacer()
                    Text("免稅免健保佔 \(String(format: "%.1f", summary.taxExemptPercent))%")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                
                Text("• 掩護性買權策略 (如 00406) 之收益主要來自「賣出選擇權權利金」，屬國內財產交易所得，停徵所得稅且完全免扣 2.11% 二代健保補充保費！\n• 預估整體組合每年可為您免除約 $\(Int(summary.estimatedAnnualNhiSaved).formatted()) 之二代健保潛在負擔。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            .padding(10)
            .background(Color.green.opacity(0.08))
            .cornerRadius(10)
            
            // 點開查看各檔持股股息來源明細
            if !summary.holdingsCalculations.isEmpty {
                Button {
                    isShowingDetails.toggle()
                } label: {
                    HStack {
                        Text(isShowingDetails ? "收合各檔持股股息拆解" : "查看各檔持股股息來源對應 (\(summary.holdingsCalculations.count) 檔)")
                            .font(.caption.bold())
                        Spacer()
                        Image(systemName: isShowingDetails ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(Color(hex: "#007AFF"))
                }
                
                if isShowingDetails {
                    VStack(spacing: 8) {
                        ForEach(summary.holdingsCalculations) { c in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(c.holding.symbol)
                                            .font(.caption.bold())
                                        Text(c.holding.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(c.profile.strategy.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color(hex: c.profile.strategy.badgeColorHex).opacity(0.12))
                                            .foregroundColor(Color(hex: c.profile.strategy.badgeColorHex))
                                            .cornerRadius(4)
                                    }
                                    Text(c.profile.notes)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("本月 $\(Int(c.monthlyDividend).formatted())")
                                        .font(.caption.bold())
                                        .foregroundColor(Color(hex: "#007AFF"))
                                    if c.pendingNextMonthShares > 0 {
                                        let isMid = Calendar.current.component(.day, from: Date()) >= 15
                                        let nextM = (Calendar.current.component(.month, from: Date()) % 12) + 1
                                        Text(isMid ? "📢 \(c.pendingNextMonthShares.formatted()) 股領 \(nextM) 月息(已公布)" : "⏳ \(c.pendingNextMonthShares.formatted()) 股待中旬公布")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(hex: isMid ? "#1D4ED8" : "#EA580C"))
                                    } else {
                                        Text("免稅比例 \(String(format: "%.0f", c.taxExemptPercentage))%")
                                            .font(.system(size: 10))
                                            .foregroundColor(c.taxExemptPercentage >= 60 ? .green : .secondary)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// 股息來源圖例小卡片
struct SourceLegendItem: View {
    let colorHex: String
    let title: String
    let amount: Double
    let percentage: Double
    let note: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                HStack(spacing: 4) {
                    Text("$\(Int(amount).formatted()) /月")
                        .font(.system(size: 12, weight: .heavy))
                    Text("(\(String(format: "%.1f", percentage))%)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Text(note)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct GoalChipButton: View {
    let title: String
    let target: Double
    @Binding var current: Double
    var onSelect: (() -> Void)? = nil
    
    var isSelected: Bool { Int(current) == Int(target) }
    
    var body: some View {
        Button {
            current = target
            onSelect?()
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
// MARK: 模組 3: 股息歷程時間軸 (連動真實持股、買入後起算配息、滑動刪除與配息加總)
// MARK: ==========================================

struct DividendTimelineView: View {
    @State private var holdings: [StockHolding] = StorageService.shared.loadHoldings()
    @State private var monthlySummaries: [MonthlyTimelineSummary] = []
    @State private var nextForecast: NextMonthDividendForecast? = nil
    
    var totalDividendsSum: Double {
        monthlySummaries.reduce(0.0) { $0 + $1.monthDividend }
    }
    
    var averageMonthlyDividend: Double {
        let activeMonths = monthlySummaries.filter { $0.monthDividend > 0 }
        return activeMonths.isEmpty ? 0 : (totalDividendsSum / Double(activeMonths.count))
    }
    
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
                        Text("只要在「持有現股」新增或對接券商匯入持股，系統將自動依據持股買入月份起算配息與資產歷程！")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    List {
                        // 1. 頂部配息加總統計卡片
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("歷程累計配息總額")
                                            .font(.caption.bold())
                                            .foregroundColor(.white.opacity(0.85))
                                        Text("$\(Int(totalDividendsSum).formatted())")
                                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("平均月配息")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.85))
                                        Text("$\(Int(averageMonthlyDividend).formatted()) /月")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                    }
                                }
                                
                                Divider()

                                
                                HStack {
                                    Label("\(monthlySummaries.count) 個月份紀錄", systemImage: "calendar.badge.clock")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white.opacity(0.9))
                                    Spacer()
                                    Text("💡 依各標的買入月份起算配息・左滑可刪除")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#007AFF"), Color(hex: "#5856D6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        // 1.5 下期配息公告／預估（如 10 月中旬後預估 11 月，或 11 月中旬後含新加碼預估 12 月）
                        if let forecast = nextForecast, forecast.estimatedDividend > 0 {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("下期預估：\(forecast.monthKey)", systemImage: "megaphone.fill")
                                            .font(.subheadline.bold())
                                            .foregroundColor(Color(hex: "#C2410C"))
                                        Spacer()
                                        Text(forecast.isMidMonthAnnounced ? "✓ 已過中旬公告期" : "⏳ 待本月中旬公告")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(forecast.isMidMonthAnnounced ? Color.green.opacity(0.15) : Color.orange.opacity(0.16))
                                            .foregroundColor(forecast.isMidMonthAnnounced ? Color(hex: "#15803D") : Color(hex: "#C2410C"))
                                            .cornerRadius(6)
                                    }

                                    HStack(alignment: .firstTextBaseline) {
                                        Text("下月預期領取")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("$\(Int(forecast.estimatedDividend).formatted())")
                                            .font(.title3.bold())
                                            .foregroundColor(Color(hex: "#EA580C"))
                                    }

                                    Text("參與下月除息股數共 \(forecast.totalEligibleShares.formatted()) 股\(forecast.pendingAddedShares > 0 ? "（含本月新買／加碼 \(forecast.pendingAddedShares.formatted()) 股）" : "")，待實際除息後入帳。")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(14)
                                .background(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                                )
                                .cornerRadius(14)
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        
                        // 2. 時間軸月份卡片清單 (支援向左滑動刪除)
                        Section {
                            ForEach(Array(monthlySummaries.enumerated()), id: \.element.id) { index, item in
                                HStack(alignment: .top, spacing: 12) {
                                    // 左側垂直時間軸節點與線條
                                    VStack(spacing: 0) {
                                        Circle()
                                            .fill(Color(hex: "#007AFF"))
                                            .frame(width: 12, height: 12)
                                            .padding(.top, 4)
                                        
                                        if index < monthlySummaries.count - 1 {
                                            Rectangle()
                                                .fill(Color(hex: "#007AFF").opacity(0.25))
                                                .frame(width: 2)
                                                .frame(maxHeight: .infinity)
                                        }
                                    }
                                    
                                    // 右側月份數據卡片
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(item.monthKey)
                                                .font(.headline.bold())
                                            Spacer()
                                            if item.cumulativeDividend > 0 {
                                                Text("累計 $\(Int(item.cumulativeDividend).formatted())")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.12))
                                                    .foregroundColor(.green)
                                                    .cornerRadius(6)
                                            }
                                        }
                                        
                                        // 當月配息重點展示
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("當月配息")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("$\(Int(item.monthDividend).formatted())")
                                                .font(.title2.bold())
                                                .foregroundColor(Color(hex: "#007AFF"))
                                        }
                                        .padding(.vertical, 2)
                                        
                                        // 買入後生效計息之持股標籤
                                        if !item.activeSymbols.isEmpty {
                                            HStack(spacing: 4) {
                                                Text("計息標的:")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.secondary)
                                                Text(item.activeSymbols.joined(separator: ", "))
                                                    .font(.caption2.bold())
                                                    .foregroundColor(Color(hex: "#5856D6"))
                                                Text("(\(item.activeSymbols.count)檔)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        if item.pendingSharesCount > 0 {
                                            Text("⏳ \(item.pendingSymbols.joined(separator: ", ")) 除息後買進 \(item.pendingSharesCount.formatted()) 股，須待下月配息公布才領取（預估 +$\(Int(item.pendingNextDividend).formatted())）")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(Color(hex: "#9A3412"))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.12))
                                                .cornerRadius(6)
                                        }
                                        
                                        Divider()

                                        
                                        // 資產指標網格
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("總價值").font(.caption2).foregroundColor(.secondary)
                                                Text("$\(Int(item.totalMarketValue).formatted())").font(.caption.bold())
                                            }
                                            Spacer()
                                            VStack(alignment: .center, spacing: 2) {
                                                Text("總成本").font(.caption2).foregroundColor(.secondary)
                                                Text("$\(Int(item.totalCost).formatted())").font(.caption.bold())
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("價差獲利").font(.caption2).foregroundColor(.secondary)
                                                Text("\(item.priceGainProfit >= 0 ? "+" : "")$\(Int(item.priceGainProfit).formatted())")
                                                    .font(.caption.bold())
                                                    .foregroundColor(item.priceGainProfit >= 0 ? Color(hex: "#FF6961") : Color(hex: "#77DD77"))
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(14)
                                    .padding(.bottom, 8)
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteMonthSummary(item.monthKey)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("股息歷程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        StorageService.shared.resetDeletedTimelineMonths()
                        monthlySummaries = StorageService.shared.getMonthlyTimelineSummaries(holdings: holdings)
                        nextForecast = StorageService.shared.getNextMonthDividendForecast(holdings: holdings)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                }
            }
            .onAppear {
                StorageService.shared.syncAnnouncedDividends()
                holdings = StorageService.shared.loadHoldings()
                monthlySummaries = StorageService.shared.getMonthlyTimelineSummaries(holdings: holdings)
                nextForecast = StorageService.shared.getNextMonthDividendForecast(holdings: holdings)
            }
        }
    }
    
    private func deleteMonthSummary(_ monthKey: String) {
        StorageService.shared.saveDeletedTimelineMonthKey(monthKey)
        withAnimation {
            monthlySummaries.removeAll { $0.monthKey == monthKey }
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
        let isZeroDivStock = StockQuoteService.shared.isZeroDividendStock(symbol: item.symbol, name: item.name)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 標的代號 + 頻率Badge + 券商Badge (清爽不擁擠、字體放大易讀)
                HStack(spacing: 8) {
                    Text(item.symbol)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                    
                    Text(isZeroDivStock ? "今年無配息" : item.frequency.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((isZeroDivStock ? Color.secondary : Color(hex: item.frequency.badgeColorHex)).opacity(0.15))
                        .foregroundColor(isZeroDivStock ? .secondary : Color(hex: item.frequency.badgeColorHex))
                        .cornerRadius(6)
                    
                    if !item.brokerage.isEmpty {
                        Text(item.brokerage)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray5))
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                // 展開收合箭頭
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            
            Text(item.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("總成本")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Text("$\(Int(item.totalCostWithFee).formatted())")
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("總股數")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Text("\(item.shares.formatted()) 股")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("總損益")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("\(item.unrealizedProfit >= 0 ? "+" : "")$\(Int(item.unrealizedProfit).formatted())")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(item.unrealizedProfit >= 0 ? Color(hex: "#FF3B30") : Color(hex: "#34C759"))
                        
                        Text(profitRateText)
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(profitBadgeBg)
                            .foregroundColor(profitTextColor)
                            .cornerRadius(6)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("已領息")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                    Text(isZeroDivStock ? "無配息" : "領息 \(item.dividendCount) 次")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            
            // 展開內容：現值、均價、現價、多功能操作區
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()

                    HStack {
                        Text("現值: $\(Int(item.marketValue).formatted())")
                        Spacer()
                        Text("均價: $\(String(format: "%.2f", item.averageCost))")
                        Spacer()
                        let diff = item.currentPrice - item.previousClose
                        let diffPct = item.todayChangePercentage
                        HStack(spacing: 3) {
                            Text("現價: $\(String(format: "%.2f", item.currentPrice))")
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            if item.previousClose > 0 && abs(diff) >= 0.005 {
                                Text(String(format: "(%@%.2f%%)", diff >= 0 ? "▲" : "▼", abs(diffPct)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(diff >= 0 ? Color(hex: "#FF3B30") : Color(hex: "#34C759"))
                            }
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    
                    let allEvents = StorageService.shared.loadEvents()
                    let calc = DividendSourceService.shared.calculateHoldingDividend(holding: item, events: allEvents)
                    let isNoDividendThisYear = isZeroDivStock || (calc.annualDividend <= 0 && calc.monthlyDividend <= 0 && calc.upcomingExDividendAmountInMonth <= 0)
                    let cal = Calendar.current
                    let todayNow = Date()
                    let curY = cal.component(.year, from: todayNow)
                    let curM = cal.component(.month, from: todayNow)
                    let isMidMonthAnnounced = cal.component(.day, from: todayNow) >= 15
                    let nextM = (curM % 12) + 1
                    let cutoffNow = StockHolding.exDividendCutoffDate(for: item.symbol, year: curY, month: curM, events: allEvents)

                    if !item.lots.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("買入與加碼批次 (\(item.lots.count) 筆)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            ForEach(item.lots) { lot in
                                let isElig = cal.startOfDay(for: lot.buyDate) < cutoffNow
                                let badgeText = isNoDividendThisYear
                                    ? "⚪ 今年無配息"
                                    : (isElig ? "✓ 本月計息" : (isMidMonthAnnounced ? "📢 領 \(nextM) 月息" : "⏳ 待 \(nextM) 月公布"))
                                let badgeBg = isNoDividendThisYear
                                    ? Color(.systemGray5)
                                    : (isElig ? Color.green.opacity(0.14) : (isMidMonthAnnounced ? Color.blue.opacity(0.14) : Color.orange.opacity(0.14)))
                                let badgeFg = isNoDividendThisYear
                                    ? Color.secondary
                                    : (isElig ? Color(hex: "#15803D") : (isMidMonthAnnounced ? Color(hex: "#1D4ED8") : Color(hex: "#C2410C")))
                                HStack(spacing: 6) {
                                    Text(lot.shortDateString)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Text(lot.lotsText)
                                        .font(.system(size: 13, weight: .bold))
                                    Text("@ $\(String(format: "%.2f", lot.price))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(badgeText)
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(badgeBg)
                                        .foregroundColor(badgeFg)
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    if isNoDividendThisYear {
                        HStack {
                            Text("⚪ \(item.name) 今年無發放現金股息 ($0)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            if let exStr = calc.announcedExDateString, let cash = calc.announcedCashPerShare {
                                Text(calc.isExDividendReachedInMonth
                                     ? "📢 本月除權息日 \(exStr) · 每股配 $\(String(format: "%.3f", cash)) · ✓ 已除息增加 \(curM) 月股息 (+$\(Int(calc.monthlyDividend).formatted()))"
                                     : "📅 本月預定除權息日 \(exStr) · 每股配 $\(String(format: "%.3f", cash)) · 到期將增加 \(curM) 月股息 (+$\(Int(calc.upcomingExDividendAmountInMonth).formatted()))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(hex: calc.isExDividendReachedInMonth ? "#15803D" : "#1D4ED8"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background((calc.isExDividendReachedInMonth ? Color.green : Color.blue).opacity(0.12))
                                    .cornerRadius(8)
                            }

                            HStack {
                                if let dps = calc.announcedCashPerShare ?? calc.profile.defaultCashDividendPerShare {
                                    Text("💡 本月可領: $\(Int(calc.monthlyDividend).formatted()) (\(calc.eligibleSharesNow.formatted())股 × $\(String(format: "%.3f", dps)))")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#007AFF"))
                                } else {
                                    Text("💡 本月可領: $\(Int(calc.monthlyDividend).formatted()) (年殖利率 \(String(format: "%.1f", calc.effectiveAnnualYield * 100))%)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color(hex: "#007AFF"))
                                }
                                Spacer()
                                if calc.taxExemptPercentage > 0 {
                                    Text("免稅 \(String(format: "%.0f", calc.taxExemptPercentage))%")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            }

                            if calc.pendingNextMonthShares > 0 {
                                Text(isMidMonthAnnounced
                                     ? "📢 \(nextM) 月配息已公布：此筆 \(calc.pendingNextMonthShares.formatted()) 股將於 \(nextM) 月除息領取（下月合計 $\(Int(calc.fullMonthlyDividend).formatted())）"
                                     : "⏳ 除息後加碼 \(calc.pendingNextMonthShares.formatted()) 股待月中旬公布 \(nextM) 月配息領取（下期滿倉 $\(Int(calc.fullMonthlyDividend).formatted())）")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: isMidMonthAnnounced ? "#1D4ED8" : "#C2410C"))
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    // 操作按鈕組（在 List row 內必須使用 .buttonStyle(.borderless)，避免點擊整列觸發所有按鈕）
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
                        .buttonStyle(.borderless)
                        
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
                        .buttonStyle(.borderless)
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.borderless)
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
    
    // 現有持股狀態
    @State private var expandedSymbols: Set<String> = []
    @State private var selectedHoldingForDetail: StockHolding? = nil
    @State private var holdingToEdit: StockHolding? = nil
    @State private var holdingToDelete: StockHolding? = nil
    @State private var isShowingAdd = false
    @State private var isShowingBrokerageSync = false
    @State private var isShowingPhotoOCR = false
    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var lastQuoteTimeText = ""
    @State private var isShowingBackup = false
    @State private var isShowingRankSheet = false
    
    // 存股成就與市值統計
    var totalMarketValue: Double { holdings.reduce(0) { $0 + $1.marketValue } }
    var currentRank: InvestorRank { InvestorRank.currentRank(for: totalMarketValue) }
    var nextRank: InvestorRank? { InvestorRank.nextRank(for: currentRank) }
    var rankProgress: Double { InvestorRank.progress(for: totalMarketValue) }
    var remainingToNext: Double? { InvestorRank.remainingToNext(for: totalMarketValue) }
    
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
            VStack(spacing: 0) {
                // 1. 頂部遊戲化存股等級個人卡 (成就門戶)
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            isShowingRankSheet = true
                        } label: {
                            AppIconAvatarView(size: 44, badge: currentRank.badge)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                        }
                    }
                    
                    // 等級升級進度條
                    VStack(spacing: 3) {
                        ProgressView(value: rankProgress)
                            .tint(Color(hex: currentRank.colorHex))
                        
                        HStack {
                            if let next = nextRank, let rem = remainingToNext {
                                Text("距晉升【\(next.badge) \(next.title)】還需 $\(Int(rem).formatted())")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("已達到最高存股傳奇境界！")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#FF2D55"))
                            }
                            Spacer()
                            Text("\(Int(rankProgress * 100))%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: currentRank.colorHex))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                
                Divider()

                // 1.5 即時報價狀態列（隨時掌握最新現價並支援一鍵重整）
                if !holdings.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: isRefreshing ? "antenna.radiowaves.left.and.right" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(isRefreshing ? Color(hex: "#007AFF") : Color(hex: "#34C759"))
                        Text(isRefreshing
                             ? "正在連線證交所/Yahoo 同步最新現價..."
                             : (lastQuoteTimeText.isEmpty ? "點擊更新即時現價 (證交所 MIS / Yahoo)" : "即時現價已更新 \(lastQuoteTimeText)"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            Task { await refreshQuotes() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                Text("更新股價")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: "#007AFF"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: "#007AFF").opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .disabled(isRefreshing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(.systemBackground))
                    Divider()
                }
                
                // 2. 現有持股主要清單
                    if holdings.isEmpty {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "briefcase")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("尚未建立或匯入持股")
                                .font(.headline)
                            Text("APP 僅會顯示您自己匯入的持股資料。\n您可以拍照或截圖自動辨識，也可以對接券商/對帳單，或點擊右上角「➕」手動新增！")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            HStack(spacing: 12) {
                                Button {
                                    isShowingPhotoOCR = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "camera.fill")
                                        Text("拍照 / 截圖自動辨識")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: "#FF9500"))
                                    .cornerRadius(12)
                                }
                                
                                Button {
                                    isShowingBrokerageSync = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "building.columns.fill")
                                        Text("對接券商 / 對帳單")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: "#007AFF"))
                                    .cornerRadius(12)
                                }
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
                                    onEdit: {
                                        selectedHoldingForDetail = nil
                                        holdingToEdit = item
                                    },
                                    onShowDetail: {
                                        holdingToEdit = nil
                                        selectedHoldingForDetail = item
                                    },
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
            .navigationBarTitleDisplayMode(.inline)
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
                            isShowingPhotoOCR = true
                        } label: {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        
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
                        reloadAllData()
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
                    reloadAllData()
                    Task { await refreshQuotes() }
                } onDelete: {
                    StorageService.shared.deleteHolding(id: h.id)
                    reloadAllData()
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                AddHoldingSheet { newHolding, isDCA in
                    StorageService.shared.addOrUpdateHolding(newHolding, isDCA: isDCA, autoAddJournal: true)
                    reloadAllData()
                    Task { await refreshQuotes() }
                }
            }
            .sheet(isPresented: $isShowingBrokerageSync) {
                BrokerageSyncSheet {
                    reloadAllData()
                    Task { await refreshQuotes() }
                }
            }
            .sheet(isPresented: $isShowingPhotoOCR) {
                PhotoOCRScannerSheet { _ in
                    reloadAllData()
                    Task { await refreshQuotes() }
                }
            }
            .sheet(isPresented: $isShowingBackup) {
                DataBackupSheet {
                    reloadAllData()
                }
            }
            .sheet(isPresented: $isShowingRankSheet) {
                InvestorRankSheet(currentAmount: totalMarketValue)
            }
            .onAppear {
                reloadAllData()
                if let ts = StorageService.shared.lastQuoteUpdatedAt {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm:ss"
                    lastQuoteTimeText = f.string(from: ts)
                }
            }
            .task {
                let last = StorageService.shared.lastQuoteUpdatedAt
                if !holdings.isEmpty && (last == nil || Date().timeIntervalSince(last!) > 30) {
                    await refreshQuotes()
                }
            }
        }
    }
    
    private func reloadAllData() {
        StorageService.shared.syncAnnouncedDividends()
        holdings = StorageService.shared.loadHoldings()
    }
    
    private func deleteHolding(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        StorageService.shared.saveHoldings(holdings)
        reloadAllData()
    }
    
    private func refreshQuotes() async {
        isRefreshing = true
        _ = await StorageService.shared.refreshAllStockQuotes()
        reloadAllData()
        if let ts = StorageService.shared.lastQuoteUpdatedAt {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            lastQuoteTimeText = f.string(from: ts)
        }
        isRefreshing = false
    }
}

// 編輯持股 Sheet（支援編輯初始買入日期與多筆加碼日期明細）
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
    @State private var editableLots: [HoldingLot] = []
    @State private var newLotDate: Date = Date()
    @State private var newLotShares: String = "10000"
    @State private var newLotPrice: String = ""
    @State private var showAddLotBox: Bool = false
    @State private var showDeleteConfirm = false

    private func recalculateFromLots() {
        let valid = editableLots.filter { $0.shares > 0 }
        let total = valid.reduce(0) { $0 + $1.shares }
        let cost = valid.reduce(0.0) { $0 + Double($1.shares) * $1.price }
        shares = "\(total)"
        if total > 0 {
            averageCost = String(format: "%.2f", cost / Double(total))
        }
    }
    
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

                Section {
                    ForEach($editableLots) { $lot in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(lot.note)
                                    .font(.caption.bold())
                                    .foregroundColor(Color(hex: "#007AFF"))
                                Spacer()
                                if editableLots.count > 1 {
                                    Button(role: .destructive) {
                                        editableLots.removeAll { $0.id == lot.id }
                                        recalculateFromLots()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            DatePicker("買入 / 加碼日期", selection: $lot.buyDate, displayedComponents: .date)
                                .font(.caption)
                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Text("股數").font(.caption).foregroundColor(.secondary)
                                    TextField("股數", value: $lot.shares, format: .number)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: lot.shares) { _ in recalculateFromLots() }
                                }
                                Divider()

                                HStack(spacing: 4) {
                                    Text("單價").font(.caption).foregroundColor(.secondary)
                                    TextField("價格", value: $lot.price, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: lot.price) { _ in recalculateFromLots() }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if showAddLotBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("新增一筆加碼紀錄")
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "#FF9500"))
                            DatePicker("加碼日期", selection: $newLotDate, displayedComponents: .date)
                                .font(.caption)
                            TextField("加碼股數 (例: 100000 = 100張)", text: $newLotShares)
                                .keyboardType(.numberPad)
                            TextField("加碼成交價 (元)", text: $newLotPrice)
                                .keyboardType(.decimalPad)
                            HStack {
                                Button("取消") { showAddLotBox = false }
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("加入此筆加碼") {
                                    let s = Int(newLotShares) ?? 0
                                    let p = Double(newLotPrice) ?? (Double(currentPrice) ?? holding.currentPrice)
                                    if s > 0 {
                                        editableLots.append(HoldingLot(buyDate: newLotDate, shares: s, price: p, note: "加碼買進"))
                                        editableLots.sort { $0.buyDate < $1.buyDate }
                                        recalculateFromLots()
                                        showAddLotBox = false
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "#007AFF"))
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            newLotDate = Date()
                            newLotPrice = currentPrice
                            newLotShares = "1000"
                            showAddLotBox = true
                        } label: {
                            Label("新增一筆買入 / 加碼日期紀錄", systemImage: "plus.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundColor(Color(hex: "#007AFF"))
                        }
                    }
                } header: {
                    Text("買入與加碼日期明細 (決定各月除息可領股數)")
                } footer: {
                    Text("例：00406A 若 10/20 買 10,000 股、11/04 加碼 100,000 股，11 月僅以 10,000 股計息（約 $1,380），11/04 加碼須待 12 月配息公布後方可領取。")
                        .font(.caption2)
                }
                
                Section("總持股與現價") {
                    HStack {
                        Text("持有總股數")
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
                        updated.currentPrice = Double(currentPrice) ?? holding.currentPrice
                        updated.totalDividendsReceived = Double(totalDividends) ?? holding.totalDividendsReceived
                        updated.dividendCount = Int(dividendCount) ?? holding.dividendCount
                        updated.brokerage = brokerage
                        let cleanLots = editableLots.filter { $0.shares > 0 }.sorted { $0.buyDate < $1.buyDate }
                        if !cleanLots.isEmpty {
                            updated.lots = cleanLots
                            updated.syncFromLots()
                        } else {
                            updated.shares = Int(shares) ?? holding.shares
                            updated.averageCost = Double(averageCost) ?? holding.averageCost
                            updated.updatedAt = Date()
                        }
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
                if holding.lots.isEmpty && holding.shares > 0 {
                    editableLots = [HoldingLot(buyDate: holding.purchaseDate, shares: holding.shares, price: holding.averageCost, note: "初始買入")]
                } else {
                    editableLots = holding.lots.sorted { $0.buyDate < $1.buyDate }
                }
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
    @State private var selectedViewMode: Int = 0 // 0: 📅 月曆顯示, 1: ⏳ 倒數清單
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    
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
                
                // 2. 檢視模式切換：月曆顯示 vs 倒數清單
                Picker("檢視模式", selection: $selectedViewMode) {
                    Text("📅 月曆顯示").tag(0)
                    Text("⏳ 倒數清單").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom, 2)
                
                // 3. 重大行事曆分類篩選 Chip
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
                    .padding(.vertical, 6)
                }
                
                // 4. 主要顯示內容 (月曆顯示 vs 剩餘天數倒數清單，均支援滑動刪除)
                if selectedViewMode == 0 {
                    TaiwanStockCalendarMonthView(
                        events: filteredEvents,
                        heldSymbols: heldSymbols,
                        selectedDate: $selectedDate,
                        currentMonth: $currentMonth,
                        onDelete: { eventToDelete in
                            StorageService.shared.deleteEvent(id: eventToDelete.id)
                            events = StorageService.shared.loadEvents()
                            NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                        }
                    )
                } else {
                    TaiwanStockCountdownListView(
                        events: filteredEvents,
                        heldSymbols: heldSymbols,
                        onDelete: { eventToDelete in
                            StorageService.shared.deleteEvent(id: eventToDelete.id)
                            events = StorageService.shared.loadEvents()
                            NotificationService.shared.syncDividendReminders(events: events, holdings: holdings)
                        }
                    )
                }
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
    var onDelete: ((DividendEvent) -> Void)? = nil
    
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete?(event)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let ev = sortedEvents[index]
                            onDelete?(ev)
                        }
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
    var onDelete: ((DividendEvent) -> Void)? = nil
    
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        onDelete?(ev)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
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
    @State private var buyDate: Date = Date()
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
                    DatePicker(
                        existingHolding != nil && isDCAMode ? "加碼日期" : "買入日期",
                        selection: $buyDate,
                        displayedComponents: .date
                    )
                    let curY = Calendar.current.component(.year, from: Date())
                    let curM = Calendar.current.component(.month, from: Date())
                    let cleanSym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let loadedEvents = StorageService.shared.loadEvents()
                    let announcedThisMonth = StockHolding.announcedDividendInMonth(
                        for: cleanSym,
                        year: curY,
                        month: curM,
                        events: loadedEvents
                    )
                    let cutoffNow = StockHolding.exDividendCutoffDate(
                        for: cleanSym,
                        year: curY,
                        month: curM,
                        events: loadedEvents
                    )
                    let eligibleThisMonth = Calendar.current.startOfDay(for: buyDate) < cutoffNow
                    if let ann = announcedThisMonth {
                        Text("📅 \(cleanSym) 本月公告除權息日：\(ann.exDateString)（每股配 $\(String(format: "%.3f", ann.cashPerShare))）")
                            .font(.caption2.bold())
                            .foregroundColor(Color(hex: "#1D4ED8"))
                    }
                    HStack {
                        Text(eligibleThisMonth
                             ? "✓ 該日期在除權息日 (\(announcedThisMonth?.exDateString ?? "本月截算日")) 前買進，計入本月配息"
                             : "⏳ 該日期已達或超過本月除權息日，配息將計入下期")
                            .font(.caption2.bold())
                            .foregroundColor(eligibleThisMonth ? Color(hex: "#15803D") : Color(hex: "#C2410C"))
                        Spacer()
                        if !eligibleThisMonth,
                           let preExDate = Calendar.current.date(byAdding: .day, value: -1, to: cutoffNow) {
                            Button("⚡ 設為除息前買入") {
                                buyDate = preExDate
                            }
                            .font(.caption2.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "#15803D"))
                        }
                    }

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
                            brokerage: brokerage,
                            purchaseDate: buyDate
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
// MARK: 3D 互動財富寵物舞台（去卡片化：招財貓 / 貪錢鳥 / 財氣犬）
// MARK: ==========================================

private struct PetParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let offsetX: CGFloat
    let targetY: CGFloat
}

private let petInteractQuotes: [PetSpecies: [String]] = [
    .cat: [
        "喵～多摸兩下，下個月股息翻倍！",
        "「發」字肉球借你摸一下，財氣滿溢！",
        "千万両金幣守護中，穩穩收租喵！"
    ],
    .bird: [
        "啾啾！再多一點金幣，馬上買零股！",
        "眼睛亮晶晶✦ 我聞到除息的味道了！",
        "紅袋子還沒裝滿呢，繼續領息啾！"
    ],
    .dog: [
        "汪汪！我幫你把「財」聚寶盆顧好好！",
        "背上這袋「福」元寶越養越重囉！",
        "摸頭好開心，長期持有我不放手汪！"
    ]
]

// MARK: - 專業 3D 立體遊戲引擎 (SceneKit 真 3D 立體模型 + 360° 自由視角 + 3D 物理追逐金幣)
struct Pet3DSceneKitGameView: UIViewRepresentable {
    let species: PetSpecies
    let isDogSitting: Bool
    let isCompact: Bool
    let actionTrigger: Int
    let actionType: String // "pat", "swoop", "coin"
    var onCatchCoin: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.isPlaying = true
        scnView.loops = true
        scnView.scene = context.coordinator.scene
        scnView.pointOfView = context.coordinator.cameraNode
        scnView.delegate = context.coordinator

        if !isCompact {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            scnView.addGestureRecognizer(pan)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        context.coordinator.scnView = scnView
        context.coordinator.rebuildPet(species: species)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.currentSpecies != species {
            context.coordinator.rebuildPet(species: species)
        }
        context.coordinator.isDogSitting = isDogSitting
        if context.coordinator.lastActionTrigger != actionTrigger {
            context.coordinator.lastActionTrigger = actionTrigger
            context.coordinator.triggerAction(type: actionType)
        }
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: Pet3DSceneKitGameView
        weak var scnView: SCNView?
        let scene = SCNScene()
        let cameraOrbitNode = SCNNode()
        let cameraNode = SCNNode()
        let worldNode = SCNNode()
        let petRootNode = SCNNode()
        let petBodyGroup = SCNNode()

        // 3D 關節節點
        var headNode = SCNNode()
        var leftEyeNode = SCNNode()
        var rightEyeNode = SCNNode()
        var rightArmPivot = SCNNode()
        var leftArmPivot = SCNNode()
        var leftWingPivot = SCNNode()
        var rightWingPivot = SCNNode()
        var tailPivot = SCNNode()
        var legFL = SCNNode()
        var legFR = SCNNode()
        var legBL = SCNNode()
        var legBR = SCNNode()

        var currentSpecies: PetSpecies? = nil
        var isDogSitting: Bool = false
        var lastActionTrigger: Int = 0

        // 3D 攝影機軌道角度
        var cameraYaw: Float = 0.0
        var cameraPitch: Float = -0.22
        var panStartYaw: Float = 0.0
        var panStartPitch: Float = -0.22

        // 3D 空間運動與追逐金幣狀態
        var posX: Float = 0.0
        var posY: Float = 0.0
        var posZ: Float = 0.0
        var facingYaw: Float = 0.0
        var targetCoinNode: SCNNode? = nil
        var targetX: Float = 0.0
        var targetZ: Float = 0.0
        var hasTargetCoin: Bool = false
        var jumpVelocityY: Float = 0.0
        var jumpOffsetY: Float = 0.0
        var swoopUntilTime: TimeInterval = 0.0

        init(_ parent: Pet3DSceneKitGameView) {
            self.parent = parent
            super.init()
            setupScene()
        }

        private func makePBRMaterial(hex: String, roughness: CGFloat = 0.38, metalness: CGFloat = 0.05, emissionHex: String? = nil) -> SCNMaterial {
            let mat = SCNMaterial()
            mat.lightingModel = .physicallyBased
            mat.diffuse.contents = UIColor(Color(hex: hex))
            mat.roughness.contents = roughness
            mat.metalness.contents = metalness
            if let em = emissionHex {
                mat.emission.contents = UIColor(Color(hex: em)).withAlphaComponent(0.25)
            }
            return mat
        }

        private func setupScene() {
            scene.rootNode.addChildNode(worldNode)
            worldNode.addChildNode(petRootNode)
            petRootNode.addChildNode(petBodyGroup)

            // 1. 3D 透視攝影機
            let cam = SCNCamera()
            cam.fieldOfView = parent.isCompact ? 36 : 42
            cam.zNear = 0.1
            cam.zFar = 100
            cameraNode.camera = cam
            cameraNode.position = SCNVector3(0, parent.isCompact ? 1.55 : 2.15, parent.isCompact ? 4.3 : 5.6)
            cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, 0)
            cameraOrbitNode.addChildNode(cameraNode)
            scene.rootNode.addChildNode(cameraOrbitNode)

            // 2. 專業三點立體打光 (主太陽光 + 暖金補光 + 天空環境光)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 520
            ambient.light?.color = UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0)
            scene.rootNode.addChildNode(ambient)

            let dirLight = SCNNode()
            dirLight.light = SCNLight()
            dirLight.light?.type = .directional
            dirLight.light?.intensity = 980
            dirLight.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1.0)
            dirLight.light?.castsShadow = true
            dirLight.light?.shadowRadius = 4
            dirLight.light?.shadowColor = UIColor.black.withAlphaComponent(0.28)
            dirLight.position = SCNVector3(4, 7, 5)
            dirLight.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 4.5, 0)
            scene.rootNode.addChildNode(dirLight)

            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .omni
            rimLight.light?.intensity = 450
            rimLight.light?.color = UIColor(Color(hex: "#FDE047"))
            rimLight.position = SCNVector3(-3.5, 3.0, -3.5)
            scene.rootNode.addChildNode(rimLight)

            // 3. 3D 遊戲綠茵浮島地形 (非平面舞台卡片)
            let radius: CGFloat = parent.isCompact ? 1.45 : 2.35
            let grassTop = SCNCylinder(radius: radius, height: 0.22)
            grassTop.radialSegmentCount = 48
            grassTop.materials = [makePBRMaterial(hex: "#4ADE80", roughness: 0.55)]
            let grassNode = SCNNode(geometry: grassTop)
            grassNode.position = SCNVector3(0, -0.11, 0)
            worldNode.addChildNode(grassNode)

            let goldTrim = SCNTorus(ringRadius: radius + 0.02, pipeRadius: 0.055)
            goldTrim.ringSegmentCount = 48
            goldTrim.materials = [makePBRMaterial(hex: "#F59E0B", roughness: 0.22, metalness: 0.78)]
            let trimNode = SCNNode(geometry: goldTrim)
            trimNode.position = SCNVector3(0, -0.02, 0)
            worldNode.addChildNode(trimNode)

            let rockBase = SCNCone(topRadius: radius * 0.96, bottomRadius: radius * 0.52, height: 0.55)
            rockBase.radialSegmentCount = 36
            rockBase.materials = [makePBRMaterial(hex: "#D97706", roughness: 0.65)]
            let baseNode = SCNNode(geometry: rockBase)
            baseNode.position = SCNVector3(0, -0.48, 0)
            worldNode.addChildNode(baseNode)

            if !parent.isCompact {
                // 3D 聚寶盆與金元寶擺件在島嶼後方角落
                let pot = SCNSphere(radius: 0.34)
                pot.materials = [makePBRMaterial(hex: "#B45309", roughness: 0.25, metalness: 0.72)]
                let potNode = SCNNode(geometry: pot)
                potNode.scale = SCNVector3(1.1, 0.75, 1.1)
                potNode.position = SCNVector3(1.45, 0.18, -1.15)
                worldNode.addChildNode(potNode)

                for i in 0..<3 {
                    let coin = SCNCylinder(radius: 0.14, height: 0.05)
                    coin.materials = [makePBRMaterial(hex: "#FACC15", roughness: 0.18, metalness: 0.88)]
                    let cn = SCNNode(geometry: coin)
                    cn.position = SCNVector3(1.38 + Float(i) * 0.07, 0.38 + Float(i) * 0.04, -1.15)
                    cn.eulerAngles = SCNVector3(0.3, Float(i) * 0.5, 0.2)
                    worldNode.addChildNode(cn)
                }
            }
        }

        func rebuildPet(species: PetSpecies) {
            currentSpecies = species
            petBodyGroup.childNodes.forEach { $0.removeFromParentNode() }
            headNode = SCNNode()
            leftEyeNode = SCNNode()
            rightEyeNode = SCNNode()
            rightArmPivot = SCNNode()
            leftArmPivot = SCNNode()
            leftWingPivot = SCNNode()
            rightWingPivot = SCNNode()
            tailPivot = SCNNode()
            legFL = SCNNode()
            legFR = SCNNode()
            legBL = SCNNode()
            legBR = SCNNode()

            switch species {
            case .cat:
                build3DLuckyCat()
            case .bird:
                build3DMoneyBird()
            case .dog:
                build3DFortuneDog()
            }
        }

        // MARK: 建立真 3D 立體招財貓模型
        private func build3DLuckyCat() {
            let whiteMat = makePBRMaterial(hex: "#FFFBEB", roughness: 0.32)
            let redMat = makePBRMaterial(hex: "#EF4444", roughness: 0.35)
            let pinkMat = makePBRMaterial(hex: "#FDA4AF", roughness: 0.4)
            let goldMat = makePBRMaterial(hex: "#FACC15", roughness: 0.18, metalness: 0.85)
            let darkMat = makePBRMaterial(hex: "#1E1B18", roughness: 0.12)
            let orangePatchMat = makePBRMaterial(hex: "#F97316", roughness: 0.4)

            // 圓潤 3D 身體
            let torsoGeo = SCNSphere(radius: 0.54)
            torsoGeo.materials = [whiteMat]
            let torso = SCNNode(geometry: torsoGeo)
            torso.scale = SCNVector3(0.96, 1.05, 0.88)
            torso.position = SCNVector3(0, 0.62, 0)
            petBodyGroup.addChildNode(torso)

            // 紅色項圈與 3D 金鈴鐺
            let collarGeo = SCNTorus(ringRadius: 0.42, pipeRadius: 0.055)
            collarGeo.materials = [redMat]
            let collar = SCNNode(geometry: collarGeo)
            collar.position = SCNVector3(0, 1.02, 0.02)
            petBodyGroup.addChildNode(collar)

            let bellGeo = SCNSphere(radius: 0.11)
            bellGeo.materials = [goldMat]
            let bell = SCNNode(geometry: bellGeo)
            bell.position = SCNVector3(0, 0.98, 0.45)
            petBodyGroup.addChildNode(bell)

            // 3D 頭部
            headNode.position = SCNVector3(0, 1.42, 0.04)
            petBodyGroup.addChildNode(headNode)

            let headGeo = SCNSphere(radius: 0.52)
            headGeo.materials = [whiteMat]
            let headMesh = SCNNode(geometry: headGeo)
            headMesh.scale = SCNVector3(1.06, 0.96, 0.95)
            headNode.addChildNode(headMesh)

            // 三花橘斑與立體貓耳
            let patchGeo = SCNSphere(radius: 0.22)
            patchGeo.materials = [orangePatchMat]
            let patchNode = SCNNode(geometry: patchGeo)
            patchNode.position = SCNVector3(-0.26, 0.26, 0.18)
            headNode.addChildNode(patchNode)

            for side: Float in [-1, 1] {
                let earOuter = SCNCone(topRadius: 0.02, bottomRadius: 0.20, height: 0.34)
                earOuter.materials = [side < 0 ? orangePatchMat : whiteMat]
                let earNode = SCNNode(geometry: earOuter)
                earNode.position = SCNVector3(side * 0.36, 0.46, -0.02)
                earNode.eulerAngles = SCNVector3(0.08, 0, -side * 0.38)
                headNode.addChildNode(earNode)

                let earInner = SCNCone(topRadius: 0.01, bottomRadius: 0.11, height: 0.24)
                earInner.materials = [pinkMat]
                let innerNode = SCNNode(geometry: earInner)
                innerNode.position = SCNVector3(0, -0.01, 0.07)
                earNode.addChildNode(innerNode)
            }

            // 3D 靈動大眼睛 + 高光 + 粉紅腮紅 + 鼻頭
            for (side, isLeft) in [(-1.0 as Float, true), (1.0 as Float, false)] {
                let eyeGeo = SCNSphere(radius: 0.095)
                eyeGeo.materials = [darkMat]
                let eye = SCNNode(geometry: eyeGeo)
                eye.position = SCNVector3(side * 0.21, 0.05, 0.45)

                let shineGeo = SCNSphere(radius: 0.032)
                shineGeo.materials = [makePBRMaterial(hex: "#FFFFFF", roughness: 0.05)]
                let shine = SCNNode(geometry: shineGeo)
                shine.position = SCNVector3(0.03, 0.035, 0.075)
                eye.addChildNode(shine)
                headNode.addChildNode(eye)
                if isLeft { leftEyeNode = eye } else { rightEyeNode = eye }

                let cheekGeo = SCNSphere(radius: 0.08)
                cheekGeo.materials = [pinkMat]
                let cheek = SCNNode(geometry: cheekGeo)
                cheek.scale = SCNVector3(1.2, 0.7, 0.5)
                cheek.position = SCNVector3(side * 0.33, -0.08, 0.41)
                headNode.addChildNode(cheek)
            }

            let noseGeo = SCNSphere(radius: 0.048)
            noseGeo.materials = [pinkMat]
            let nose = SCNNode(geometry: noseGeo)
            nose.scale = SCNVector3(1.2, 0.85, 0.8)
            nose.position = SCNVector3(0, -0.04, 0.51)
            headNode.addChildNode(nose)

            // 右手 3D 招財手臂關節 (前後立體揮動)
            rightArmPivot.position = SCNVector3(-0.46, 0.96, 0.10)
            petBodyGroup.addChildNode(rightArmPivot)

            let armGeo = SCNCapsule(capRadius: 0.115, height: 0.46)
            armGeo.materials = [whiteMat]
            let armNode = SCNNode(geometry: armGeo)
            armNode.position = SCNVector3(-0.06, 0.18, 0.08)
            rightArmPivot.addChildNode(armNode)

            let pawGeo = SCNSphere(radius: 0.13)
            pawGeo.materials = [whiteMat]
            let pawNode = SCNNode(geometry: pawGeo)
            pawNode.position = SCNVector3(-0.06, 0.36, 0.12)
            rightArmPivot.addChildNode(pawNode)

            // 左手抱 3D 立體千萬兩金幣 (Koban)
            leftArmPivot.position = SCNVector3(0.45, 0.84, 0.18)
            petBodyGroup.addChildNode(leftArmPivot)
            let lArmNode = SCNNode(geometry: armGeo)
            lArmNode.eulerAngles = SCNVector3(0.5, 0, -0.4)
            leftArmPivot.addChildNode(lArmNode)

            let kobanGeo = SCNBox(width: 0.30, height: 0.44, length: 0.08, chamferRadius: 0.08)
            kobanGeo.materials = [goldMat]
            let koban = SCNNode(geometry: kobanGeo)
            koban.position = SCNVector3(0.32, 0.68, 0.44)
            koban.eulerAngles = SCNVector3(-0.15, 0.25, -0.12)
            petBodyGroup.addChildNode(koban)

            // 3D 雙腳與搖擺貓尾
            let legGeo = SCNCapsule(capRadius: 0.125, height: 0.38)
            legGeo.materials = [whiteMat]
            legFL = SCNNode(geometry: legGeo)
            legFL.position = SCNVector3(-0.23, 0.19, 0.10)
            petBodyGroup.addChildNode(legFL)

            legFR = SCNNode(geometry: legGeo)
            legFR.position = SCNVector3(0.23, 0.19, 0.10)
            petBodyGroup.addChildNode(legFR)

            tailPivot.position = SCNVector3(0, 0.38, -0.44)
            petBodyGroup.addChildNode(tailPivot)
            let tailGeo = SCNCapsule(capRadius: 0.075, height: 0.55)
            tailGeo.materials = [orangePatchMat]
            let tailMesh = SCNNode(geometry: tailGeo)
            tailMesh.position = SCNVector3(0, 0.22, -0.10)
            tailMesh.eulerAngles = SCNVector3(-0.55, 0, 0)
            tailPivot.addChildNode(tailMesh)
        }

        // MARK: 建立真 3D 立體貪錢鳥模型
        private func build3DMoneyBird() {
            let goldFeatherMat = makePBRMaterial(hex: "#F59E0B", roughness: 0.32, metalness: 0.15)
            let bellyMat = makePBRMaterial(hex: "#FEF3C7", roughness: 0.38)
            let wingMat = makePBRMaterial(hex: "#D97706", roughness: 0.35)
            let beakMat = makePBRMaterial(hex: "#EA580C", roughness: 0.28)
            let coinMat = makePBRMaterial(hex: "#FACC15", roughness: 0.16, metalness: 0.88)
            let darkMat = makePBRMaterial(hex: "#1E1B18", roughness: 0.10)
            let cheekMat = makePBRMaterial(hex: "#FB7185", roughness: 0.4)

            // 圓滾滾 3D 鳥身
            let bodyGeo = SCNSphere(radius: 0.54)
            bodyGeo.materials = [goldFeatherMat]
            let bodyNode = SCNNode(geometry: bodyGeo)
            bodyNode.scale = SCNVector3(0.95, 0.92, 1.08)
            bodyNode.position = SCNVector3(0, 0.95, 0)
            petBodyGroup.addChildNode(bodyNode)

            let bellyGeo = SCNSphere(radius: 0.44)
            bellyGeo.materials = [bellyMat]
            let bellyNode = SCNNode(geometry: bellyGeo)
            bellyNode.position = SCNVector3(0, 0.88, 0.18)
            petBodyGroup.addChildNode(bellyNode)

            // 頭頂呆毛羽冠
            headNode.position = SCNVector3(0, 1.38, 0.12)
            petBodyGroup.addChildNode(headNode)
            for i in -1...1 {
                let crestGeo = SCNCapsule(capRadius: 0.045, height: 0.24)
                crestGeo.materials = [goldFeatherMat]
                let crest = SCNNode(geometry: crestGeo)
                crest.position = SCNVector3(Float(i) * 0.06, 0.14, 0)
                crest.eulerAngles = SCNVector3(-0.2, 0, Float(i) * -0.28)
                headNode.addChildNode(crest)
            }

            // 3D 靈動大眼睛與腮紅
            for (side, isLeft) in [(-1.0 as Float, true), (1.0 as Float, false)] {
                let eyeGeo = SCNSphere(radius: 0.095)
                eyeGeo.materials = [darkMat]
                let eye = SCNNode(geometry: eyeGeo)
                eye.position = SCNVector3(side * 0.24, 1.06, 0.48)
                let shine = SCNNode(geometry: SCNSphere(radius: 0.032))
                shine.geometry?.materials = [makePBRMaterial(hex: "#FFFFFF", roughness: 0.05)]
                shine.position = SCNVector3(0.03, 0.035, 0.075)
                eye.addChildNode(shine)
                petBodyGroup.addChildNode(eye)
                if isLeft { leftEyeNode = eye } else { rightEyeNode = eye }

                let cheek = SCNNode(geometry: SCNSphere(radius: 0.08))
                cheek.geometry?.materials = [cheekMat]
                cheek.position = SCNVector3(side * 0.34, 0.94, 0.44)
                petBodyGroup.addChildNode(cheek)
            }

            // 3D 鳥喙咬著立體旋轉金幣
            let beakGeo = SCNCone(topRadius: 0.01, bottomRadius: 0.12, height: 0.24)
            beakGeo.materials = [beakMat]
            let beak = SCNNode(geometry: beakGeo)
            beak.position = SCNVector3(0, 0.98, 0.62)
            beak.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            petBodyGroup.addChildNode(beak)

            let heldCoinGeo = SCNCylinder(radius: 0.20, height: 0.055)
            heldCoinGeo.materials = [coinMat]
            let heldCoin = SCNNode(geometry: heldCoinGeo)
            heldCoin.position = SCNVector3(0, 0.85, 0.72)
            heldCoin.eulerAngles = SCNVector3(Float.pi / 2.2, 0, 0)
            petBodyGroup.addChildNode(heldCoin)

            // 3D 左右立體翅膀關節
            leftWingPivot.position = SCNVector3(-0.48, 1.02, 0.0)
            rightWingPivot.position = SCNVector3(0.48, 1.02, 0.0)
            petBodyGroup.addChildNode(leftWingPivot)
            petBodyGroup.addChildNode(rightWingPivot)

            let wingGeo = SCNBox(width: 0.56, height: 0.12, length: 0.42, chamferRadius: 0.06)
            wingGeo.materials = [wingMat]
            let lWing = SCNNode(geometry: wingGeo)
            lWing.position = SCNVector3(-0.24, 0, 0)
            leftWingPivot.addChildNode(lWing)

            let rWing = SCNNode(geometry: wingGeo)
            rWing.position = SCNVector3(0.24, 0, 0)
            rightWingPivot.addChildNode(rWing)

            // 3D 尾羽
            tailPivot.position = SCNVector3(0, 0.82, -0.52)
            petBodyGroup.addChildNode(tailPivot)
            let tailGeo = SCNBox(width: 0.28, height: 0.08, length: 0.34, chamferRadius: 0.04)
            tailGeo.materials = [wingMat]
            let tailNode = SCNNode(geometry: tailGeo)
            tailNode.position = SCNVector3(0, 0.04, -0.14)
            tailNode.eulerAngles = SCNVector3(0.35, 0, 0)
            tailPivot.addChildNode(tailNode)
        }

        // MARK: 建立真 3D 立體財氣犬 (柴犬) 模型
        private func build3DFortuneDog() {
            let shibaMat = makePBRMaterial(hex: "#EA580C", roughness: 0.38)
            let creamMat = makePBRMaterial(hex: "#FFFBEB", roughness: 0.35)
            let redMat = makePBRMaterial(hex: "#DC2626", roughness: 0.35)
            let goldMat = makePBRMaterial(hex: "#FACC15", roughness: 0.18, metalness: 0.86)
            let darkMat = makePBRMaterial(hex: "#1E1B18", roughness: 0.12)

            // 3D 柴犬身體
            let torsoGeo = SCNCapsule(capRadius: 0.40, height: 0.98)
            torsoGeo.materials = [shibaMat]
            let torso = SCNNode(geometry: torsoGeo)
            torso.position = SCNVector3(0, 0.62, 0)
            torso.eulerAngles = SCNVector3(Float.pi / 2.3, 0, 0)
            petBodyGroup.addChildNode(torso)

            let chestGeo = SCNSphere(radius: 0.36)
            chestGeo.materials = [creamMat]
            let chest = SCNNode(geometry: chestGeo)
            chest.position = SCNVector3(0, 0.68, 0.24)
            petBodyGroup.addChildNode(chest)

            // 紅色招財領巾與金牌
            let collarGeo = SCNTorus(ringRadius: 0.37, pipeRadius: 0.055)
            collarGeo.materials = [redMat]
            let collar = SCNNode(geometry: collarGeo)
            collar.position = SCNVector3(0, 0.96, 0.22)
            collar.eulerAngles = SCNVector3(0.25, 0, 0)
            petBodyGroup.addChildNode(collar)

            let medalGeo = SCNCylinder(radius: 0.11, height: 0.04)
            medalGeo.materials = [goldMat]
            let medal = SCNNode(geometry: medalGeo)
            medal.position = SCNVector3(0, 0.86, 0.58)
            medal.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            petBodyGroup.addChildNode(medal)

            // 3D 柴犬頭部、吻部、白眉與立耳
            headNode.position = SCNVector3(0, 1.32, 0.28)
            petBodyGroup.addChildNode(headNode)

            let headGeo = SCNSphere(radius: 0.46)
            headGeo.materials = [shibaMat]
            let headMesh = SCNNode(geometry: headGeo)
            headMesh.scale = SCNVector3(1.05, 0.96, 0.98)
            headNode.addChildNode(headMesh)

            let snoutGeo = SCNSphere(radius: 0.24)
            snoutGeo.materials = [creamMat]
            let snout = SCNNode(geometry: snoutGeo)
            snout.scale = SCNVector3(1.1, 0.82, 1.15)
            snout.position = SCNVector3(0, -0.10, 0.36)
            headNode.addChildNode(snout)

            let noseGeo = SCNSphere(radius: 0.065)
            noseGeo.materials = [darkMat]
            let nose = SCNNode(geometry: noseGeo)
            nose.position = SCNVector3(0, -0.02, 0.58)
            headNode.addChildNode(nose)

            for (side, isLeft) in [(-1.0 as Float, true), (1.0 as Float, false)] {
                let earGeo = SCNCone(topRadius: 0.02, bottomRadius: 0.18, height: 0.34)
                earGeo.materials = [shibaMat]
                let ear = SCNNode(geometry: earGeo)
                ear.position = SCNVector3(side * 0.32, 0.44, -0.04)
                ear.eulerAngles = SCNVector3(0.12, 0, -side * 0.30)
                headNode.addChildNode(ear)

                let eyeGeo = SCNSphere(radius: 0.082)
                eyeGeo.materials = [darkMat]
                let eye = SCNNode(geometry: eyeGeo)
                eye.position = SCNVector3(side * 0.19, 0.06, 0.41)
                let shine = SCNNode(geometry: SCNSphere(radius: 0.028))
                shine.geometry?.materials = [makePBRMaterial(hex: "#FFFFFF", roughness: 0.05)]
                shine.position = SCNVector3(0.025, 0.03, 0.065)
                eye.addChildNode(shine)
                headNode.addChildNode(eye)
                if isLeft { leftEyeNode = eye } else { rightEyeNode = eye }

                // 柴犬招牌白豆眉
                let browGeo = SCNSphere(radius: 0.045)
                browGeo.materials = [creamMat]
                let brow = SCNNode(geometry: browGeo)
                brow.scale = SCNVector3(1.3, 0.7, 0.7)
                brow.position = SCNVector3(side * 0.17, 0.19, 0.40)
                headNode.addChildNode(brow)
            }

            // 4 條 3D 可動腿 (支援快步小跑與坐下姿勢切換)
            let legGeo = SCNCapsule(capRadius: 0.105, height: 0.44)
            legGeo.materials = [shibaMat]
            legFL = SCNNode(geometry: legGeo)
            legFL.position = SCNVector3(-0.22, 0.22, 0.28)
            legFR = SCNNode(geometry: legGeo)
            legFR.position = SCNVector3(0.22, 0.22, 0.28)
            legBL = SCNNode(geometry: legGeo)
            legBL.position = SCNVector3(-0.22, 0.22, -0.26)
            legBR = SCNNode(geometry: legGeo)
            legBR.position = SCNVector3(0.22, 0.22, -0.26)
            petBodyGroup.addChildNode(legFL)
            petBodyGroup.addChildNode(legFR)
            petBodyGroup.addChildNode(legBL)
            petBodyGroup.addChildNode(legBR)

            // 3D 捲曲柴犬尾巴
            tailPivot.position = SCNVector3(0, 0.76, -0.44)
            petBodyGroup.addChildNode(tailPivot)
            let tailGeo = SCNTorus(ringRadius: 0.16, pipeRadius: 0.075)
            tailGeo.materials = [shibaMat]
            let tailNode = SCNNode(geometry: tailGeo)
            tailNode.position = SCNVector3(0, 0.14, -0.06)
            tailNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            tailPivot.addChildNode(tailNode)
        }

        // MARK: 投擲 3D 金幣與互動特效
        func spawn3DCoin(atX x: Float, z: Float) {
            targetCoinNode?.removeFromParentNode()
            let coinGeo = SCNCylinder(radius: 0.22, height: 0.065)
            coinGeo.materials = [makePBRMaterial(hex: "#FACC15", roughness: 0.15, metalness: 0.90, emissionHex: "#F59E0B")]
            let coinNode = SCNNode(geometry: coinGeo)
            coinNode.position = SCNVector3(x, 1.8, z)
            coinNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            worldNode.addChildNode(coinNode)

            let drop = SCNAction.move(to: SCNVector3(x, 0.24, z), duration: 0.36)
            drop.timingMode = .easeIn
            let bounceUp = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: 0.14)
            let bounceDown = SCNAction.moveBy(x: 0, y: -0.25, z: 0, duration: 0.14)
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 1.0))
            coinNode.runAction(SCNAction.group([spin, SCNAction.sequence([drop, bounceUp, bounceDown])]))

            targetCoinNode = coinNode
            targetX = x
            targetZ = z
            hasTargetCoin = true
            if isDogSitting { isDogSitting = false }
        }

        private func burst3DStars(at pos: SCNVector3) {
            let goldMat = makePBRMaterial(hex: "#FDE047", roughness: 0.1, metalness: 0.85, emissionHex: "#F59E0B")
            for i in 0..<8 {
                let star = SCNNode(geometry: SCNSphere(radius: 0.08))
                star.geometry?.materials = [goldMat]
                star.position = SCNVector3(pos.x, pos.y + 0.6, pos.z)
                worldNode.addChildNode(star)
                let angle = Float(i) * (Float.pi * 2 / 8.0)
                let dx = CGFloat(cos(angle) * 0.75)
                let dz = CGFloat(sin(angle) * 0.75)
                let move = SCNAction.moveBy(x: dx, y: 0.7, z: dz, duration: 0.55)
                move.timingMode = .easeOut
                let fade = SCNAction.fadeOut(duration: 0.55)
                star.runAction(SCNAction.sequence([SCNAction.group([move, fade]), SCNAction.removeFromParentNode()]))
            }
        }

        func triggerAction(type: String) {
            if type == "coin" {
                let rx = Float.random(in: -1.15...1.15)
                let rz = Float.random(in: -0.85...0.95)
                spawn3DCoin(atX: rx, z: rz)
            } else if type == "swoop" {
                swoopUntilTime = CACurrentMediaTime() + 1.4
                jumpVelocityY = 0.11
            } else {
                jumpVelocityY = 0.085
                burst3DStars(at: petRootNode.position)
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = scnView else { return }
            let trans = gesture.translation(in: view)
            if gesture.state == .began {
                panStartYaw = cameraYaw
                panStartPitch = cameraPitch
            } else if gesture.state == .changed {
                cameraYaw = panStartYaw - Float(trans.x) * 0.012
                cameraPitch = max(-0.68, min(-0.05, panStartPitch - Float(trans.y) * 0.008))
                cameraOrbitNode.eulerAngles = SCNVector3(0, cameraYaw, 0)
                cameraNode.eulerAngles = SCNVector3(cameraPitch, 0, 0)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if parent.isCompact {
                jumpVelocityY = 0.085
                burst3DStars(at: petRootNode.position)
                parent.onCatchCoin?()
                return
            }
            guard let view = scnView else { return }
            let pt = gesture.location(in: view)
            let hits = view.hitTest(pt, options: nil)
            if let hit = hits.first {
                let wx = max(-1.35, min(1.35, hit.worldCoordinates.x))
                let wz = max(-1.05, min(1.05, hit.worldCoordinates.z))
                spawn3DCoin(atX: wx, z: wz)
            } else {
                spawn3DCoin(atX: Float.random(in: -1.1...1.1), z: Float.random(in: -0.85...0.85))
            }
            parent.onCatchCoin?()
        }

        // MARK: 60fps 3D 骨骼與世界座標更新迴圈
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let t = Float(time)
            let isSwooping = time < swoopUntilTime
            let maxRadius: Float = parent.isCompact ? 0.35 : 1.25

            // 1. 計算 3D 空間走動 / 飛翔 / 追逐金幣位移 (x, y, z)
            var desiredX: Float = 0
            var desiredZ: Float = 0
            if hasTargetCoin {
                desiredX = targetX
                desiredZ = targetZ
                let dx = desiredX - posX
                let dz = desiredZ - posZ
                let dist = hypot(dx, dz)
                if dist > 0.08 {
                    let step = min(dist, isSwooping ? 0.075 : 0.048)
                    posX += (dx / dist) * step
                    posZ += (dz / dist) * step
                    let targetAngle = atan2(dx, dz)
                    facingYaw = facingYaw * 0.82 + targetAngle * 0.18
                } else {
                    // 追上並吃到 3D 金幣！起跳慶祝 + 爆發 3D 金星
                    hasTargetCoin = false
                    targetCoinNode?.removeFromParentNode()
                    targetCoinNode = nil
                    jumpVelocityY = 0.115
                    burst3DStars(at: SCNVector3(posX, posY, posZ))
                }
            } else if parent.isCompact {
                posX = sin(t * 0.9) * 0.12
                posZ = 0
                facingYaw = sin(t * 0.9) * 0.28
            } else if currentSpecies == .dog && isDogSitting {
                facingYaw = sin(t * 0.7) * 0.22
            } else {
                let speed: Float = isSwooping ? 1.65 : 0.75
                desiredX = sin(t * speed) * maxRadius
                desiredZ = sin(t * speed * 2.0) * (maxRadius * 0.52)
                let dx = desiredX - posX
                let dz = desiredZ - posZ
                posX += dx * 0.08
                posZ += dz * 0.08
                if hypot(dx, dz) > 0.004 {
                    let targetAngle = atan2(dx, dz)
                    let diff = atan2(sin(targetAngle - facingYaw), cos(targetAngle - facingYaw))
                    facingYaw += diff * 0.12
                }
            }

            // 2. 垂直跳躍物理與步態彈跳
            if jumpVelocityY != 0 || jumpOffsetY > 0 {
                jumpOffsetY += jumpVelocityY
                jumpVelocityY -= 0.0075
                if jumpOffsetY <= 0 {
                    jumpOffsetY = 0
                    jumpVelocityY = 0
                }
            }

            let walkBounce = (currentSpecies == .dog && isDogSitting) ? 0 : abs(sin(t * (hasTargetCoin || isSwooping ? 11.0 : 6.5))) * 0.11
            let flightY: Float = (currentSpecies == .bird) ? (0.32 + sin(t * 3.8) * 0.14) : walkBounce
            posY = flightY + jumpOffsetY

            petRootNode.position = SCNVector3(posX, posY, posZ)
            petRootNode.eulerAngles = SCNVector3(0, facingYaw, 0)

            // 3. 呼吸彈性 (Squash & Stretch) 與自然眨眼
            let breath = sin(t * 3.0) * 0.025
            petBodyGroup.scale = SCNVector3(1.0 - breath * 0.6, 1.0 + breath, 1.0 - breath * 0.6)
            headNode.eulerAngles = SCNVector3(sin(t * 2.2) * 0.06, sin(t * 1.5) * 0.10, sin(t * 1.8) * 0.07)

            let blinkCycle = fmod(t, 3.6)
            let eyeScaleY: Float = (blinkCycle > 3.44) ? 0.12 : 1.0
            leftEyeNode.scale = SCNVector3(1, eyeScaleY, 1)
            rightEyeNode.scale = SCNVector3(1, eyeScaleY, 1)

            // 4. 各品種專屬 3D 關節動作
            switch currentSpecies {
            case .cat:
                let wave = sin(t * 5.2)
                rightArmPivot.eulerAngles = SCNVector3(-0.75 + wave * 0.55, 0, 0.15)
                let stride = sin(t * (hasTargetCoin ? 11.0 : 6.5)) * 0.35
                legFL.eulerAngles = SCNVector3(stride, 0, 0)
                legFR.eulerAngles = SCNVector3(-stride, 0, 0)
                tailPivot.eulerAngles = SCNVector3(0, sin(t * 4.2) * 0.38, sin(t * 4.2) * 0.25)
            case .bird:
                let flap = sin(t * (hasTargetCoin || isSwooping ? 18.0 : 12.5)) * 0.68
                leftWingPivot.eulerAngles = SCNVector3(0, 0, flap)
                rightWingPivot.eulerAngles = SCNVector3(0, 0, -flap)
                tailPivot.eulerAngles = SCNVector3(sin(t * 6.0) * 0.18, 0, 0)
            case .dog:
                let wag = sin(t * 14.0) * 0.48
                tailPivot.eulerAngles = SCNVector3(0, wag, wag * 0.5)
                if isDogSitting {
                    petBodyGroup.position = SCNVector3(0, -0.10, 0)
                    legBL.eulerAngles = SCNVector3(-1.15, 0, 0)
                    legBR.eulerAngles = SCNVector3(-1.15, 0, 0)
                    legFL.eulerAngles = SCNVector3(0, 0, 0)
                    legFR.eulerAngles = SCNVector3(0, 0, 0)
                } else {
                    petBodyGroup.position = SCNVector3(0, 0, 0)
                    let trot = sin(t * (hasTargetCoin || isSwooping ? 12.0 : 7.5)) * 0.45
                    legFL.eulerAngles = SCNVector3(trot, 0, 0)
                    legBR.eulerAngles = SCNVector3(trot, 0, 0)
                    legFR.eulerAngles = SCNVector3(-trot, 0, 0)
                    legBL.eulerAngles = SCNVector3(-trot, 0, 0)
                }
            case .none:
                break
            }
        }
    }
}

struct PetCompanionBannerCard: View {
    let petState: DividendPetState
    let isDownMarket: Bool
    let auras: [PetAuraBadge]
    let onTapCard: () -> Void
    let onTapFeed: () -> Void

    @State private var actionTrigger: Int = 0
    @State private var reactionQuote: String? = nil
    @State private var isDogSitting = false

    private var levelInfo: PetLevelInfo {
        PetService.shared.levelInfo(for: petState.totalXP)
    }

    private var stageTitle: String {
        let names = petState.species.stageNames
        let idx = max(0, min(names.count - 1, levelInfo.stage - 1))
        return names[idx]
    }

    private var bubbleText: String {
        if !petState.hasChosenStarter {
            return "🎯 點擊選擇你的專屬 3D 財富寵物（三選一出發）"
        }
        if let quote = reactionQuote { return quote }
        if petState.pendingFeedDP > 0 {
            return "有 \(petState.pendingFeedDP) DP 股息金幣待餵食"
        }
        if isDownMarket {
            return petState.species.downMarketLine
        }
        let remain = max(0, levelInfo.needXP - levelInfo.currentXP)
        return "點我 3D 互動招財・距第 \(min(20, levelInfo.stage + 1)) 階還差 \(remain) XP"
    }

    private func pokePet() {
        actionTrigger += 1
        if petState.species == .dog {
            isDogSitting.toggle()
            reactionQuote = isDogSitting ? "乖乖坐下搖尾巴顧「財」盆汪！" : "站起來繼續替你招財巡邏汪！"
        } else if let lines = petInteractQuotes[petState.species], let picked = lines.randomElement() {
            reactionQuote = picked
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 左側：真 3D SceneKit 立體遊戲角色視窗
            Pet3DSceneKitGameView(
                species: petState.species,
                isDogSitting: isDogSitting,
                isCompact: true,
                actionTrigger: actionTrigger,
                actionType: "pat",
                onCatchCoin: { pokePet() }
            )
            .frame(width: 102, height: 102)

            // 右側：開放式對話氣泡 + 進度條 + 互動膠囊鈕
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onTapCard) {
                    Text(bubbleText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Text("Lv.\(levelInfo.level) \(stageTitle)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(hex: "#D97706"))
                    ProgressView(value: levelInfo.progress)
                        .tint(Color(hex: "#F59E0B"))
                }

                HStack(spacing: 8) {
                    if petState.pendingFeedDP > 0 {
                        Button(action: onTapFeed) {
                            Text("🪙 餵食 +\(petState.pendingFeedDP)")
                                .font(.system(size: 13, weight: .heavy))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "#FDE047"), Color(hex: "#F59E0B")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(Color(hex: "#451A03"))
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "#F59E0B").opacity(0.35), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.borderless)
                    }

                    Button(action: onTapCard) {
                        Text(petState.hasChosenStarter ? "🎮 進入 3D 遊戲樂園 ›" : "🎯 三選一領養陪伴 ›")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#007AFF").opacity(0.12))
                            .foregroundColor(Color(hex: "#007AFF"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

struct PetCompanionSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var petState: DividendPetState
    let holdings: [StockHolding]
    let summary: PortfolioDividendSourceSummary
    let isDownMarket: Bool

    @State private var actionTrigger: Int = 0
    @State private var actionType: String = "pat"
    @State private var quoteText: String? = nil
    @State private var isDogSitting = false

    private var levelInfo: PetLevelInfo {
        PetService.shared.levelInfo(for: petState.totalXP)
    }

    private var stageTitle: String {
        let names = petState.species.stageNames
        let idx = max(0, min(names.count - 1, levelInfo.stage - 1))
        return names[idx]
    }

    private var auras: [PetAuraBadge] {
        PetService.shared.auras(for: holdings, summary: summary)
    }

    private func trigger3DAction(type: String) {
        UIImpactFeedbackGenerator(style: type == "coin" ? .medium : .light).impactOccurred()
        actionType = type
        actionTrigger += 1
        if type == "swoop" {
            if petState.species == .dog && isDogSitting { isDogSitting = false }
            switch petState.species {
            case .cat: quoteText = "喵～3D 全速躍動招財！股息通通吸過來！"
            case .bird: quoteText = "啾啾～3D 高空盤旋俯衝接金幣！"
            case .dog: quoteText = "汪汪！活力全開在 3D 綠茵島飛奔！"
            }
        } else if type == "coin" {
            quoteText = "🪙 發現 3D 金幣！立刻轉身衝過去跳躍接住！"
        } else if let lines = petInteractQuotes[petState.species], let picked = lines.randomElement() {
            quoteText = picked
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 寵物選擇列（一開始僅可三選一領養陪伴，確認後鎖定專屬夥伴）
                    VStack(spacing: 8) {
                        HStack {
                            Text(petState.hasChosenStarter ? "🤝 專屬 3D 陪伴夥伴（一對一鎖定培育）" : "🎯 請選擇一種 3D 寵物陪伴出發（三選一）")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(petState.hasChosenStarter ? Color(hex: "#D97706") : .primary)
                            Spacer()
                            if petState.hasChosenStarter {
                                Text("第 \(levelInfo.stage)/20 階")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            ForEach(PetSpecies.allCases) { sp in
                                let isActive = petState.species == sp
                                let isLocked = petState.hasChosenStarter && !isActive
                                Button {
                                    if isLocked {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        quoteText = "每位投資人初始僅能選擇一隻專屬寵物陪伴，專心培育【\(petState.species.displayName)】至第 20 階吧！"
                                        return
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                        petState = PetService.shared.selectSpecies(sp)
                                        quoteText = nil
                                    }
                                    trigger3DAction(type: "pat")
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            Text(sp == .cat ? "🐱" : (sp == .bird ? "🐥" : "🐕"))
                                                .font(.system(size: 34))
                                                .frame(width: 58, height: 58)
                                                .background(
                                                    Circle()
                                                        .fill(isActive ? Color(hex: "#FEF3C7") : Color(.systemGray6))
                                                )
                                                .opacity(isLocked ? 0.36 : 1.0)
                                                .scaleEffect(isActive ? 1.10 : 0.94)
                                            if isLocked {
                                                Text("🔒")
                                                    .font(.system(size: 13))
                                                    .offset(x: 4, y: -2)
                                            }
                                        }
                                        Text(isLocked ? sp.displayName : (isActive && petState.hasChosenStarter ? "✓ \(sp.displayName)" : sp.displayName))
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(isActive ? Color(hex: "#D97706") : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !petState.hasChosenStarter {
                            Button {
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                    petState = PetService.shared.adoptStarter(petState.species)
                                }
                                trigger3DAction(type: "coin")
                                quoteText = "太棒了！【\(petState.species.displayName)】正式成為你的專屬 3D 財富夥伴！"
                            } label: {
                                Text("✨ 確認領養【\(petState.species.displayName)】開始陪伴")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "#FDE047"), Color(hex: "#F59E0B")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(Color(hex: "#451A03"))
                                    .clipShape(Capsule())
                                    .shadow(color: Color(hex: "#F59E0B").opacity(0.35), radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 專業 SceneKit 真 3D 立體遊戲畫面（支援 360° 旋轉視角 + 點擊地面投擲 3D 金幣追逐）
                    VStack(spacing: 10) {
                        HStack {
                            Text("🎮 360° 拖曳旋轉 3D 視角 · 點地面投擲 3D 金幣")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("🪙 \(petState.spendableDP) DP")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(Color(hex: "#D97706"))
                        }

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 22)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#E0F2FE"), Color(hex: "#FEF9C3").opacity(0.65), Color(hex: "#DCFCE7").opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            Pet3DSceneKitGameView(
                                species: petState.species,
                                isDogSitting: isDogSitting,
                                isCompact: false,
                                actionTrigger: actionTrigger,
                                actionType: actionType,
                                onCatchCoin: {
                                    quoteText = "🪙 追上 3D 金幣了！開心地跳起來招財！"
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                        }
                        .frame(height: 295)
                        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)

                        Text("Lv.\(levelInfo.level) \(stageTitle)（第 \(levelInfo.stage)/20 階）")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)

                        Text(quoteText ?? (isDownMarket ? petState.species.downMarketLine : "\(petState.species.tagline)（點擊 3D 島嶼地面投金幣引導追逐）"))
                            .font(.system(size: 14, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)

                        // 3D 互動按鈕組
                        HStack(spacing: 8) {
                            Button {
                                trigger3DAction(type: "pat")
                            } label: {
                                Text("👋 摸摸跳躍")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .foregroundColor(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                trigger3DAction(type: "swoop")
                            } label: {
                                Text(petState.species == .bird ? "🪽 3D 衝刺飛翔" : (petState.species == .dog ? "🦴 3D 飛奔巡邏" : "🐾 3D 躍動招手"))
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .foregroundColor(.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                trigger3DAction(type: "coin")
                            } label: {
                                Text("🪙 投 3D 金幣")
                                    .font(.system(size: 13, weight: .heavy))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(hex: "#FDE047"), Color(hex: "#F59E0B")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .foregroundColor(Color(hex: "#451A03"))
                                    .clipShape(Capsule())
                                    .shadow(color: Color(hex: "#F59E0B").opacity(0.35), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)

                            if petState.species == .dog {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    isDogSitting.toggle()
                                    quoteText = isDogSitting ? "乖乖坐下顧聚寶盆，3D 尾巴繼續搖汪！" : "精力充沛站起來在 3D 綠茵島奔跑汪！"
                                } label: {
                                    Text(isDogSitting ? "🐕 站起來" : "🐶 坐下")
                                        .font(.system(size: 13, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.secondarySystemBackground))
                                        .foregroundColor(Color(hex: "#9A3412"))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach(auras) { aura in
                                Text("\(aura.icon) \(aura.text)")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: aura.colorHex).opacity(0.15))
                                    .foregroundColor(Color(hex: aura.colorHex))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // 成長進度與餵食
                    VStack(spacing: 10) {
                        HStack {
                            Text("晉升階位 (第 \(levelInfo.stage)/20 階)")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Text("\(levelInfo.currentXP) / \(levelInfo.needXP) XP")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "#007AFF"))
                        }
                        ProgressView(value: levelInfo.progress)
                            .tint(Color(hex: "#F59E0B"))

                        Button {
                            let res = PetService.shared.feedAllPending()
                            petState = res.state
                            if res.fedAmount > 0 {
                                trigger3DAction(type: "coin")
                            }
                        } label: {
                            HStack {
                                Text("🪙 餵食全部待領股息點數 (\(petState.pendingFeedDP) DP)")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(petState.pendingFeedDP > 0 ? Color(hex: "#007AFF") : Color(.systemGray4))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(petState.pendingFeedDP <= 0)

                        Text("手指左右拖曳可 360° 旋轉 3D 視角；點擊地面可投擲 3D 金幣吸引寵物追逐。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                }
                .padding()
            }
            .navigationTitle("3D 財富寵物樂園")
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
    @State private var bridgeServerURL = ""
    @State private var sinopacDirectText = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("對接模式", selection: $selectedTab) {
                    Text("📸 拍照辨識").tag(3)
                    Text("對帳單匯入").tag(1)
                    Text("永豐 API").tag(2)
                    Text("已支援券商").tag(0)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 3 {
                    PhotoOCRScannerViewContent(onImportCompleted: { _ in
                        onSyncCompleted()
                        dismiss()
                    })
                } else if selectedTab == 1 {
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
                            
                            Text("永豐 Shioaji 官方為 Python SDK。您可透過電腦端中繼服務 (shioaji_bridge.py) 自動抓取，或直接貼上大戶投 App 庫存明細！")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // 方式 A: Python 中繼服務直連
                            VStack(alignment: .leading, spacing: 10) {
                                Text("【方式 A】Python 中繼伺服器直連 (自動化)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color(hex: "#FF9500"))
                                
                                TextField("中繼伺服器網址 (例: http://192.168.1.100:8000)", text: $bridgeServerURL)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                
                                TextField("Shioaji API Key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                SecureField("Secret Key", text: $secretKey)
                                    .textFieldStyle(.roundedBorder)
                                
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
                                
                                Button {
                                    guard !bridgeServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                        shioajiStatusMessage = "⚠️ 請填寫中繼伺服器網址 (例: http://192.168.1.100:8000)，或改用下方方式 B 直接貼上！"
                                        return
                                    }
                                    isConnectingShioaji = true
                                    shioajiStatusMessage = "連線中繼伺服器中..."
                                    BrokerageService.shared.fetchPositionsFromShioajiBridge(
                                        bridgeURL: bridgeServerURL,
                                        apiKey: apiKey,
                                        secretKey: secretKey,
                                        certPath: certPath
                                    ) { result in
                                        DispatchQueue.main.async {
                                            isConnectingShioaji = false
                                            switch result {
                                            case .success(let holdings):
                                                if holdings.isEmpty {
                                                    shioajiStatusMessage = "連線成功，但您的永豐帳戶目前無證券庫存持股。"
                                                } else {
                                                    let count = StorageService.shared.batchImportHoldings(holdings)
                                                    shioajiStatusMessage = "✅ 成功自永豐 Shioaji 同步 \(count) 筆真實個人持股！"
                                                    onSyncCompleted()
                                                }
                                            case .failure(let error):
                                                shioajiStatusMessage = "❌ 連線失敗：\(error.localizedDescription)\n請確認電腦已啟動 shioaji_bridge.py 且位於相同區網。"
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if isConnectingShioaji {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "link")
                                        }
                                        Text("連線中繼伺服器並同步真實持股")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(hex: "#FF9500"))
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            
                            // 方式 B: 大戶投庫存文字直接貼上
                            VStack(alignment: .leading, spacing: 10) {
                                Text("【方式 B】大戶投庫存一鍵貼上 (免跑伺服器、手機最快)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(Color(hex: "#007AFF"))
                                
                                Text("至永豐「大戶投 App」→「未實現損益」全選複製文字貼於此：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                TextEditor(text: $sinopacDirectText)
                                    .frame(height: 100)
                                    .padding(6)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                
                                Button {
                                    let parsed = BrokerageService.shared.parseBrokerageText(sinopacDirectText, brokerageName: "永豐金證券 (大戶投)")
                                    if !parsed.isEmpty {
                                        let count = StorageService.shared.batchImportHoldings(parsed)
                                        shioajiStatusMessage = "✅ 已成功匯入 \(count) 筆您本人的永豐大戶投持股！"
                                        sinopacDirectText = ""
                                        onSyncCompleted()
                                    } else {
                                        shioajiStatusMessage = "⚠️ 解析失敗，請確認已貼上正確的股票代號與股數。"
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.down.doc.fill")
                                        Text("匯入本人真實永豐持股")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(sinopacDirectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color(hex: "#007AFF"))
                                    .cornerRadius(10)
                                }
                                .disabled(sinopacDirectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            
                            if !shioajiStatusMessage.isEmpty {
                                Text(shioajiStatusMessage)
                                    .font(.caption.bold())
                                    .foregroundColor(shioajiStatusMessage.contains("✅") ? Color(hex: "#34C759") : Color(hex: "#FF3B30"))
                                    .padding(.horizontal, 4)
                            }
                            
                            // 輔助按鈕：清除先前誤匯的永豐持股
                            Button(role: .destructive) {
                                StorageService.shared.deleteHoldings(forBrokerage: "永豐金證券")
                                shioajiStatusMessage = "🗑️ 已清空先前建立的永豐金證券持股。"
                                onSyncCompleted()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("一鍵清除先前誤匯入的永豐持股")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
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

// MARK: ==========================================
// MARK: 📸 照片/截圖 OCR 智慧辨識 (Apple Vision 引擎)
// MARK: ==========================================

struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    var onImageCaptured: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotoOCRScannerViewContent: View {
    var onImportCompleted: ([StockHolding]) -> Void
    
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var isShowingCamera = false
    @State private var isRecognizing = false
    @State private var recognizedHoldings: [StockHolding] = []
    @State private var statusMessage = ""
    @State private var showCameraUnavailableAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 頂部選擇區塊
                HStack(spacing: 12) {
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            isShowingCamera = true
                        } else {
                            showCameraUnavailableAlert = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("立即拍照")
                        }
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#FF9500"))
                        .cornerRadius(12)
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("相簿選取截圖")
                        }
                        .font(.headline.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "#007AFF"))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Text("💡 支援永豐大戶投、元大、國泰、富邦等各大券商之「庫存損益」截圖或對帳單相片，Apple Vision 本機神經網路毫秒級離線自動識別！")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // 影像預覽區
                if let image = pickedImage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("影像預覽")
                                .font(.subheadline.bold())
                            Spacer()
                            if isRecognizing {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Vision 智慧辨識中...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal)
                }
                
                // 辨識結果確認與校對清單
                if !recognizedHoldings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("已識別 \(recognizedHoldings.count) 檔真實持股")
                                .font(.headline.bold())
                            Spacer()
                            Text("可直接修改股數與均價")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach($recognizedHoldings) { $h in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(h.symbol).font(.headline.bold())
                                        Text(h.name).font(.subheadline).foregroundColor(.secondary)
                                    }
                                    Text(h.frequency.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color(hex: h.frequency.badgeColorHex).opacity(0.15))
                                        .foregroundColor(Color(hex: h.frequency.badgeColorHex))
                                        .cornerRadius(4)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("股數:").font(.caption).foregroundColor(.secondary)
                                        TextField("股數", value: $h.shares, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 75)
                                            .keyboardType(.numberPad)
                                            .multilineTextAlignment(.trailing)
                                    }
                                    HStack(spacing: 4) {
                                        Text("均價:").font(.caption).foregroundColor(.secondary)
                                        TextField("均價", value: $h.averageCost, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 75)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                                
                                Button {
                                    recognizedHoldings.removeAll { $0.id == h.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.body)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        
                        // 一鍵確認匯入按鈕
                        Button {
                            _ = StorageService.shared.batchImportHoldings(recognizedHoldings)
                            onImportCompleted(recognizedHoldings)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("確認匯入 \(recognizedHoldings.count) 檔持股至持有現股")
                            }
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "#34C759"))
                            .cornerRadius(12)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal)
                } else if pickedImage != nil && !isRecognizing {
                    VStack(spacing: 8) {
                        Text("⚠️ 未能在該相片中識別出明確的台股代號")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                        Text("建議請近距離拍攝清楚的股票代號（例如 2330、0056）與股數數字。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .padding(.vertical)
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let newItem = newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        processImage(uiImage)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraView { capturedImage in
                processImage(capturedImage)
            }
        }
        .alert("無法啟動相機", isPresented: $showCameraUnavailableAlert) {
            Button("確定") {}
        } message: {
            Text("此裝置未具備相機硬體，請改用「相簿選取截圖」功能！")
        }
    }
    
    private func processImage(_ image: UIImage) {
        pickedImage = image
        isRecognizing = true
        recognizedHoldings = []
        
        StockOCRService.shared.recognizeStocks(from: image) { result in
            DispatchQueue.main.async {
                isRecognizing = false
                switch result {
                case .success(let items):
                    recognizedHoldings = items
                case .failure(let error):
                    statusMessage = "辨識失敗：\(error.localizedDescription)"
                }
            }
        }
    }
}

struct PhotoOCRScannerSheet: View {
    @Environment(\.dismiss) var dismiss
    var onImportCompleted: ([StockHolding]) -> Void
    
    var body: some View {
        NavigationStack {
            PhotoOCRScannerViewContent { holdings in
                onImportCompleted(holdings)
                dismiss()
            }
            .navigationTitle("📸 拍照 / 截圖自動辨識")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
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
