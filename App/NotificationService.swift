import Foundation
import UserNotifications

public final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private let notificationsEnabledKey = "is_dividend_notifications_enabled_v2"
    
    private override init() {
        super.init()
        center.delegate = self
    }
    
    public var isNotificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }
    
    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.isNotificationsEnabled = granted
                completion(granted)
            }
        }
    }
    
    public func checkAuthorization(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                let isAuth = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                completion(isAuth)
            }
        }
    }
    
    public func syncDividendReminders(events: [DividendEvent], holdings: [StockHolding]) {
        guard isNotificationsEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }
        
        center.removeAllPendingNotificationRequests()
        let holdingDict = Dictionary(uniqueKeysWithValues: holdings.map { ($0.symbol, $0) })
        let calendar = Calendar.current
        let now = Date()
        
        for event in events {
            guard event.targetDate > now else { continue }
            
            // 提醒 1: 前一天 08:30 (除息提醒 / 最後買進日)
            if let reminderDate = calendar.date(byAdding: .day, value: -1, to: event.targetDate), reminderDate > now {
                var comp = calendar.dateComponents([.year, .month, .day], from: reminderDate)
                comp.hour = 8
                comp.minute = 30
                
                let content = UNMutableNotificationContent()
                let heldShares = holdingDict[event.symbol]?.shares ?? event.sharesSnapshot
                let estMoney = (heldShares > 0 && event.cashPerShare > 0)
                    ? "，持有 \(heldShares.formatted()) 股預估入帳 $\(Int(Double(heldShares) * event.cashPerShare).formatted()) 元"
                    : ""
                
                content.title = "🔔【除息前提醒】\(event.symbol) \(event.name)"
                content.body = "明日即將迎來 \(event.eventType.rawValue)！每股配息 $\(String(format: "%.2f", event.cashPerShare)) 元\(estMoney)。"
                content.sound = .default
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
                let req = UNNotificationRequest(identifier: "div_pre_\(event.id.uuidString)", content: content, trigger: trigger)
                center.add(req)
            }
            
            // 提醒 2: 當天 08:30 (今天除息日 / 股利發放日)
            var dayComp = calendar.dateComponents([.year, .month, .day], from: event.targetDate)
            dayComp.hour = 8
            dayComp.minute = 30
            
            let contentToday = UNMutableNotificationContent()
            contentToday.title = "📅【今日除權息】\(event.symbol) \(event.name)"
            contentToday.body = "今天是 \(event.eventType.rawValue)！每股配發 $\(String(format: "%.2f", event.cashPerShare)) 元，請留意帳戶入帳！"
            contentToday.sound = .default
            
            let triggerToday = UNCalendarNotificationTrigger(dateMatching: dayComp, repeats: false)
            let reqToday = UNNotificationRequest(identifier: "div_day_\(event.id.uuidString)", content: contentToday, trigger: triggerToday)
            center.add(reqToday)
        }
    }
    
    // 前台顯示通知 Banner
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
