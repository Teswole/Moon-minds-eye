// 2026-11-20 10:40 PM CST — Moon Mind's Eye iPhone app: the full page, with the pro camera and alerts built in
import SwiftUI

@main
struct MoonMindsEyeApp: App {
    @StateObject private var location = LocationModel()
    @StateObject private var camera = CameraModel()
    @StateObject private var alerts = MoonAlerts()

    var body: some Scene {
        WindowGroup {
            AppShell()
            .environmentObject(location)
            .environmentObject(camera)
            .environmentObject(alerts)
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.96, green: 0.78, blue: 0.42))
            .onAppear { location.start() }
        }
    }
}
