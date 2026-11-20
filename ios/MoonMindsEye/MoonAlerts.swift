// 2026-11-20 2:20 AM CST — Big-moon alerts: phone notifications before each low-moon window (no calendar needed)
import Foundation
import UserNotifications
import SwiftUI

final class MoonAlerts: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @AppStorage("alertsOn") var on = false { didSet { objectWillChange.send() } }
    @AppStorage("alertLead") var lead = 15 { didSet { objectWillChange.send() } }        // minutes before the window
    @AppStorage("alertBright") var brightOnly = true { didSet { objectWillChange.send() } } // only nights at least 40% lit
    @Published var upcoming: [(start: Date, end: Date, lit: Int, dir: String)] = []
    @Published var note = ""
    @Published var blocked = false

    private let center = UNUserNotificationCenter.current()
    private let prefix = "bigmoon-"

    override init() { super.init(); center.delegate = self }

    /// Show the alert as a banner even while the app is open
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }

    /// Work out the next 2 weeks of windows and (re)schedule the alerts
    func refresh(lat: Double, lng: Double) {
        let wins = MoonMath.windows(from: Date(), lat: lat, lng: lng, days: 14).compactMap { w -> (Date, Date, Int, String)? in
            let m = MoonMath.moon(w.start, lat: lat, lng: lng), lit = Int((m.fraction * 100).rounded())
            if brightOnly && lit < 40 { return nil }
            return (w.start, w.end, lit, MoonAlerts.dirName(MoonMath.compass(m.bearing)))
        }
        DispatchQueue.main.async { self.upcoming = wins.map { (start: $0.0, end: $0.1, lit: $0.2, dir: $0.3) } }
        clear {
            guard self.on else { DispatchQueue.main.async { self.note = "" }; return }
            self.center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                guard ok else { DispatchQueue.main.async { self.blocked = true; self.note = "Notifications are off for this app. Turn them on in Settings → Notifications → Moon Mind's Eye." }; return }
                DispatchQueue.main.async { self.blocked = false }
                let t = DateFormatter(); t.dateFormat = "h:mm a"
                var count = 0
                for (i, w) in wins.prefix(30).enumerated() {
                    let span = "\(t.string(from: w.0))–\(t.string(from: w.1))"
                    let before = w.0.addingTimeInterval(-Double(self.lead) * 60)
                    if before > Date() {
                        self.add(id: "\(self.prefix)\(i)a", at: before, title: "🌙 Big moon in \(self.lead) minutes",
                                 body: "Look \(w.3), low over the horizon. Best window \(span). \(w.2)% lit. Open the camera and let the Shot Coach help!")
                        count += 1
                    }
                    if w.0 > Date() {
                        self.add(id: "\(self.prefix)\(i)b", at: w.0, title: "🌙 The big moon is up now",
                                 body: "Look \(w.3). The best window lasts until \(t.string(from: w.1)).")
                    }
                }
                DispatchQueue.main.async { self.note = count == 0 ? "No big-moon windows in the next 2 weeks with these settings." : "Alerts are set for the next \(count) big-moon windows. They refresh each time you open the app." }
            }
        }
    }

    private func add(id: String, at date: Date, title: String, body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    private func clear(then: @escaping () -> Void) {
        center.getPendingNotificationRequests { reqs in
            self.center.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix(self.prefix) })
            then()
        }
    }

    static func dirName(_ c: String) -> String {
        let n = ["N": "north", "NNE": "north-northeast", "NE": "northeast", "ENE": "east-northeast", "E": "east", "ESE": "east-southeast",
                 "SE": "southeast", "SSE": "south-southeast", "S": "south", "SSW": "south-southwest", "SW": "southwest", "WSW": "west-southwest",
                 "W": "west", "WNW": "west-northwest", "NW": "northwest", "NNW": "north-northwest"]
        return n[c] ?? c
    }
}
