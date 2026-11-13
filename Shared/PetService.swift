import Foundation

public enum PetSpecies: String, CaseIterable, Codable, Identifiable {
    case cat
    case bird
    case dog

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cat: return "招財貓"
        case .bird: return "貪錢鳥"
        case .dog: return "財氣犬"
        }
    }

    public var badgeText: String {
        switch self {
        case .cat: return "🐱 金庫招財系"
        case .bird: return "🐦 複利獵手系"
        case .dog: return "🐶 忠實守息系"
        }
    }

    public var avatarImageName: String {
        switch self {
        case .cat: return "pet_cat"
        case .bird: return "pet_bird"
        case .dog: return "pet_dog"
        }
    }

    public var cardImageName: String {
        switch self {
        case .cat: return "pet_cat_card"
        case .bird: return "pet_bird_card"
        case .dog: return "pet_dog_card"
        }
    }

    public var tagline: String {
        switch self {
        case .cat: return "右爪一招，月配股息穩穩入庫。"
        case .bird: return "緊抱每枚配息金幣，精算再投入複利。"
        case .dog: return "長抱不放手，幫你咬住每一張配息存摺。"
        }
    }

    public var downMarketLine: String {
        switch self {
        case .cat: return "大盤整理中，先戴安全帽守著金庫等除息喵！"
        case .bird: return "貼息不賣股！金幣抱緊緊等填息爆發啾！"
        case .dog: return "就算帳面浮虧，我也幫你咬住籌碼不放汪！"
        }
    }

    public var stageNames: [String] {
        switch self {
        case .cat:
            return ["小瓷招財貓", "金判招財貓", "御守招財王", "雙幣聚財貓", "白金招財尊爵"]
        case .bird:
            return ["愛幣小雀", "金冠吸金鳥", "分析師金鳥", "聚寶飛羽鳥", "黃金複利鳳凰"]
        case .dog:
            return ["小赤財氣犬", "咬券小財柴", "金鈴護息犬", "御守守財柴", "白金聚財神犬"]
        }
    }
}

public enum PetCardTheme: String, CaseIterable, Codable, Identifiable {
    case fortune
    case defaultLight
    case obsidian
    case sakura

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fortune: return "財運紅金"
        case .defaultLight: return "極簡純白"
        case .obsidian: return "曜石黑金"
        case .sakura: return "晨曦櫻花"
        }
    }

    public var costDP: Int {
        switch self {
        case .fortune: return 0
        case .defaultLight: return 0
        case .obsidian: return 80
        case .sakura: return 150
        }
    }

    public var isDarkBackground: Bool {
        self == .fortune || self == .obsidian
    }
}

public struct PetLevelInfo {
    public let level: Int
    public let currentXP: Int
    public let needXP: Int
    public let stage: Int

    public var progress: Double {
        needXP > 0 ? min(1.0, Double(currentXP) / Double(needXP)) : 1.0
    }
}

public struct PetAuraBadge: Identifiable {
    public var id: String { text }
    public let icon: String
    public let text: String
    public let colorHex: String
}

public struct DividendPetState: Codable {
    public var species: PetSpecies = .cat
    public var totalXP: Int = 0
    public var spendableDP: Int = 0
    public var pendingFeedDP: Int = 60 // 新手見面禮 60 DP，首次開啟即可體驗餵食
    public var claimedRecordIDs: [String] = []
    public var unlockedThemes: [String] = [PetCardTheme.fortune.rawValue, PetCardTheme.defaultLight.rawValue]
    public var activeTheme: PetCardTheme = .fortune

    public init() {}
}

public final class PetService {
    public static let shared = PetService()

    private let userDefaults = UserDefaults(suiteName: StorageService.appGroupId) ?? .standard
    private let stateKey = "saved_dividend_pet_state_v1"

    private init() {}

    public func loadState() -> DividendPetState {
        guard let data = userDefaults.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(DividendPetState.self, from: data) else {
            return DividendPetState()
        }
        return decoded
    }

    public func saveState(_ state: DividendPetState) {
        if let encoded = try? JSONEncoder().encode(state) {
            userDefaults.set(encoded, forKey: stateKey)
        }
    }

