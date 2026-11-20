// 2026-11-20 2:25 AM CST — Moon Mind's Eye iPhone app: entry point and tabs
import SwiftUI

@main
struct MoonMindsEyeApp: App {
    @StateObject private var location = LocationModel()
    @StateObject private var camera = CameraModel()
    @StateObject private var alerts = MoonAlerts()

    var body: some Scene {
        WindowGroup {
            TabView {
                MoonView()
                    .tabItem { Label("Moon", systemImage: "moon.stars") }
                CameraView()
                    .tabItem { Label("Camera", systemImage: "camera") }
            }
            .environmentObject(location)
            .environmentObject(camera)
            .environmentObject(alerts)
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.96, green: 0.78, blue: 0.42))
            .onAppear { location.start() }
        }
    }
}
