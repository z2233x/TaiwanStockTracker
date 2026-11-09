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

    var body: some View {
        switch family {
        // MARK: - 鎖定畫面頂部文字行 (accessoryInline)
        case .accessoryInline:
            HStack(spacing: 2) {
                Image(systemName: isProfit ? "arrow.up.right" : "arrow.down.right")
                Text("台股 $\(Int(entry.summary.totalMarketValue).formatted()) (\(entry.summary.nextEventTitle) \(entry.summary.nextEventCountdown))")
            }

        // MARK: - 鎖定畫面環形小工具 (accessoryCircular)
        case .accessoryCircular:
            Gauge(value: min(1.0, max(0.0, entry.summary.totalDividendsReceived / 10000.0))) {
                Image(systemName: "dollarsign.circle")
            } currentValueLabel: {
                Text("\(Int(entry.summary.totalDividendsReceived / 1000))k")
                    .font(.system(size: 11, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)

        // MARK: - 鎖定畫面矩形卡片 (accessoryRectangular) - 總值 + 損益 + 最近除息倒數
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
                    Text("價差獲利")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text("\(isProfit ? "+" : "")\(Int(entry.summary.unrealizedProfit).formatted()) (\(String(format: "%.1f", entry.summary.returnRate))%)")
                        .font(.system(size: 10, weight: .semibold))
                }
                HStack {
                    Text(entry.summary.nextEventTitle)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(entry.summary.nextEventCountdown)
                        .font(.system(size: 10, weight: .bold))
                }
            }

        default:
            Text("$\(Int(entry.summary.totalMarketValue))")
        }
    }
}

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
        .configurationDisplayName("台股與ETF股息監控")
        .description("在鎖定畫面顯示總市值、價差獲利與最近除權息倒數天數。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}
