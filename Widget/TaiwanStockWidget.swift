import WidgetKit
import SwiftUI

struct StockTimelineEntry: TimelineEntry {
    let date: Date
    let summary: WidgetDataSummary
}

struct StockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StockTimelineEntry {
        StockTimelineEntry(date: Date(), summary: StorageService.shared.loadWidgetSummary())
    }

    func getSnapshot(in context: Context, completion: @escaping (StockTimelineEntry) -> Void) {
        completion(StockTimelineEntry(date: Date(), summary: StorageService.shared.loadWidgetSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StockTimelineEntry>) -> Void) {
        let summary = StorageService.shared.loadWidgetSummary()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [StockTimelineEntry(date: Date(), summary: summary)], policy: .after(nextUpdate)))
    }
}

struct TaiwanStockWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: StockTimelineEntry
    
    var isProfit: Bool { entry.summary.unrealizedProfit >= 0 }
    var twColor: Color {
        if entry.summary.unrealizedProfit > 0.0001 { return .red }
        if entry.summary.unrealizedProfit < -0.0001 { return .green }
        return .secondary
    }

    var body: some View {
        switch family {
        // MARK: - 鎖定畫面時鐘頂部文字 (accessoryInline)
        case .accessoryInline:
            HStack(spacing: 2) {
                Image(systemName: isProfit ? "arrow.up.right" : "arrow.down.right")
                Text("台股 \(isProfit ? "+" : "")\(Int(entry.summary.unrealizedProfit).formatted()) (\(String(format: "%.1f", entry.summary.returnRate))%)")
            }

        // MARK: - 鎖定畫面環形進度 (accessoryCircular)
        case .accessoryCircular:
            Gauge(value: min(1.0, max(0.0, entry.summary.currentMonthEstimatedCash / 20000.0))) {
                Image(systemName: "dollarsign.circle")
            } currentValueLabel: {
                Text("\(Int(entry.summary.currentMonthEstimatedCash / 1000))k")
                    .font(.system(size: 11, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)

        // MARK: - 鎖定畫面矩形卡片 (accessoryRectangular) - 總市值 + 損益 + 每月配股配息
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("台股市值")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("$\(Int(entry.summary.totalMarketValue).formatted())")
                        .font(.system(size: 11, weight: .bold))
                }
                HStack {
                    Text("未實現損益")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("\(isProfit ? "+" : "")\(Int(entry.summary.unrealizedProfit).formatted()) (\(String(format: "%.1f", entry.summary.returnRate))%)")
                        .font(.system(size: 10, weight: .semibold))
                }
                HStack {
                    Text("本月配股息")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("$\(Int(entry.summary.currentMonthEstimatedCash).formatted()) / +\(entry.summary.currentMonthStockShares)股")
                        .font(.system(size: 10, weight: .semibold))
                }
            }

        // MARK: - 桌面中型小工具 (systemMedium)
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("台股總資產")
                        .font(.caption).foregroundColor(.secondary)
                    Text("$\(Int(entry.summary.totalMarketValue).formatted())")
                        .font(.title2.bold())
                    
                    HStack(spacing: 4) {
                        Image(systemName: isProfit ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        Text("\(isProfit ? "+" : "")\(Int(entry.summary.unrealizedProfit).formatted()) (\(String(format: "%.2f", entry.summary.returnRate))%)")
                    }
                    .font(.footnote.bold())
                    .foregroundColor(twColor)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月預估配息")
                        .font(.caption).foregroundColor(.secondary)
                    Text("$\(Int(entry.summary.currentMonthEstimatedCash).formatted())")
                        .font(.headline).foregroundColor(.orange)
                    
                    Text("本月預估配股：+\(entry.summary.currentMonthStockShares) 股")
                        .font(.caption).foregroundColor(.blue)
                    Text("主要持股：\(entry.summary.topHoldingName)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(8)

        default:
            Text("台股 $\(Int(entry.summary.totalMarketValue))")
        }
    }
}

// 擴充相容 iOS 16 與 iOS 17 的 Widget Background 規範
extension View {
    func widgetBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            return self.containerBackground(for: .widget) { Color.clear }
        } else {
            return self.background(Color.clear)
        }
    }
}

@main
struct TaiwanStockWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaiwanStockWidget()
    }
}

struct TaiwanStockWidget: Widget {
    let kind: String = "TaiwanStockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StockTimelineProvider()) { entry in
            TaiwanStockWidgetEntryView(entry: entry)
                .widgetBackgroundCompat()
        }
        .configurationDisplayName("台股績效與配股監控")
        .description("在鎖定畫面顯示總市值、未實現損益與每月配股配息進度。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemMedium
        ])
    }
}
