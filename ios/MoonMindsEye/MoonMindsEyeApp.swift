// 2026-11-14 3:10 PM CST — Moon Mind's Eye iPhone app: entry point and tabs
import SwiftUI

@main
struct MoonMindsEyeApp: App {
    @StateObject private var location = LocationModel()
    @StateObject private var camera = CameraModel()

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
            .preferredColorScheme(.dark)
            .tint(Color(red: 0.96, green: 0.78, blue: 0.42))
            .onAppear { location.start() }
        }
    }
}