    public func levelInfo(for totalXP: Int) -> PetLevelInfo {
        var lv = 1
        var remaining = max(0, totalXP)
        while lv < 99 {
            let need = Int((40.0 * pow(Double(lv), 1.45)).rounded())
            if remaining < need {
                let stage: Int
                if lv >= 80 { stage = 5 }
                else if lv >= 50 { stage = 4 }
                else if lv >= 25 { stage = 3 }
                else if lv >= 10 { stage = 2 }
                else { stage = 1 }
                return PetLevelInfo(level: lv, currentXP: remaining, needXP: need, stage: stage)
            }
            remaining -= need
            lv += 1
        }
        return PetLevelInfo(level: 99, currentXP: 0, needXP: 1, stage: 5)
    }

    @discardableResult
    public func syncDividendPoints(holdings: [StockHolding], histories: [HoldingDividendHistory]) -> DividendPetState {
        var state = loadState()
        var claimed = Set(state.claimedRecordIDs)
        var added = 0

        for rec in histories {
            let cid = "hist_\(rec.id.uuidString)"
            if !claimed.contains(cid) {
                let dp = max(1, Int(floor(rec.totalReceived / 100.0)))
                added += dp
                claimed.insert(cid)
            }
        }

        // 若持有現股本身已有匯入之總股息、但尚無對應歷史流水，給予一次初始里程碑點數
        let symbolsWithHistory = Set(histories.map { $0.symbol })
        for h in holdings where h.totalDividendsReceived > 0 && !symbolsWithHistory.contains(h.symbol) {
            let cid = "holding_base_\(h.symbol)"
            if !claimed.contains(cid) {
                let dp = max(1, Int(floor(h.totalDividendsReceived / 100.0)))
                added += dp
                claimed.insert(cid)
            }
        }

        if added > 0 {
            state.pendingFeedDP += added
            state.claimedRecordIDs = Array(claimed)
            saveState(state)
        }
        return state
    }

    public func feedAllPending() -> (state: DividendPetState, fedAmount: Int) {
        var state = loadState()
        let amount = state.pendingFeedDP
        guard amount > 0 else { return (state, 0) }
        state.totalXP += amount
        state.spendableDP += amount
        state.pendingFeedDP = 0
        saveState(state)
        return (state, amount)
    }

    public func selectSpecies(_ species: PetSpecies) -> DividendPetState {
        var state = loadState()
        state.species = species
        saveState(state)
        return state
    }

    public func buyOrApplyTheme(_ theme: PetCardTheme) -> (state: DividendPetState, insufficient: Bool) {
        var state = loadState()
        var unlocked = Set(state.unlockedThemes)
        if theme.costDP == 0 || unlocked.contains(theme.rawValue) {
            unlocked.insert(theme.rawValue)
            state.unlockedThemes = Array(unlocked)
            state.activeTheme = theme
            saveState(state)
            return (state, false)
        }
        guard state.spendableDP >= theme.costDP else {
            return (state, true)
        }
        state.spendableDP -= theme.costDP
        unlocked.insert(theme.rawValue)
        state.unlockedThemes = Array(unlocked)
        state.activeTheme = theme
        saveState(state)
        return (state, false)
    }

    public func auras(for holdings: [StockHolding], summary: PortfolioDividendSourceSummary) -> [PetAuraBadge] {
        var result: [PetAuraBadge] = []
        if summary.taxExemptPercent >= 50 {
            result.append(PetAuraBadge(icon: "🛡️", text: "節稅護盾 \(Int(summary.taxExemptPercent.rounded()))%", colorHex: "#34C759"))
        }
        let freqs = Set(holdings.map { $0.frequency })
        if freqs.contains(.monthly) || freqs.count >= 2 {
            result.append(PetAuraBadge(icon: "♾️", text: "現金流節奏", colorHex: "#007AFF"))
        }
        let growthSymbols: Set<String> = ["0050", "006208", "2330", "2454"]
        if holdings.contains(where: { growthSymbols.contains($0.symbol) }) {
            result.append(PetAuraBadge(icon: "🚀", text: "成長尾翼", colorHex: "#5856D6"))
        }
        if result.isEmpty {
            result.append(PetAuraBadge(icon: "🌱", text: "存股啟航中", colorHex: "#8E8E93"))
        }
        return result
    }
}
